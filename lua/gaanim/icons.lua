---@mod gaanim.icons Icons in pickers, the statusline and signs
---
--- Nerd Font (Material Design) icons by default; `icons = "unicode"` uses
--- plain characters for fonts without them, and a table overrides any.

local M = {}

---@class gaanim.Icons
---@field segment string A slide
---@field section string
---@field stop string
---@field marker string
---@field voiceover string
---@field playing string
---@field paused string
---@field follow string The preview follows the cursor
---@field time string The instant of the cursor's line
---@field slides string A slides project
---@field video string A video project
---@field reloading string
---@field starting string
---@field failed string

---@type table<string, gaanim.Icons>
M.sets = {
  nerd = {
    segment = "󰐨", -- md-presentation
    section = "󰚟", -- md-format_section
    stop = "󰏤", -- md-pause
    marker = "󰃀", -- md-bookmark
    voiceover = "󰍬", -- md-microphone
    playing = "󰐊", -- md-play
    paused = "󰏤", -- md-pause
    follow = "󰌹", -- md-link_variant
    time = "󰔛", -- md-timer_outline
    slides = "󰐨", -- md-presentation
    video = "󰎁", -- md-movie
    reloading = "󰓦", -- md-sync
    starting = "󰔟", -- md-timer_sand
    failed = "✗",
  },
  unicode = {
    segment = "▤",
    section = "§",
    stop = "⏸",
    marker = "◆",
    voiceover = "♪",
    playing = "▶",
    paused = "⏸",
    follow = "⇄",
    time = "⏱",
    slides = "▤",
    video = "▶",
    reloading = "↻",
    starting = "◌",
    failed = "✗",
  },
}

--- The configured icons.
---@return gaanim.Icons
function M.get()
  local choice = require("gaanim.config").get().icons
  if type(choice) == "table" then
    return vim.tbl_extend("force", M.sets.nerd, choice)
  end
  return M.sets[choice] or M.sets.nerd
end

return M
