---@mod gaanim.lsp Completion from the project's environment
---
--- `gaanim init` puts the authoring package, with its type stubs, in the
--- project's `.venv`. Pyright and basedpyright do not look there on their
--- own, so a client that attaches to a project file is told to use that
--- interpreter. In a workspace the environment is the one `.venv` at its
--- root, and scripts import from folders other than their own (the shared
--- `src/`, the member's): `gaanim project` names the interpreter and the
--- folders on `sys.path`, which go to `analysis.extraPaths`.

local M = {}

--- The clients told, with the section their analysis settings live in.
---@type table<string, string>
M.clients = { pyright = "python", basedpyright = "basedpyright" }

---@param root string
---@return string?
function M.interpreter(root)
  local candidates = vim.fn.has("win32") == 1 and { ".venv/Scripts/python.exe", "venv/Scripts/python.exe" }
    or { ".venv/bin/python", "venv/bin/python" }
  for _, relative in ipairs(candidates) do
    local path = vim.fs.joinpath(root, relative)
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

---@class gaanim.LspPython
---@field interpreter? string
---@field paths string[] Folders on `sys.path`, first to last
---@field skip? string[] Folders the client searches already

--- The settings that point a client at an environment: `python.pythonPath`,
--- and the folders `analysis.extraPaths` lacks added after the ones it has
--- (the user's included). Nil when nothing changes.
---@param name string Client name
---@param settings? table
---@param python gaanim.LspPython
---@return table?
function M.settings(name, settings, python)
  local workspace = require("gaanim.workspace")
  local new = vim.deepcopy(settings or {})
  local changed = false
  if python.interpreter and vim.tbl_get(new, "python", "pythonPath") ~= python.interpreter then
    new.python = type(new.python) == "table" and new.python or {}
    new.python.pythonPath = python.interpreter
    changed = true
  end
  local section = M.clients[name] or "python"
  local extra = vim.tbl_get(new, section, "analysis", "extraPaths")
  extra = type(extra) == "table" and vim.deepcopy(extra) or {}
  local added = false
  for _, path in ipairs(python.paths or {}) do
    local known = false
    for _, other in ipairs(vim.list_extend(vim.deepcopy(extra), python.skip or {})) do
      if workspace.same(path, other) then
        known = true
        break
      end
    end
    if not known then
      table.insert(extra, path)
      added = true
    end
  end
  if added then
    new[section] = type(new[section]) == "table" and new[section] or {}
    new[section].analysis = type(new[section].analysis) == "table" and new[section].analysis or {}
    new[section].analysis.extraPaths = extra
    changed = true
  end
  return changed and new or nil
end

--- What `gaanim project` says of a file, as a client takes it: a file's own
--- folder is left out unless it is its project's (the client finds what
--- sits beside a file by itself), and so is the client's root.
---@param description gaanim.Description
---@param file string
---@param client_root? string
---@return gaanim.LspPython
function M.from_description(description, file, client_root)
  local workspace = require("gaanim.workspace")
  local folder = vim.fs.dirname(vim.fs.normalize(file))
  local project = description.project and description.project.root
  local skip = { client_root }
  if not workspace.same(folder, project) then
    table.insert(skip, folder)
  end
  return { interpreter = description.python.interpreter, paths = description.python.paths, skip = skip }
end

--- Without `gaanim project`: the interpreter of the project's `.venv`, else
--- of the workspace's above it.
---@param root string
---@return gaanim.LspPython
function M.fallback(root)
  local above = require("gaanim.workspace").root_above(root)
  return { interpreter = M.interpreter(root) or (above and M.interpreter(above)), paths = {} }
end

---@param client vim.lsp.Client
---@param python gaanim.LspPython
local function apply(client, python)
  if vim.lsp.get_client_by_id(client.id) == nil then
    return
  end
  local settings = M.settings(client.name, client.settings, python)
  if settings then
    client.settings = settings
    client:notify("workspace/didChangeConfiguration", { settings = client.settings })
  end
end

---@param buf integer
---@param client_id integer
function M.attach(buf, client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  if not (client and M.clients[client.name]) then
    return
  end
  local root = vim.fs.root(buf, "gaanim.toml")
  if not root then
    return
  end
  root = vim.fs.normalize(root)
  local file = vim.api.nvim_buf_get_name(buf)
  local client_root = client.root_dir and vim.fs.normalize(vim.fn.fnamemodify(client.root_dir, ":p")) or nil
  require("gaanim.caps").load(function(can)
    if not (can.project and file ~= "") then
      apply(client, M.fallback(root))
      return
    end
    require("gaanim.workspace").describe(file, function(description)
      apply(client, description and M.from_description(description, file, client_root) or M.fallback(root))
    end)
  end)
end

return M
