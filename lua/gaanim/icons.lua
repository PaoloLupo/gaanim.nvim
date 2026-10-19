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
---@field still string A frame exported as an image
---@field voiceover string
---@field playing string
---@field paused string
---@field follow string The preview follows the cursor
---@field loop string The preview loops a range, and the lens that starts it
---@field unloop string The lens that ends a loop
---@field time string The instant of the cursor's line
---@field previous string The panel's previous slide
---@field next string The panel's next slide
---@field slides string A slides project
---@field video string A video project
---@field workspace string A workspace: projects that share code and assets
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
    still = "󰋩", -- md-image
    voiceover = "󰍬", -- md-microphone
    playing = "󰐊", -- md-play
    paused = "󰏤", -- md-pause
    follow = "󰌹", -- md-link_variant
    loop = "󰑖", -- md-repeat
    unloop = "󰑗", -- md-repeat_off
    time = "󰔛", -- md-timer_outline
    previous = "󰒮", -- md-skip_previous
    next = "󰒭", -- md-skip_next
    slides = "󰐨", -- md-presentation
    video = "󰎁", -- md-movie
    workspace = "󰉓", -- md-folder_multiple
    reloading = "󰓦", -- md-sync
    starting = "󰔟", -- md-timer_sand
    failed = "✗",
  },
  unicode = {
    segment = "▤",
    section = "§",
    stop = "⏸",
    marker = "◆",
    still = "▣",
    voiceover = "♪",
    playing = "▶",
    paused = "⏸",
    follow = "⇄",
    loop = "⟲",
    unloop = "⊘",
    time = "⏱",
    previous = "⏮",
    next = "⏭",
    slides = "▤",
    video = "▶",
    workspace = "▦",
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
