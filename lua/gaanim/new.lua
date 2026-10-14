---@mod gaanim.new Creating and opening projects

local cli = require("gaanim.cli")
local config = require("gaanim.config")
local project_mod = require("gaanim.project")
local ui = require("gaanim.ui")

local M = {}

M.kinds = { "slides", "video" }

local KIND_HINT = {
  slides = "a presentation: each segment is a slide, stop() waits for you",
  video = "an animation rendered to a video file",
}

---@param root string
local function open(root)
  local project = project_mod.load(root)
  if not project then
    return
  end
  project_mod.enter(project.root)
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

--- Creates a project with `gaanim init` and opens its entry script.
---@param kind? "slides"|"video"
---@param name? string Folder name under `projects_dir`, or a path
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
    cli.notify("Kind must be slides or video, not " .. kind, vim.log.levels.ERROR)
    return
  end
  if not name then
    ui.input(("New %s project name: "):format(kind), nil, function(value)
      M.new(kind, value)
    end)
    return
  end
  local dir = resolve_dir(name)
  if vim.uv.fs_stat(vim.fs.joinpath(dir, "gaanim.toml")) then
    cli.notify(dir .. " is already a Gaanim project; opening it")
    open(dir)
    return
  end
  local progress = ui.progress("Gaanim init")
  progress.update(("creating %s (Python environment included)"):format(dir))
  cli.run({ "init", kind, dir }, {
    on_exit = function(code)
      if code ~= 0 then
        progress.finish(false, "gaanim init failed; see :Gaanim log")
        return
      end
      if config.get().new.git and not vim.uv.fs_stat(vim.fs.joinpath(dir, ".git")) then
        vim.system({ "git", "init", "--quiet" }, { cwd = dir })
      end
      progress.finish(true, "created " .. dir)
      open(dir)
    end,
  })
end

--- Picks one of the projects under `projects_dir` and opens it.
function M.projects()
  if not project_mod.projects_dir() then
    cli.notify("Set `projects_dir` in the gaanim.nvim options to list your projects", vim.log.levels.WARN)
    return
  end
  local items = vim.tbl_map(function(project)
    return {
      text = project.name,
      hint = project.kind .. "  " .. vim.fn.fnamemodify(project.root, ":~"),
      icon = project.kind == "slides" and "▤" or "▶",
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
