---@mod gaanim.docs The documentation of the installed Gaanim
---
--- The authoring wheel bundles the documentation's Typst sources as
--- `gaanim/_docs` in the project's environment, so they match the Gaanim the
--- project runs. API entries read `#api-entry(name: "Scene.voiceover", ...)`.

local cli = require("gaanim.cli")
local config = require("gaanim.config")
local project_mod = require("gaanim.project")
local ui = require("gaanim.ui")

local M = {}

--- The `_docs` folder for the current project, or from `GAANIM_DOCS`.
---@return string?
function M.dir()
  local env = vim.env.GAANIM_DOCS
  if env and vim.uv.fs_stat(env) then
    return vim.fs.normalize(env)
  end
  local project = project_mod.current()
  local start = project and project.root or vim.uv.cwd()
  local venv = vim.fs.find({ ".venv", "venv" }, { path = start, upward = true, type = "directory" })[1]
  if not venv then
    return nil
  end
  local candidates = { vim.fs.joinpath(venv, "Lib", "site-packages", "gaanim", "_docs") }
  for path in vim.fs.dir(vim.fs.joinpath(venv, "lib")) do
    table.insert(candidates, vim.fs.joinpath(venv, "lib", path, "site-packages", "gaanim", "_docs"))
  end
  for _, path in ipairs(candidates) do
    if vim.uv.fs_stat(path) then
      return vim.fs.normalize(path)
    end
  end
end

---@return string?
local function require_dir()
  local dir = M.dir()
  if not dir then
    cli.notify("No bundled docs: open the project once with gaanim, or set GAANIM_DOCS", vim.log.levels.WARN)
  end
  return dir
end

---@return boolean
local function has_snacks()
  return config.get().picker ~= "select" and pcall(require, "snacks.picker") and _G.Snacks ~= nil
end

--- Searches the docs: a live grep with snacks, else `:vimgrep` into quickfix.
---@param query? string
function M.open(query)
  local dir = require_dir()
  if not dir then
    return
  end
  if has_snacks() then
    Snacks.picker.grep({ title = "Gaanim docs", cwd = dir, search = query, glob = { "*.typ", "*.py" } })
    return
  end
  if not query then
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(dir, "index.typ")))
    return
  end
  local pattern = vim.fn.escape(query, "/\\")
  vim.cmd(("silent! vimgrep /\\V%s/j %s/**/*.typ"):format(pattern, vim.fn.fnameescape(dir)))
  vim.cmd("botright copen")
end

--- API entries whose name ends with `name` (`voiceover` finds
--- `Scene.voiceover`).
---@param dir string
---@param name string
---@return gaanim.PickItem[]
function M.api_entries(dir, name)
  local items = {}
  local wanted = name:lower()
  for path, kind in vim.fs.dir(dir, { depth = 4 }) do
    if kind == "file" and path:match("%.typ$") then
      local file = vim.fs.joinpath(dir, path)
      local lnum, in_entry = 0, false
      for line in io.lines(file) do
        lnum = lnum + 1
        -- `#api-entry(` and its `name: "..."` share a line or follow each other.
        local entry = line:match('api%-entry%(%s*name:%s*"([^"]+)"')
          or (in_entry and line:match('^%s*name:%s*"([^"]+)"'))
        in_entry = line:match("api%-entry%(%s*$") ~= nil
        if entry then
          local lower = entry:lower()
          if lower == wanted or vim.endswith(lower, "." .. wanted) then
            table.insert(items, { text = entry, hint = path .. ":" .. lnum, file = file, lnum = lnum, icon = "λ" })
          end
        end
      end
    end
  end
  return items
end

--- Opens the API entry of `name`, or of the word under the cursor.
---@param name? string
function M.api(name)
  local dir = require_dir()
  if not dir then
    return
  end
  name = name or vim.fn.expand("<cword>")
  local items = M.api_entries(dir, name)
  if #items == 0 then
    M.open(name)
  elseif #items == 1 then
    ui.jump(items[1].file, items[1].lnum)
  else
    ui.pick(items, {
      title = "Gaanim API · " .. name,
      on_choice = function(item)
        ui.jump(item.file, item.lnum)
      end,
    })
  end
end

return M
