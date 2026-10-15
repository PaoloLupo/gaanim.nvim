---@mod gaanim.theme The Gaanim colorscheme
---
--- `:colorscheme gaanim` follows 'background'; `gaanim-light` and
--- `gaanim-dark` set it. Options go through `require("gaanim.theme").setup()`
--- before the colorscheme loads.

local M = {}

---@class gaanim.theme.Config
---@field transparent boolean Leave the editor and float backgrounds to the terminal
---@field italic boolean Italic comments, builtins and parameters
---@field on_colors? fun(colors: gaanim.theme.Palette, variant: "light"|"dark")
---@field on_highlights? fun(groups: table<string, vim.api.keyset.highlight>, colors: gaanim.theme.Palette, variant: "light"|"dark")

---@type gaanim.theme.Config
M.config = { transparent = false, italic = true }

---@param opts? gaanim.theme.Config
function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
end

--- The palette of `variant` after `on_colors`.
---@param variant "light"|"dark"
---@return gaanim.theme.Palette
function M.colors(variant)
  local colors = vim.deepcopy(require("gaanim.theme.palette")[variant])
  if M.config.on_colors then
    M.config.on_colors(colors, variant)
  end
  return colors
end

--- Loads the colorscheme. With a `variant`, 'background' is set to it;
--- without one, the variant follows 'background'.
---@param variant? "light"|"dark"
function M.load(variant)
  if vim.g.colors_name then
    vim.cmd("highlight clear")
  end
  -- Cleared first so setting 'background' does not reload the previous
  -- colorscheme.
  vim.g.colors_name = nil
  if variant and vim.o.background ~= variant then
    vim.o.background = variant
  end
  variant = variant or vim.o.background --[[@as "light"|"dark"]]

  local colors = M.colors(variant)
  local groups = require("gaanim.theme.groups")
  local hl = groups.get(colors, M.config)
  if M.config.on_highlights then
    M.config.on_highlights(hl, colors, variant)
  end
  for name, spec in pairs(hl) do
    vim.api.nvim_set_hl(0, name, spec)
  end
  for i, color in ipairs(groups.terminal(colors)) do
    vim.g["terminal_color_" .. (i - 1)] = color
  end
end

--- A lualine theme in the colors of `variant`.
---@param variant "light"|"dark"
function M.lualine(variant)
  local c = M.colors(variant)
  local function mode(color)
    return {
      a = { fg = c.bg, bg = color, gui = "bold" },
      b = { fg = color, bg = c.bg_cursor },
      c = { fg = c.fg_dim, bg = c.bg_float },
    }
  end
  local inactive = { fg = c.comment, bg = c.bg_float }
  return {
    normal = mode(c.violet),
    insert = mode(c.green),
    visual = mode(c.gold),
    replace = mode(c.red),
    command = mode(c.orange),
    terminal = mode(c.teal),
    inactive = { a = inactive, b = inactive, c = inactive },
  }
end

return M
