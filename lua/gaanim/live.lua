---@mod gaanim.live Live mode: the preview follows your edits as you make them
---
--- In live mode a changed project file is written shortly after you stop
--- changing it (in normal mode, or also while typing), without running
--- write autocommands such as formatters. Gaanim reloads on every write, so
--- the preview shows each change within a fraction of a second; times in the
--- code are refreshed after it.

local cli = require("gaanim.cli")
local config = require("gaanim.config")

local M = {}

---@type table<string, boolean> Projects in live mode
M.enabled = {}

---@type table<integer, uv.uv_timer_t>
local timers = {}

---@param buf integer
---@return string|false
local function root_of(buf)
  local root = vim.b[buf].gaanim_root
  if root == nil then
    root = vim.fs.root(buf, "gaanim.toml") or false
    vim.b[buf].gaanim_root = root
  end
  return root and vim.fs.normalize(root) or false
end

---@param root string
---@return boolean
function M.active(root)
  return M.enabled[vim.fs.normalize(root)] == true
end

--- Turns live mode on or off for the current project; toggles without an
--- argument. Turning it on opens the preview at the cursor when it is closed.
---@param on? boolean
function M.toggle(on)
  local project = require("gaanim.project").require()
  if not project then
    return
  end
  if on == nil then
    on = not M.enabled[project.root]
  end
  M.enabled[project.root] = on or nil
  if on then
    local status = require("gaanim.preview").status[project.root]
    if not (status and cli.running(status.key)) then
      require("gaanim.preview").here()
    end
    cli.notify("Live: changes reach the preview as you make them")
  else
    cli.notify("Live mode off")
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "GaanimPreview", data = { root = project.root } })
end

--- Writes a buffer of a live project if it still has changes.
---@param buf integer
function M.write(buf)
  if not (vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified) then
    return
  end
  if vim.fn.getcmdtype() ~= "" then
    -- Not while a command line is open; the next change writes it.
    return
  end
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent! lockmarks noautocmd update")
  end)
  local project = require("gaanim.project").current(buf)
  if not project then
    return
  end
  require("gaanim.server").update(project)
  if package.loaded["gaanim.script"] then
    require("gaanim.script").refresh(buf)
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "GaanimLiveWrite", data = { root = project.root, buf = buf } })
end

--- Called when a buffer changes: writes it once the changes settle, in a
--- project in live mode.
---@param buf integer
---@param typing boolean The change happened in insert mode
function M.on_change(buf, typing)
  if not next(M.enabled) then
    return
  end
  local root = root_of(buf)
  if not (root and M.enabled[root]) then
    return
  end
  local cfg = config.get().live
  if typing and not cfg.while_typing then
    return
  end
  local timer = timers[buf]
  if not timer then
    timer = vim.uv.new_timer()
    timers[buf] = timer
  end
  timer:stop()
  timer:start(typing and cfg.typing_delay or cfg.delay, 0, function()
    vim.schedule(function()
      M.write(buf)
    end)
  end)
end

return M
