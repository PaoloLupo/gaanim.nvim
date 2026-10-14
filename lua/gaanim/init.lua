---@mod gaanim gaanim.nvim
---
--- Write Gaanim scenes and slides in Neovim: create projects, preview and
--- present from the slide under the cursor, check on save, export, and keep
--- the narration script beside the code.
---
--- The plugin works without calling `setup()`; options can also be set in
--- `vim.g.gaanim` before it loads.

local M = {}

---@param opts? table See |gaanim-config|
function M.setup(opts)
  require("gaanim.config").setup(opts)
end

local STATES = { starting = "◌", reloading = "↻", ready = "●", failed = "✗" }

--- A short status for statuslines: the slide under the cursor, the preview's
--- state and the last check, or "" outside Gaanim projects.
---@return string
function M.status()
  local buf = vim.api.nvim_get_current_buf()
  local root = vim.b[buf].gaanim_root
  if root == nil then
    root = vim.fs.root(buf, "gaanim.toml") or false
    vim.b[buf].gaanim_root = root
  end
  if not root then
    return ""
  end
  local parts = {}
  if vim.bo[buf].filetype == "python" then
    local here = require("gaanim.index").at_cursor(buf)
    if here.segment then
      local text = "▤ " .. here.segment.name
      if here.stop_index > 0 then
        text = text .. " ⏸" .. here.stop_index
      end
      table.insert(parts, text)
    end
  end
  local preview = package.loaded["gaanim.preview"] and require("gaanim.preview").status[root]
  if preview then
    table.insert(parts, STATES[preview.state] .. " " .. preview.state)
  end
  local check = package.loaded["gaanim.check"] and require("gaanim.check").last[root]
  if check then
    table.insert(
      parts,
      check.status == "pass" and "✓" or check.status == "warning" and ("!" .. #check.items) or "✗"
    )
  end
  return table.concat(parts, "  ")
end

return M
