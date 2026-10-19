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

--- A short status for statuslines: the slide under the cursor and the
--- instant its line stands for, where the preview rests (and `⇄` when it
--- follows the cursor), and the last check; "" outside Gaanim projects. In
--- a workspace's shared module, those of the member it runs as.
---@return string
function M.status()
  local buf = vim.api.nvim_get_current_buf()
  local root = require("gaanim.project").root_of(buf)
  if not root then
    return ""
  end
  local icons = require("gaanim.icons").get()
  local parts = {}
  if vim.bo[buf].filetype == "python" then
    local here = require("gaanim.index").at_cursor(buf)
    if here.segment then
      local text = icons.segment .. " " .. here.segment.name
      if here.stop_index > 0 then
        text = text .. " " .. icons.stop .. here.stop_index
      end
      table.insert(parts, text)
    end
  end
  local inspect = package.loaded["gaanim.inspect"] and require("gaanim.inspect")
  local data = inspect and inspect.cache[root] and inspect.cache[root].data
  if data and vim.bo[buf].filetype == "python" then
    local point = inspect.point_at(data, vim.api.nvim_buf_get_name(buf), vim.api.nvim_win_get_cursor(0)[1])
    if point then
      table.insert(parts, icons.time .. " " .. require("gaanim.outline").clock(point.time))
    end
  end
  local preview_mod = package.loaded["gaanim.preview"] and require("gaanim.preview")
  local preview = preview_mod and preview_mod.status[root]
  if preview then
    local playhead = preview.playhead
    if playhead and preview.state == "ready" then
      -- Looping has its own icon, in place of play or pause.
      local icon = playhead.loop and icons.loop or (playhead.playing and icons.playing or icons.paused)
      local text = icon .. " " .. require("gaanim.outline").clock(playhead.time)
      if playhead.segment then
        text = text .. " " .. playhead.segment
      end
      if playhead.stop and playhead.stop ~= "" then
        text = text .. "·" .. playhead.stop
      end
      table.insert(parts, text)
    else
      local state =
        { starting = icons.starting, reloading = icons.reloading, ready = icons.playing, failed = icons.failed }
      table.insert(parts, state[preview.state] .. " " .. preview.state)
    end
    if preview_mod.following[root] then
      table.insert(parts, icons.follow)
    end
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
