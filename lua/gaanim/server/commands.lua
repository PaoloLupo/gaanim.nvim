---@mod gaanim.server.commands What code lenses and code actions run
---
--- Client-side commands (`vim.lsp.commands`): the server names them in its
--- lenses and actions, and Neovim runs them here.

local M = {}

--- Brings the window to a line of a document.
---@param uri string
---@param line integer
local function focus(uri, line)
  local buf = vim.uri_to_bufnr(uri)
  if vim.api.nvim_get_current_buf() ~= buf then
    require("gaanim.ui").jump(vim.uri_to_fname(uri), line)
  elseif vim.api.nvim_win_get_cursor(0)[1] ~= line then
    vim.api.nvim_win_set_cursor(0, { line, 0 })
  end
end

--- The variable the scene goes by around a line (`scene` when unsure).
---@param buf integer
---@param line integer
---@return string
function M.receiver(buf, line)
  for row = line, 1, -1 do
    local text = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local name = text:match("([%a_][%w_]*)%.play%(")
      or text:match("([%a_][%w_]*)%.stop%(")
      or text:match("([%a_][%w_]*)%.wait%(")
      or text:match("([%a_][%w_]*)%.segment%(")
      or text:match("([%a_][%w_]*)%.marker%(")
    if name then
      return name
    end
  end
  return "scene"
end

---@param name string
---@return string
local function python_string(name)
  return '"' .. name:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

---@type table<string, fun(args: any[])>
M.commands = {
  ["gaanim.preview"] = function(args)
    focus(args[1], args[2])
    require("gaanim.preview").here()
  end,
  ["gaanim.still"] = function(args)
    focus(args[1], args[2])
    require("gaanim.export").still_here()
  end,
  ["gaanim.script"] = function(args)
    focus(args[1], args[2])
    require("gaanim.script").command("goto")
  end,
  ["gaanim.seek"] = function(args)
    require("gaanim.preview").seek(args[2])
  end,
  ["gaanim.exportSlide"] = function(args)
    focus(args[1], args[2])
    require("gaanim.export").export("draft", { "here" })
  end,
  ["gaanim.nameStop"] = function(args)
    focus(args[1], args[2])
    local buf, line = vim.api.nvim_get_current_buf(), args[2]
    require("gaanim.ui").input("Stop name: ", nil, function(name)
      local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
      local s, e = text:find("%.stop%(%s*%)")
      if s then
        local named = text:sub(1, s - 1) .. ".stop(" .. python_string(name) .. ")" .. text:sub(e + 1)
        vim.api.nvim_buf_set_lines(buf, line - 1, line, false, { named })
      end
    end)
  end,
  ["gaanim.addMarker"] = function(args)
    focus(args[1], args[2])
    local buf, line = vim.api.nvim_get_current_buf(), args[2]
    require("gaanim.ui").input("Marker name: ", nil, function(name)
      local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
      local indent = text:match("^%s*")
      local marker = indent .. M.receiver(buf, line) .. ".marker(" .. python_string(name) .. ")"
      vim.api.nvim_buf_set_lines(buf, line, line, false, { marker })
      vim.api.nvim_win_set_cursor(0, { line + 1, #indent })
    end)
  end,
}

local registered = false

--- Makes the commands known to Neovim's LSP client, once.
function M.register()
  if registered then
    return
  end
  registered = true
  for name, run in pairs(M.commands) do
    vim.lsp.commands[name] = function(command)
      run(command.arguments or {})
    end
  end
end

return M
