---@mod gaanim.new Creating and opening projects

local cli = require("gaanim.cli")
local config = require("gaanim.config")
local project_mod = require("gaanim.project")
local ui = require("gaanim.ui")

local M = {}

M.kinds = { "slides", "video", "workspace" }

local KIND_HINT = {
  slides = "a presentation: each segment is a slide, stop() waits for you",
  video = "an animation rendered to a video file",
  workspace = "several projects in one repository that share code, assets and Python",
}

---@param root string
local function open(root)
  local workspace = require("gaanim.workspace")
  if workspace.is_root(root) then
    workspace.open_root(root)
    return
  end
  local project = project_mod.load(root)
  if not project then
    return
  end
  -- A member is entered at its workspace, the repository's root.
  project_mod.enter(workspace.root_above(vim.fs.dirname(project.root)) or project.root)
  vim.cmd.edit(vim.fn.fnameescape(project.entry))
end

---@param name string
---@return string
local function resolve_dir(name)
  local expanded = vim.fn.expand(name)
  if expanded:match("^[/\\]") or expanded:match("^%a:[/\\]") or expanded:match("^%.") then
    return vim.fs.normalize(vim.fn.fnamemodify(expanded, ":p"))
  end
  local base = project_mod.projects_dir() or vim.uv.cwd()
  return vim.fs.normalize(vim.fs.joinpath(base, expanded))
end

--- Whether a name is a path of its own (absolute, or from `.`), not one
--- inside the workspace or `projects_dir`.
---@param name string
---@return boolean
local function explicit(name)
  local expanded = vim.fn.expand(name)
  return expanded:match("^[/\\]") ~= nil or expanded:match("^%a:[/\\]") ~= nil or expanded:match("^%.") ~= nil
end

---@class gaanim.InitResult
---@field created? { kind: string, root: string, entry?: string, workspace?: string, member?: boolean, venv?: string } The `init` line of `--message-format json`
---@field warnings string[] Each with the hint that follows it, such as the `members` line to add
---@field error? string

--- What `gaanim init` said: the JSON lines of `--message-format json`
--- (the `init` line names what it created), else its text for people.
--- Older versions put Windows' `\\?\` in front of paths.
---@param lines string[]
---@param objects table[]
---@return gaanim.InitResult
function M.init_result(lines, objects)
  local function plain(text)
    return (tostring(text or ""):gsub("\\\\%?\\", ""))
  end
  ---@type gaanim.InitResult
  local result = { warnings = {} }
  for _, line in ipairs(lines) do
    local text = line:match("^%s%s!%s+%S+%s+(.*)$")
    if text then
      table.insert(result.warnings, plain(text))
    end
  end
  for _, object in ipairs(objects) do
    if object.type == "init" then
      local created = vim.deepcopy(object)
      for _, key in ipairs({ "root", "entry", "workspace", "venv", "manifest" }) do
        created[key] = type(object[key]) == "string" and vim.fs.normalize(object[key]) or nil
      end
      result.created = created
    elseif object.type == "message" and object.level == "warning" then
      table.insert(result.warnings, plain(object.message))
    elseif object.type == "hint" and #result.warnings > 0 then
      result.warnings[#result.warnings] = result.warnings[#result.warnings] .. "\n" .. plain(object.message)
    elseif object.type == "message" and object.level == "error" then
      result.error = plain(object.message)
    end
  end
  return result
end

--- Creates a project with `gaanim init` and opens its entry script. Inside a
--- workspace a video or slides project becomes a member of it.
---@param kind? "slides"|"video"|"workspace"
---@param name? string Folder name under `projects_dir` (or the workspace), or a path
function M.new(kind, name)
  if not kind then
    ui.pick(
      vim.tbl_map(function(k)
        return { text = k, hint = KIND_HINT[k], value = k }
      end, M.kinds),
      {
        title = "New Gaanim project",
        on_choice = function(item)
          M.new(item.value, name)
        end,
      }
    )
    return
  end
  if not vim.tbl_contains(M.kinds, kind) then
    cli.notify("Kind must be slides, video or workspace, not " .. kind, vim.log.levels.ERROR)
    return
  end
  if kind == "workspace" then
    M.workspace(name)
    return
  end
  if not (name and explicit(name)) then
    local workspace = require("gaanim.workspace")
    local buf_name = vim.api.nvim_buf_get_name(0)
    local here = vim.fs.root(buf_name ~= "" and buf_name or (vim.uv.cwd() or "."), "gaanim.toml")
    here = here and vim.fs.normalize(here)
    if here and (workspace.is_root(here) or workspace.root_above(vim.fs.dirname(here))) then
      local ws = workspace.current(0, { quiet = true })
      if ws then
        M.member(ws, kind, name)
        return
      end
    end
  end
  if not name then
    ui.input(("New %s project name: "):format(kind), nil, function(value)
      M.new(kind, value)
    end)
    return
  end
  M.create(kind, resolve_dir(name))
end

--- Runs `gaanim init <kind> <dir>` and opens what it made, or hands it to
--- `on_done` (with the `init` line, when this gaanim writes JSON).
---@param kind "slides"|"video"|"workspace"
---@param dir string
---@param on_done? fun(created?: table)
function M.create(kind, dir, on_done)
  if vim.uv.fs_stat(vim.fs.joinpath(dir, "gaanim.toml")) then
    cli.notify(dir .. " is already a Gaanim " .. (kind == "workspace" and "workspace" or "project") .. "; opening it")
    open(dir)
    return
  end
  local progress = ui.progress("Gaanim init")
  progress.update(
    kind == "workspace" and ("creating %s (Git repository and Python environment included)"):format(dir)
      or ("creating %s"):format(dir)
  )
  local args = { "init", kind, dir }
  if require("gaanim.caps").get().init then
    vim.list_extend(args, { "--message-format", "json" })
  end
  cli.run(args, {
    on_exit = function(code, lines, objects)
      local result = M.init_result(lines, objects)
      if code ~= 0 then
        progress.finish(false, (result.error or "gaanim init failed") .. "; see :Gaanim log")
        return
      end
      if
        kind ~= "workspace"
        and config.get().new.git
        and not vim.uv.fs_stat(vim.fs.joinpath(dir, ".git"))
        and not require("gaanim.workspace").root_above(vim.fs.dirname(dir))
      then
        vim.system({ "git", "init", "--quiet" }, { cwd = dir })
      end
      require("gaanim.workspace").invalidate()
      progress.finish(true, "created " .. dir)
      for _, text in ipairs(result.warnings) do
        cli.notify(text, vim.log.levels.WARN)
      end
      if on_done then
        on_done(result.created)
      else
        open(dir)
      end
    end,
  })
end

--- Creates a workspace with `gaanim init workspace` (its first member,
--- shared `src/` and `assets/`, its `.venv` and Git repository included)
--- and opens its first member.
---@param name? string
function M.workspace(name)
  if not require("gaanim.caps").get().project then
    cli.notify("Workspaces need a newer Gaanim (`gaanim update`)", vim.log.levels.WARN)
    return
  end
  if not name then
    ui.input("New workspace name: ", nil, function(value)
      M.workspace(value)
    end)
    return
  end
  M.create("workspace", resolve_dir(name))
end

--- The folder, relative to the workspace, a new member named `name` goes
--- in: a name with a `/` is a path from the workspace's root; a bare name
--- goes beside the active member when it is of that kind, else beside the
--- first member of that kind, else beside the first member, else at the
--- root.
---@param workspace gaanim.Workspace
---@param kind "slides"|"video"
---@param name? string Nil for just the folder, ending in `/` (or "")
---@param active? string Root of the active member
---@return string
function M.member_path(workspace, kind, name, active)
  if name and name:find("/", 1, true) then
    return (name:gsub("^/+", ""):gsub("/+$", ""))
  end
  local function parent(member)
    return member.path:match("^(.*)/[^/]+$")
  end
  local folder
  for _, member in ipairs(workspace.members) do
    if active and require("gaanim.workspace").same(member.root, active) and member.kind == kind then
      folder = parent(member)
    end
  end
  for _, member in ipairs(workspace.members) do
    if folder == nil and member.kind == kind then
      folder = parent(member) or ""
    end
  end
  if folder == nil and workspace.members[1] then
    folder = parent(workspace.members[1]) or ""
  end
  folder = (folder and folder ~= "") and (folder .. "/") or ""
  return name and (folder .. name) or folder
end

--- Adds a member to a workspace with `gaanim init <kind>`, which writes only
--- the member's files (the environment is the workspace's), then opens it.
---@param workspace gaanim.Workspace
---@param kind? "slides"|"video"
---@param name? string A name beside the other members, or a path from the workspace
function M.member(workspace, kind, name)
  if not kind then
    ui.pick({
      { text = "video", hint = KIND_HINT.video, value = "video" },
      { text = "slides", hint = KIND_HINT.slides, value = "slides" },
    }, {
      title = "New member of " .. workspace.name,
      on_choice = function(item)
        M.member(workspace, item.value, name)
      end,
    })
    return
  end
  local active = require("gaanim.workspace").active[vim.fs.normalize(workspace.root)]
  if not name then
    ui.input(
      ("New %s in %s: "):format(kind == "slides" and "presentation" or "video", workspace.name),
      M.member_path(workspace, kind, nil, active),
      function(value)
        M.member(workspace, kind, value)
      end
    )
    return
  end
  local dir = explicit(name) and resolve_dir(name)
    or vim.fs.normalize(vim.fs.joinpath(workspace.root, M.member_path(workspace, kind, name, active)))
  M.create(kind, dir, function(created)
    local project = project_mod.load(dir)
    if not project then
      return
    end
    local ws = require("gaanim.workspace")
    if created then
      -- The `init` line says whether `members` lists it.
      if created.member and created.workspace then
        ws.use(created.workspace, project.root)
      end
    else
      local description = ws.describe(dir)
      if description and description.workspace then
        ws.use(description.workspace.root, project.root)
      end
    end
    project_mod.enter(workspace.root)
    vim.cmd.edit(vim.fn.fnameescape(project.entry))
  end)
end

--- Picks one of the projects or workspaces under `projects_dir` and opens
--- it; a workspace opens one of its members.
function M.projects()
  if not project_mod.projects_dir() then
    cli.notify("Set `projects_dir` in the gaanim.nvim options to list your projects", vim.log.levels.WARN)
    return
  end
  local icons = require("gaanim.icons").get()
  local items = vim.tbl_map(function(project)
    return {
      text = project.name,
      hint = project.kind .. "  " .. vim.fn.fnamemodify(project.root, ":~"),
      icon = icons[project.kind] or icons.video,
      file = project.entry,
      lnum = 1,
      value = project,
    }
  end, project_mod.list())
  ui.pick(items, {
    title = "Gaanim projects",
    on_choice = function(item)
      open(item.value.root)
    end,
  })
end

return M
