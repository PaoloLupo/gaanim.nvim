---@mod gaanim.project Finding projects and reading gaanim.toml

local config = require("gaanim.config")

local M = {}

---@class gaanim.Project
---@field root string Project folder (or the script's folder for a lone script)
---@field target string What the CLI receives: the folder, or the lone script
---@field manifest? string Path of gaanim.toml
---@field name string
---@field kind "video"|"slides"|"script"|"workspace" "workspace" only in `list`
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

--- Builds the project for a gaanim.toml folder; nil for a workspace's own
--- manifest, which names no project (see |gaanim.workspace|).
---@param root string
---@return gaanim.Project?
function M.load(root)
  root = vim.fs.normalize(root)
  if require("gaanim.workspace").is_root(root) then
    return nil
  end
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

--- A Python file that imports gaanim, as a project of its own.
---@param name string
---@return gaanim.Project
function M.script(name)
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

--- What a file in a workspace's own folders acts as: a script that imports
--- gaanim outside the shared Python folders is a project of its own (a
--- sketch); anything else, a shared module above all, runs as part of the
--- workspace's active member.
---@param root string Workspace root
---@param file string "" for none
---@return gaanim.Project?
function M.in_workspace(root, file)
  local workspace = require("gaanim.workspace")
  if file ~= "" and not workspace.is_shared(root, file) and is_gaanim_script(file) then
    return M.script(file)
  end
  local member = workspace.active[vim.fs.normalize(root)]
  return member and M.load(member) or nil
end

--- The project of a buffer, or of the current directory. A Python file that
--- imports gaanim outside any project counts as a project of its own. In a
--- workspace's own folders, see `in_workspace`.
---@param buf? integer
---@return gaanim.Project?
function M.current(buf)
  buf = buf or 0
  local name = vim.api.nvim_buf_get_name(buf)
  name = name ~= "" and vim.fs.normalize(name) or ""
  local root = vim.fs.root(buf, "gaanim.toml")
  if root then
    return M.load(root) or M.in_workspace(root, name)
  end
  if name ~= "" and is_gaanim_script(name) then
    return M.script(name)
  end
  root = vim.fs.root(vim.uv.cwd() or ".", "gaanim.toml")
  return root and (M.load(root) or M.in_workspace(root, "")) or nil
end

--- Runs again the `:Gaanim` command being run, once a member is picked.
---@type fun()?
M.retry = nil

--- Like `current`, but tells the user when there is no project. In a
--- workspace's own file with no active member yet, it takes the only
--- member, or asks which one and runs the command again with it.
---@param buf? integer
---@return gaanim.Project?
function M.require(buf)
  local project = M.current(buf)
  if project then
    return project
  end
  local root = vim.fs.root(buf or 0, "gaanim.toml")
  if root and require("gaanim.workspace").is_root(vim.fs.normalize(root)) then
    return require("gaanim.workspace").choose(vim.fs.normalize(root), M.retry)
  end
  vim.notify("No Gaanim project here (no gaanim.toml above this file)", vim.log.levels.WARN, { title = "Gaanim" })
  return nil
end

--- The root of the project a buffer's commands act on, cheaply enough for
--- autocommands and statuslines: its project's; in a workspace's own
--- folders the active member's, or a sketch's folder; false outside.
---@param buf integer
---@return string|false
function M.root_of(buf)
  local root = vim.b[buf].gaanim_root
  if root == nil then
    root = vim.fs.root(buf, "gaanim.toml")
    root = root and vim.fs.normalize(root) or false
    vim.b[buf].gaanim_root = root
  end
  if not root then
    return false
  end
  local workspace = require("gaanim.workspace")
  if not workspace.is_root(root) then
    return root
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name ~= "" then
    name = vim.fs.normalize(name)
    local script = vim.b[buf].gaanim_script
    if script == nil then
      script = is_gaanim_script(name)
      vim.b[buf].gaanim_script = script
    end
    if script and not workspace.is_shared(root, name) then
      return vim.fs.dirname(name)
    end
  end
  return workspace.active[root] or false
end

---@return string?
function M.projects_dir()
  local dir = config.get().projects_dir
  return dir and vim.fs.normalize(vim.fn.expand(dir)) or nil
end

--- Projects and workspaces under `projects_dir`, up to three levels deep,
--- newest first. A workspace is one entry (of kind "workspace", its entry
--- its manifest) that stands for its members.
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
  local workspace = require("gaanim.workspace")
  local found, workspaces = {}, {}
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
      local root = vim.fs.normalize(vim.fs.joinpath(dir, vim.fs.dirname(path)))
      local manifest = vim.fs.joinpath(root, "gaanim.toml")
      local entry
      if workspace.is_root(root) then
        local info = workspace.manifest(root) or {}
        entry = {
          root = root,
          target = root,
          manifest = manifest,
          name = info.name or vim.fs.basename(root),
          kind = "workspace",
          entry = manifest,
          assets_dir = vim.fs.joinpath(root, "assets"),
          output_dir = vim.fs.joinpath(root, "exports"),
          raw = {},
        }
        table.insert(workspaces, root)
      else
        entry = M.load(root)
      end
      if entry then
        local stat = vim.uv.fs_stat(entry.entry) or vim.uv.fs_stat(manifest)
        entry.raw._mtime = stat and stat.mtime.sec or 0
        table.insert(found, entry)
      end
    end
  end
  -- A workspace's members are reached through it.
  found = vim.tbl_filter(function(entry)
    for _, root in ipairs(workspaces) do
      if entry.root ~= root and workspace.within(entry.root, root) then
        return false
      end
    end
    return true
  end, found)
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
