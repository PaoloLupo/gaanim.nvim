---@mod gaanim.remote Opening code from Gaanim in this Neovim
---
--- Gaanim opens a script line in the editor that `GAANIM_EDITOR` names (the
--- inspector, the console, a double click on the animation timeline and the
--- script error panel's "Open in the editor"). Previews started from Neovim
--- get a `GAANIM_EDITOR` that sends the line back to this Neovim through its
--- RPC server.

local M = {}

--- Neovim's RPC address, starting a server if there is none.
---@return string
function M.server()
  local server = vim.v.servername
  if server == nil or server == "" then
    server = vim.fn.serverstart()
  end
  return server
end

--- A `GAANIM_EDITOR` command that opens `{file}` at `{line}` here. Gaanim
--- splits it on spaces, keeps quoted words whole and fills the placeholders
--- afterwards, so paths with backslashes reach Neovim untouched.
---@return string
function M.editor_command()
  return ([["%s" --server "%s" --remote-expr "v:lua.require'gaanim.remote'.open('{file}', {line})"]]):format(
    vim.v.progpath,
    M.server()
  )
end

--- Called by Gaanim through `--remote-expr`.
---@param file string
---@param line integer|string
---@return boolean
function M.open(file, line)
  vim.schedule(function()
    if vim.fn.mode() ~= "n" then
      vim.cmd("stopinsert")
    end
    require("gaanim.ui").jump(vim.fs.normalize(file), tonumber(line))
    vim.notify(("%s:%s"):format(vim.fn.fnamemodify(file, ":~:."), line), vim.log.levels.INFO, { title = "Gaanim" })
  end)
  return true
end

return M
