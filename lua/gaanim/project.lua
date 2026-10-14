---@mod gaanim.project Finding projects and reading gaanim.toml

local config = require("gaanim.config")

local M = {}

---@class gaanim.Project
---@field root string Project folder (or the script's folder for a lone script)
---@field target string What the CLI receives: the folder, or the lone script
---@field manifest? string Path of gaanim.toml
---@field name string
---@field kind "video"|"slides"|"script"
---@field entry string Entry script, absolute
---@field assets_dir string Absolute
---@field output_dir string Absolute
---@field language? string
---@field raw table<string, any> Every top-level key of gaanim.toml

--- Reads the top-level `key = value` pairs of a TOML file. gaanim.toml only
--- needs strings, numbers and booleans there; tables are skipped.
---@param path string
---@return table<string, any>?
function M.read_toml(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local result = {}
  for line in file:lines() do
    line = line:gsub("^%s+", "")
    if line:match("^%[") then
      break
    end
    local key, value = line:match("^([%w_%-]+)%s*=%s*(.-)%s*$")
    if key then
      local str = value:match('^"(.-)"') or value:match("^'(.-)'")
      if str then
        result[key] = str
      elseif value:match("^true") then
        result[key] = true
      elseif value:match("^false") then
        result[key] = false
      else
        result[key] = tonumber(value:match("^[%d%.%-]+"))
      end
    end
  end
  file:close()
  return result
end

---@param path string
---@return boolean
local function is_gaanim_script(path)
  if not path:match("%.py$") then
    return false
  end
  local file = io.open(path, "r")
  if not file then
    return false
  end
  local head = file:read(4096) or ""
  file:close()
  return head:match("from%s+gaanim") ~= nil or head:match("import%s+gaanim") ~= nil
end

--- Builds the project for a gaanim.toml folder.
---@param root string
---@return gaanim.Project?
function M.load(root)
  root = vim.fs.normalize(root)
  local manifest = vim.fs.joinpath(root, "gaanim.toml")
  local raw = M.read_toml(manifest)
  if not raw then
    return nil
  end
  local kind = raw.kind == "slides" and "slides" or "video"
  return {
    root = root,
    target = root,
    manifest = manifest,
    name = raw.name or vim.fs.basename(root),
    kind = kind,
    entry = vim.fs.joinpath(root, raw.entry or "main.py"),
    assets_dir = vim.fs.joinpath(root, raw.assets_dir or "assets"),
    output_dir = vim.fs.joinpath(root, raw.output_dir or "exports"),
    language = raw.language,
    raw = raw,
  }
end

--- The project of a buffer, or of the current directory. A Python file that
--- imports gaanim outside any project counts as a project of its own.
---@param buf? integer
---@return gaanim.Project?
function M.current(buf)
  buf = buf or 0
  local root = vim.fs.root(buf, "gaanim.toml")
  if root then
    return M.load(root)
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name ~= "" and is_gaanim_script(name) then
    name = vim.fs.normalize(name)
    local dir = vim.fs.dirname(name)
    return {
      root = dir,
      target = name,
      name = vim.fn.fnamemodify(name, ":t:r"),
      kind = "script",
      entry = name,
      assets_dir = vim.fs.joinpath(dir, "assets"),
      output_dir = dir,
      raw = {},
    }
  end
  root = vim.fs.root(vim.uv.cwd() or ".", "gaanim.toml")
  return root and M.load(root) or nil
end

--- Like `current`, but tells the user when there is no project.
---@param buf? integer
---@return gaanim.Project?
function M.require(buf)
  local project = M.current(buf)
  if not project then
    vim.notify("No Gaanim project here (no gaanim.toml above this file)", vim.log.levels.WARN, { title = "Gaanim" })
  end
  return project
end

---@return string?
function M.projects_dir()
  local dir = config.get().projects_dir
  return dir and vim.fs.normalize(vim.fn.expand(dir)) or nil
end

--- Projects under `projects_dir`, up to three levels deep, newest first.
---@return gaanim.Project[]
function M.list()
  local dir = M.projects_dir()
  if not dir then
    return {}
  end
  local ignore = { assets = true }
  for _, name in ipairs(config.get().outline.ignore) do
    ignore[name] = true
  end
  local found = {}
  for path, kind in
    vim.fs.dir(dir, {
      depth = 3,
      skip = function(name)
        local base = vim.fs.basename(name)
        return not (ignore[base] or vim.startswith(base, "."))
      end,
    })
  do
    if kind == "file" and vim.fs.basename(path) == "gaanim.toml" then
      local project = M.load(vim.fs.joinpath(dir, vim.fs.dirname(path)))
      if project then
        local stat = vim.uv.fs_stat(project.entry) or vim.uv.fs_stat(project.manifest)
        project.raw._mtime = stat and stat.mtime.sec or 0
        table.insert(found, project)
      end
    end
  end
  table.sort(found, function(a, b)
    return a.raw._mtime > b.raw._mtime
  end)
  return found
end

--- Python files of a project, skipping environments and outputs.
---@param project gaanim.Project
---@return string[]
function M.python_files(project)
  if project.kind == "script" then
    return { project.entry }
  end
  local ignore = {}
  for _, name in ipairs(config.get().outline.ignore) do
    ignore[name] = true
  end
  local files = {}
  for path, kind in
    vim.fs.dir(project.root, {
      depth = 6,
      skip = function(dir)
        return not ignore[vim.fs.basename(dir)]
      end,
    })
  do
    if kind == "file" and path:match("%.py$") then
      table.insert(files, vim.fs.joinpath(project.root, path))
    end
  end
  table.sort(files, function(a, b)
    -- The entry script first, then the rest by path.
    if a == project.entry or b == project.entry then
      return a == project.entry
    end
    return a < b
  end)
  return files
end

--- Enters a project folder with the configured `:cd` flavour.
---@param root string
function M.enter(root)
  local cd = config.get().new.cd
  if cd then
    vim.cmd[cd](vim.fn.fnameescape(root))
  end
end

return M
