---@mod gaanim.lsp Completion from the project's environment
---
--- `gaanim init` puts the authoring package, with its type stubs, in the
--- project's `.venv`. Pyright and basedpyright do not look there on their
--- own, so a client that attaches to a project file is told to use that
--- interpreter.

local M = {}

M.clients = { pyright = true, basedpyright = true }

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

---@param buf integer
---@param client_id integer
function M.attach(buf, client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  if not (client and M.clients[client.name]) then
    return
  end
  local root = vim.fs.root(buf, "gaanim.toml")
  local python = root and M.interpreter(root)
  if not python then
    return
  end
  local settings = client.settings or {}
  if vim.tbl_get(settings, "python", "pythonPath") == python then
    return
  end
  client.settings = vim.tbl_deep_extend("force", settings, { python = { pythonPath = python } })
  client:notify("workspace/didChangeConfiguration", { settings = client.settings })
end

return M
