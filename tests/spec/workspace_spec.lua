local workspace = require("gaanim.workspace")
local project_mod = require("gaanim.project")

local root = vim.fs.joinpath(FIXTURES, "channel")
local intro = vim.fs.joinpath(root, "videos", "intro")
local kickoff = vim.fs.joinpath(root, "talks", "kickoff")

--- What `gaanim project --json` says of videos/intro/main.py, with this
--- checkout's paths.
local function described()
  local text = table.concat(vim.fn.readfile(vim.fs.joinpath(FIXTURES, "channel.project.json")), "\n")
  local object = vim.json.decode((text:gsub("{root}", root)), { luanil = { object = true, array = true } })
  return workspace.decode(object)
end

---@param path string
local function edit(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
end

describe("workspace manifests", function()
  it("reads what a workspace's gaanim.toml declares", function()
    local info = workspace.manifest(root)
    eq(true, info.workspace)
    eq(false, info.project)
    eq("channel", info.name)
    eq({ "common" }, info.python, "a comment after the array stays out")
    eq({ "media" }, info.assets, "an array over several lines")
  end)

  it("is no project, and its members are", function()
    eq(true, workspace.is_root(root))
    eq(nil, project_mod.load(root))
    eq("video", project_mod.load(intro).kind)
    eq(false, workspace.is_root(intro))
    eq(root, workspace.root_above(intro))
    eq(nil, workspace.root_above(vim.fs.joinpath(FIXTURES, "talk")))
  end)

  it("knows the shared folders without gaanim", function()
    eq({ vim.fs.joinpath(root, "common") }, workspace.shared(root, "python"))
    eq({ vim.fs.joinpath(root, "media") }, workspace.shared(root, "assets"))
    eq(true, workspace.is_shared(root, vim.fs.joinpath(root, "common", "style.py")))
    eq(false, workspace.is_shared(root, vim.fs.joinpath(root, "sketch.py")))
  end)

  it("matches members as --members does", function()
    eq(true, workspace.matches("videos/*", "videos/intro"))
    eq(false, workspace.matches("videos/*", "videos/intro/extra"))
    eq(true, workspace.matches("talks/kick*", "talks/kickoff"))
    eq(false, workspace.matches("talks/*", "videos/intro"))
  end)
end)

describe("gaanim project", function()
  it("reads its JSON the plugin's way", function()
    local description = described()
    eq(intro, description.project.root)
    eq("channel › intro", description.project.display_name)
    eq(root, description.workspace.root)
    eq({ vim.fs.joinpath(root, "common") }, description.workspace.python)
    eq(3, #description.workspace.members)
    eq("Videos", description.workspace.members[1].group)
    local broken = description.workspace.members[2]
    eq(nil, broken.kind)
    eq(nil, broken.error:find("\\\\?\\", 1, true), "no Windows verbatim prefix")
    eq(vim.fs.joinpath(root, ".venv", "Scripts", "python.exe"), description.python.interpreter)
  end)

  it("selects members by path or pattern", function()
    local ws = described().workspace
    eq(
      { "videos/intro", "videos/outro" },
      vim.tbl_map(function(member)
        return member.path
      end, workspace.select(ws, "videos/*"))
    )
    eq(3, #workspace.select(ws, nil))
    eq("talks/kickoff", workspace.select(ws, "talks/kickoff, nothing/*")[1].path)
    eq(kickoff, workspace.member(ws, "talks/kickoff").root)
    eq("Videos › intro", workspace.label(workspace.member_at(ws, vim.fs.joinpath(intro, "main.py"))))
  end)
end)

describe("a workspace's own files", function()
  local style = vim.fs.joinpath(root, "common", "style.py")

  it("run as the active member", function()
    workspace.active = {}
    edit(style)
    eq(nil, project_mod.current(0), "no member entered yet")
    eq(false, project_mod.root_of(0))
    workspace.use(root, kickoff)
    eq(kickoff, project_mod.current(0).root)
    eq(kickoff, project_mod.root_of(0))
    vim.cmd("bwipeout!")
    workspace.active = {}
  end)

  it("leave a sketch outside the shared folders on its own", function()
    workspace.use(root, kickoff)
    edit(vim.fs.joinpath(root, "sketch.py"))
    local project = project_mod.current(0)
    eq("script", project.kind)
    eq(vim.fs.joinpath(root, "sketch.py"), project.entry)
    vim.cmd("bwipeout!")
    workspace.active = {}
  end)

  it("ask which member when there are several and none is active", function()
    workspace.active = {}
    edit(style)
    local ws = described().workspace
    local picked
    local original_describe, original_pick = workspace.describe, workspace.pick
    workspace.describe = function()
      return { workspace = ws, python = { paths = {} } }
    end
    workspace.pick = function(_, opts)
      picked = opts
    end
    local ran = false
    project_mod.retry = function()
      ran = true
    end
    eq(nil, project_mod.require(0))
    project_mod.retry = nil
    eq(true, picked.valid, "only members that can run")
    picked.on_choice(ws.members[1])
    eq(intro, workspace.active[root])
    eq(true, ran, "the command runs again with the member")
    workspace.describe, workspace.pick = original_describe, original_pick
    workspace.active = {}
    vim.cmd("bwipeout!")
  end)
end)

describe("pyright in a workspace", function()
  local lsp = require("gaanim.lsp")

  it("gets the shared interpreter and the sys.path folders", function()
    local description = described()
    local python = lsp.from_description(description, vim.fs.joinpath(intro, "main.py"), root)
    local settings =
      lsp.settings("basedpyright", { basedpyright = { analysis = { extraPaths = { "/mine" } } } }, python)
    eq(description.python.interpreter, settings.python.pythonPath)
    eq(
      { "/mine", intro, vim.fs.joinpath(root, "common") },
      settings.basedpyright.analysis.extraPaths,
      "not the client's root"
    )
    eq(nil, lsp.settings("basedpyright", settings, python), "nothing changes the second time")
  end)

  it("leaves out a file's own folder and keeps adding members", function()
    local python = {
      interpreter = "/ws/.venv/bin/python",
      paths = { "/ws/a/scenes", "/ws/a", "/ws/src", "/ws" },
      skip = { "/ws/a/scenes" },
    }
    local settings = lsp.settings("pyright", {}, python)
    eq({ "/ws/a", "/ws/src", "/ws" }, settings.python.analysis.extraPaths)
    settings = lsp.settings("pyright", settings, { paths = { "/ws/b", "/ws/src", "/ws" } })
    eq({ "/ws/a", "/ws/src", "/ws", "/ws/b" }, settings.python.analysis.extraPaths)
  end)

  it("finds the workspace's .venv without gaanim project", function()
    eq(nil, lsp.fallback(intro).interpreter, "the fixture has no environment")
  end)
end)

describe("shared assets", function()
  local assets = require("gaanim.server.assets")

  it("resolve names after the project's own folders", function()
    local project = project_mod.load(intro)
    eq(vim.fs.joinpath(root, "media"), assets.bases(project)[#assets.bases(project)])
    eq(vim.fs.joinpath(root, "media", "jingle.wav"), assets.resolve(project, "jingle.wav"))
    local files = assets.files(project, { "wav" })
    eq("jingle.wav", files[1].name)
    eq(true, files[1].shared)
    edit(vim.fs.joinpath(intro, "main.py"))
    eq({}, assets.diagnostics(project, 0), "jingle.wav is found in media/")
    vim.cmd("bwipeout!")
  end)
end)

describe("checking a workspace", function()
  local check = require("gaanim.check")

  it("gives each member its report", function()
    local ws = described().workspace
    local reports, order = check.workspace_reports(ws, {
      {
        type = "diagnostic",
        level = "warning",
        message = "segment `intro` has no notes",
        file = vim.fs.joinpath(intro, "main.py"),
        line = 4,
      },
      { type = "check", member = "videos/intro", result = "warning", segments = 1, duration = 2 },
      {
        type = "message",
        level = "error",
        label = "check",
        message = "could not load project: invalid project manifest \\\\?\\C:\\ws\\videos\\outro\\gaanim.toml",
      },
      { type = "check", member = "videos/outro", result = "error" },
      { type = "check", member = "talks/kickoff", result = "pass", segments = 3, duration = 9 },
      { type = "workspace", name = "channel", members = 3, passed = 2, failed = 1 },
    })
    eq({ "videos/intro", "videos/outro", "talks/kickoff" }, order)
    eq("warning", reports["videos/intro"].report.status)
    eq(4, reports["videos/intro"].report.items[1].lnum)
    eq("error", reports["videos/outro"].report.status)
    eq(vim.fs.joinpath(root, "videos", "outro", "gaanim.toml"), reports["videos/outro"].report.items[1].filename)
    eq(
      "could not load project: invalid project manifest C:\\ws\\videos\\outro\\gaanim.toml",
      reports["videos/outro"].report.items[1].text,
      "without Windows' verbatim prefix"
    )
    eq("pass", reports["talks/kickoff"].report.status)
  end)
end)

describe("exporting a workspace", function()
  local export = require("gaanim.export")
  local config = require("gaanim.config")

  it("names each member's file after its path", function()
    local ws = described().workspace
    local presets = config.get().export.presets
    eq(vim.fs.joinpath(root, "exports", "{member}.mp4"), export.workspace_output(ws, "mp4", presets.mp4))
    eq(vim.fs.joinpath(root, "exports", "{member}-draft.mp4"), export.workspace_output(ws, "draft", presets.draft))
    eq(vim.fs.joinpath(root, "exports", "{member}-1.5.png"), export.workspace_output(ws, "still", presets.still, "1.5"))
  end)
end)

describe("new members", function()
  local new = require("gaanim.new")

  it("go beside the members of their kind", function()
    local ws = described().workspace
    eq("videos/ep2", new.member_path(ws, "video", "ep2"))
    eq("talks/q3", new.member_path(ws, "slides", "q3"))
    eq("talks/", new.member_path(ws, "slides"))
    eq("shorts/one", new.member_path(ws, "video", "shorts/one"), "a path is from the workspace")
    eq("x", new.member_path({ members = {} }, "video", "x"))
  end)
end)

describe("listing projects", function()
  it("shows a workspace as one entry", function()
    local config = require("gaanim.config")
    local before = config.get().projects_dir
    config.get().projects_dir = FIXTURES
    local entries = project_mod.list()
    config.get().projects_dir = before
    local kinds = {}
    for _, entry in ipairs(entries) do
      kinds[vim.fs.basename(entry.root)] = entry.kind
    end
    eq("workspace", kinds.channel)
    eq("slides", kinds.talk)
    eq(nil, kinds.kickoff, "its members are reached through it")
  end)
end)
