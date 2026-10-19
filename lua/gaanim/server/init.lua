---@mod gaanim.server A Gaanim language server inside Neovim
---
--- An LSP server written in Lua that runs in Neovim's own process
--- (`vim.lsp.start` with a function as `cmd`). It attaches to the Python
--- files of Gaanim projects next to basedpyright and adds what only Gaanim
--- knows: the time of every `play`, `stop` and segment as inlay hints, code
--- lenses over each slide, hover on timeline lines and assets, code actions,
--- the scene's structure as document symbols, asset paths and Typst math in
--- completion, and diagnostics for assets that do not exist.
---
--- Times come from `gaanim inspect` (see |gaanim.inspect|), refreshed after
--- each save; the structure comes from the Python itself.

local config = require("gaanim.config")

local M = {}

M.name = "gaanim"

--- What the server offers. Positions are byte offsets (UTF-8), the way the
--- handlers read lines; with UTF-16 a hint after `¿` or an accent lands past
--- the end of its line. Handlers read the buffers directly, being in the same
--- process, but changes are still synced: the client re-requests hints and
--- lenses on `didChange`, which drops times while a line is being edited.
M.capabilities = {
  positionEncoding = "utf-8",
  textDocumentSync = { openClose = true, change = 2, save = true },
  inlayHintProvider = true,
  codeLensProvider = { resolveProvider = false },
  hoverProvider = true,
  codeActionProvider = { codeActionKinds = { "quickfix", "source" } },
  documentSymbolProvider = true,
  completionProvider = { triggerCharacters = { ".", '"', "'", "/" }, resolveProvider = false },
}

--- Request handlers by method. Each answers through `reply`, now or later.
---@type table<string, fun(params: table, reply: fun(result: any), ctx: { root: string })>
M.handlers = {
  ["textDocument/inlayHint"] = function(params, reply)
    require("gaanim.server.timeline").inlay_hints(params, reply)
  end,
  ["textDocument/codeLens"] = function(params, reply)
    require("gaanim.server.timeline").code_lenses(params, reply)
  end,
  ["textDocument/hover"] = function(params, reply)
    require("gaanim.server.hover").hover(params, reply)
  end,
  ["textDocument/codeAction"] = function(params, reply)
    require("gaanim.server.actions").code_actions(params, reply)
  end,
  ["textDocument/documentSymbol"] = function(params, reply)
    require("gaanim.server.symbols").document_symbols(params, reply)
  end,
  ["textDocument/completion"] = function(params, reply)
    require("gaanim.server.completion").complete(params, reply)
  end,
}

--- The buffer of a document URI, if it is loaded.
---@param uri string
---@return integer?
function M.buffer(uri)
  local buf = vim.uri_to_bufnr(uri)
  if vim.api.nvim_buf_is_loaded(buf) then
    return buf
  end
end

--- The project and buffer of a request's document.
---@param params table
---@return gaanim.Project?, integer?
function M.document(params)
  local uri = params.textDocument and params.textDocument.uri
  local buf = uri and M.buffer(uri)
  if not buf then
    return nil
  end
  return require("gaanim.project").current(buf), buf
end

---@type table<string, { dispatchers: vim.lsp.rpc.Dispatchers, closing: boolean }>
local servers = {}

--- A client for `vim.lsp.start`: requests go to `M.handlers` and are
--- answered asynchronously, like a server in another process would.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@param root string
---@return vim.lsp.rpc.PublicClient
function M.client(dispatchers, root)
  local state = { dispatchers = dispatchers, closing = false }
  servers[root] = state
  local next_id = 0
  local function answer(callback, notify_reply, id, err, result)
    vim.schedule(function()
      if notify_reply then
        notify_reply(id)
      end
      callback(err, result)
    end)
  end
  return {
    request = function(method, params, callback, notify_reply)
      next_id = next_id + 1
      local id = next_id
      if method == "initialize" then
        answer(callback, notify_reply, id, nil, { capabilities = M.capabilities, serverInfo = { name = M.name } })
      elseif method == "shutdown" then
        answer(callback, notify_reply, id, nil, nil)
      elseif M.handlers[method] then
        local ok, err = pcall(M.handlers[method], params or {}, function(result)
          answer(callback, notify_reply, id, nil, result)
        end, { root = root })
        if not ok then
          answer(callback, notify_reply, id, { code = -32603, message = tostring(err) }, nil)
        end
      else
        answer(callback, notify_reply, id, { code = -32601, message = "unsupported: " .. method }, nil)
      end
      return true, id
    end,
    notify = function(method, params)
      if method == "exit" then
        state.closing = true
        servers[root] = nil
        dispatchers.on_exit(0, 0)
      elseif method == "textDocument/didOpen" or method == "textDocument/didSave" then
        local buf = params and params.textDocument and M.buffer(params.textDocument.uri)
        if buf then
          vim.schedule(function()
            require("gaanim.server.assets").publish(buf)
          end)
        end
      end
      return true
    end,
    is_closing = function()
      return state.closing
    end,
    terminate = function()
      state.closing = true
      servers[root] = nil
    end,
  }
end

--- Asks the clients to request hints and lenses again, for a project: its
--- own, and a workspace's above it, whose shared modules run as a member.
---@param root string
function M.refresh(root)
  local workspace = require("gaanim.workspace")
  for server_root, state in pairs(servers) do
    if not state.closing and (server_root == root or workspace.within(root, server_root)) then
      vim.schedule(function()
        pcall(state.dispatchers.server_request, "workspace/inlayHint/refresh", nil)
        pcall(state.dispatchers.server_request, "workspace/codeLens/refresh", nil)
      end)
    end
  end
end

--- Sends diagnostics for a document.
---@param root string
---@param uri string
---@param diagnostics lsp.Diagnostic[]
function M.publish(root, uri, diagnostics)
  local state = servers[root]
  if state and not state.closing then
    state.dispatchers.notification("textDocument/publishDiagnostics", { uri = uri, diagnostics = diagnostics })
  end
end

local inspect_timer = vim.uv.new_timer()

--- Once saves settle, gets the new timeline (from the preview's next
--- `ready`, else `gaanim inspect`) and refreshes hints and lenses. The save
--- itself marks the timeline stale.
---@param project gaanim.Project
---@param delay? integer
function M.update(project, delay)
  inspect_timer:stop()
  inspect_timer:start(delay or 600, 0, function()
    vim.schedule(function()
      require("gaanim.inspect").get(project, function()
        M.refresh(project.root)
      end)
    end)
  end)
end

local guarded = false

--- Neovim 0.12 draws the hints of every client once any of them answers for
--- the buffer's new version, the others' still at the columns of the old
--- text. This server answers at once, so after an edit that shortens a line
--- basedpyright's hints land past its end and the decoration provider fails
--- with "Invalid 'col': out of range". After each answer, every stored hint
--- is kept within its line until its own client answers again. Neovim 0.13
--- draws each client's hints only at their own version, and needs none of it.
function M.guard_hints()
  if guarded or vim.fn.has("nvim-0.13") == 1 then
    return
  end
  guarded = true
  local default = vim.lsp.handlers["textDocument/inlayHint"]
  vim.lsp.handlers["textDocument/inlayHint"] = function(err, result, ctx, cfg)
    default(err, result, ctx, cfg)
    local buf = ctx.bufnr
    if not (buf and vim.api.nvim_buf_is_loaded(buf)) then
      return
    end
    local ok, hints = pcall(vim.lsp.inlay_hint.get, { bufnr = buf })
    if not ok then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, item in ipairs(hints) do
      local position = item.inlay_hint.position
      local line = lines[position.line + 1]
      if line and position.character > #line then
        position.character = #line
      end
    end
  end
end

--- Starts (or reuses) the server for a Python buffer of a Gaanim project.
---@param buf integer
---@return integer? client_id
function M.attach(buf)
  local cfg = config.get().server
  if not cfg.enabled or vim.bo[buf].buftype ~= "" then
    return nil
  end
  local root = vim.fs.root(buf, "gaanim.toml")
  if not root then
    return nil
  end
  root = vim.fs.normalize(root)
  require("gaanim.server.commands").register()
  local id = vim.lsp.start({
    name = M.name,
    cmd = function(dispatchers)
      return M.client(dispatchers, root)
    end,
    root_dir = root,
  }, { bufnr = buf })
  if id and cfg.lens then
    -- Neovim 0.12 takes a buffer or a client here, not both.
    vim.lsp.codelens.enable(true, { bufnr = buf })
  end
  if id and cfg.hints then
    M.guard_hints()
    vim.lsp.inlay_hint.enable(true, { bufnr = buf })
  end
  local project = require("gaanim.project").current(buf)
  if project and require("gaanim.cli").available() and not require("gaanim.inspect").cached(project) then
    M.update(project, 0)
  end
  return id
end

return M
