-- The features that use a newer Gaanim: capabilities, JSON messages,
-- `gaanim inspect` and the preview's control channel.

local caps = require("gaanim.caps")
local check = require("gaanim.check")
local inspect = require("gaanim.inspect")
local project_mod = require("gaanim.project")

local root = vim.fs.joinpath(FIXTURES, "talk")
local main = vim.fs.joinpath(root, "main.py")

--- The timeline `gaanim inspect --json` printed for the fixture.
---@return gaanim.Timeline
local function timeline()
  local text = table.concat(vim.fn.readfile(vim.fs.joinpath(FIXTURES, "talk.inspect.json")), "\n")
  return vim.json.decode((text:gsub("{root}", root)), { luanil = { object = true, array = true } })
end

describe("caps", function()
  it("reads what a help text offers", function()
    local new = caps.parse(
      "COMMANDS\n  inspect <SCRIPT_OR_PROJECT> [--json]  List segments\nPREVIEW OPTIONS\n  --listen <stdio|HOST:PORT>  Let an editor\n  --message-format <FORMAT>   human or json",
      "  --frame <SECONDS|NAME>[,...]  Write exactly one PNG"
    )
    eq({ listen = true, json = true, inspect = true, names = true }, new)
    local old = caps.parse(
      "COMMANDS\n  init <video|slides> [DIR]\n  check <SCRIPT_OR_PROJECT>\nPREVIEW OPTIONS\n  --present  Present fullscreen, with a presenter window (the inspector)",
      "  --frame <SECONDS|MARKER>[,...]  Write exactly one PNG"
    )
    eq({ listen = false, json = false, inspect = false, names = false }, old)
  end)
end)

describe("JSON messages", function()
  local project = project_mod.load(root)

  it("places diagnostics where Gaanim says", function()
    local report = check.from_json(project, {
      {
        type = "diagnostic",
        level = "warning",
        message = "segment `Problem` contains unnamed stops",
        file = native(main),
        line = 17,
      },
      { type = "check", result = "pass", errors = 0, warnings = 1, segments = 3, stops = 4, duration = 2.8 },
    })
    eq("warning", report.status)
    eq("ready · 3 segments · 4 stops · 2.8 s", report.summary)
    eq({ main, 17, "W" }, { report.items[1].filename, report.items[1].lnum, report.items[1].type })
  end)

  it("finds the line of a load failure inside its traceback", function()
    local report = check.from_json(project, {
      {
        type = "message",
        level = "error",
        label = "check",
        message = 'could not load project: Traceback (most recent call last):\n  File "<string>", line 3, in <module>\n  File "'
          .. main
          .. '", line 25, in <module>\n    scene.stop()\nValueError: a stop already exists at 0.500000s in the active segment\n',
      },
    })
    eq("error", report.status)
    eq(25, report.items[1].lnum)
    eq("ValueError: a stop already exists at 0.500000s in the active segment", report.items[1].text)
  end)
end)

describe("inspect", function()
  it("takes the timeline among the printed objects", function()
    local data = timeline()
    eq(data, inspect.parse({ { type = "print" }, data }))
    eq(nil, inspect.parse({ { event = "ready" } }))
  end)

  it("knows the instant each line stands for", function()
    local data = timeline()
    local function at(line)
      local point = inspect.point_at(data, main, line)
      return point and { point.kind, point.time } or nil
    end
    eq(nil, at(5))
    eq({ "segment", 0.8 }, at(10), "a segment rests at its first stop")
    eq({ "play", 0.8 }, at(13))
    eq({ "stop", 1.3 }, at(23))
    eq({ "marker", 1.3 }, at(24))
    eq({ "voiceover", 1.8 }, at(29), "a line inside a block takes the block above")
    eq({ "stop", 2.8 }, at(32))
  end)

  it("finds segments by time and code by name", function()
    local data = timeline()
    eq("Problem", inspect.segment_at(data, 1.0).name)
    eq(23, inspect.location(data, "Problem", "question").line)
    eq(17, inspect.location(data, "Problem").line)
  end)

  it("orders the timeline picker by time", function()
    local items = require("gaanim.outline").timeline_items(project_mod.load(root), timeline())
    local texts = vim.tbl_map(function(item)
      return vim.trim(item.text)
    end, items)
    eq({ "Cover", "title", "Problem", "question", "answer", "(stop)", "Closing", "outro", "thanks" }, texts)
    eq({ cmd = "seek", segment = "Problem" }, items[3].value)
    eq("0:00.8–0:01.8  main.py:17", items[3].hint)
  end)
end)

describe("preview control", function()
  local preview = require("gaanim.preview")
  local cli = require("gaanim.cli")

  it("queues commands until the scene is ready, then sends them", function()
    local project = project_mod.load(root)
    local written = {}
    local fake = {
      is_closing = function()
        return false
      end,
      write = function(_, data)
        table.insert(written, data)
      end,
    }
    cli.jobs["preview:" .. root] = fake
    preview.status[root] = { state = "starting", key = "preview:" .. root, listen = true, queue = {} }
    eq(true, preview.send(project, { cmd = "seek", time = 1 }))
    eq(0, #written)
    eq(1, #preview.status[root].queue)
    preview.status[root].state = "ready"
    eq(true, preview.send(project, { cmd = "play" }))
    eq('{"cmd":"play"}\n', written[1])
    cli.jobs["preview:" .. root] = nil
    preview.status[root] = nil
    eq(false, preview.send(project, { cmd = "play" }))
  end)

  it("marks the line the preview rests at", function()
    local project = project_mod.load(root)
    inspect.cache[project.root] = { data = timeline(), stale = false }
    vim.cmd.edit(vim.fn.fnameescape(main))
    local buf = vim.api.nvim_get_current_buf()
    preview.on_playhead(project, { time = 1.3, segment = "Problem", stop = "question", playing = false })
    local marks = vim.api.nvim_buf_get_extmarks(buf, preview.ns, 0, -1, { details = true })
    eq(1, #marks)
    eq(22, marks[1][2], "0-based row of line 23")
    eq(require("gaanim.icons").get().paused, vim.trim(marks[1][4].sign_text))
    vim.cmd("bwipeout!")
    inspect.cache[project.root] = nil
  end)
end)
