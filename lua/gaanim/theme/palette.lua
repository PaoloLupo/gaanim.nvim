---@mod gaanim.theme.palette The colors of the Gaanim colorscheme
---
--- Both variants come from the brand (docs/assets/brand in Gaanim): ink and
--- paper for text, violet for keywords and the cursor's surroundings, gold for
--- types and titles, mist for rules and borders. Text colors are tuned to read
--- at 4.5:1 (WCAG AA) or more on every surface they sit on: the background,
--- the cursor line, floats and the selection.

---@class gaanim.theme.Palette
---@field bg string Editor background
---@field bg_float string Floats, sidebars, the statusline
---@field bg_cursor string Cursor line and column
---@field bg_visual string Selection
---@field bg_search string
---@field bg_hint string Under inlay hints
---@field bg_add string
---@field bg_delete string
---@field bg_change string
---@field bg_text string The changed text inside a changed line
---@field fg string
---@field fg_dim string Punctuation, secondary text
---@field comment string
---@field line_nr string Gutter numbers and other non-text marks (3:1)
---@field rule string Borders, splits, indent guides
---@field rule_strong string Active borders, the current scope
---@field nontext string Whitespace and fillers (decorative)
---@field ink string Strongest text
---@field violet string
---@field blue string
---@field teal string
---@field cyan string
---@field green string
---@field gold string
---@field gold_bright string Decorative gold: the cursor, the playhead sign
---@field orange string
---@field red string
---@field magenta string

local M = {}

-- Warm paper with ink a step lighter than the brand's, so long sessions do not
-- glare: no pure white, no saturated accents.
---@type gaanim.theme.Palette
M.light = {
  bg = "#F3F1EA",
  bg_float = "#E9E6DD",
  bg_cursor = "#EDEAE2",
  bg_visual = "#E3DFF4",
  bg_search = "#F2E0A6",
  bg_hint = "#EAE7F1",
  bg_add = "#DFEBD7",
  bg_delete = "#F2DCDA",
  bg_change = "#E3E2EE",
  bg_text = "#D3D0EC",
  fg = "#2A2640",
  fg_dim = "#55516C",
  comment = "#646079",
  line_nr = "#87839B",
  rule = "#D2CEDF",
  rule_strong = "#A9A2DA",
  nontext = "#C9C5D3",
  ink = "#14112E",
  violet = "#5040D0",
  blue = "#2F5FB0",
  teal = "#1E6D6D",
  cyan = "#196B87",
  green = "#386F35",
  gold = "#825B00",
  gold_bright = "#E09D00",
  orange = "#984E1D",
  red = "#AF3947",
  magenta = "#9A3E91",
}

-- Paper on graphite, the brand's own dark surface, with the paper dimmed so
-- the text does not burn on the black.
---@type gaanim.theme.Palette
M.dark = {
  bg = "#161616",
  bg_float = "#1C1C1E",
  bg_cursor = "#202023",
  bg_visual = "#2C2850",
  bg_search = "#4A3F1C",
  bg_hint = "#1F1E29",
  bg_add = "#1E2B1D",
  bg_delete = "#35201F",
  bg_change = "#222233",
  bg_text = "#363364",
  fg = "#E2E0EE",
  fg_dim = "#B4B0C8",
  comment = "#9793B6",
  line_nr = "#6A6686",
  rule = "#2E2C3A",
  rule_strong = "#5047B8",
  nontext = "#38364A",
  ink = "#F7F6FF",
  violet = "#A99FFF",
  blue = "#86AEEA",
  teal = "#79C6C2",
  cyan = "#7FC4DE",
  green = "#9DCC94",
  gold = "#EFC35E",
  gold_bright = "#FFC933",
  orange = "#EDA374",
  red = "#F08A8E",
  magenta = "#DA9CD6",
}

return M
