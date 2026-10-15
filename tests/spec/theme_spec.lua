local theme = require("gaanim.theme")

-- WCAG 2 contrast ratio between two "#RRGGBB" colors.
local function contrast(a, b)
  local function luminance(hex)
    local function channel(i)
      local v = tonumber(hex:sub(i, i + 1), 16) / 255
      return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * channel(2) + 0.7152 * channel(4) + 0.0722 * channel(6)
  end
  local la, lb = luminance(a), luminance(b)
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

local function hex(n)
  return n and ("#%06X"):format(n)
end

-- Groups whose text has to read at AA on its own background (or Normal's).
local text_groups = {
  "Normal",
  "NormalFloat",
  "FloatTitle",
  "FloatFooter",
  "Comment",
  "String",
  "Number",
  "Function",
  "Keyword",
  "Type",
  "Constant",
  "Special",
  "PreProc",
  "Operator",
  "Delimiter",
  "@variable.member",
  "@variable.builtin",
  "@property",
  "@attribute",
  "@module",
  "@string.escape",
  "@markup.heading.1",
  "@markup.heading.2",
  "@markup.raw",
  "@markup.link.url",
  "LspInlayHint",
  "LspCodeLens",
  "DiagnosticError",
  "DiagnosticWarn",
  "DiagnosticInfo",
  "DiagnosticHint",
  "DiagnosticOk",
  "DiagnosticVirtualTextError",
  "DiagnosticVirtualTextWarn",
  "DiagnosticVirtualTextInfo",
  "DiagnosticVirtualTextHint",
  "DiagnosticVirtualTextOk",
  "StatusLine",
  "StatusLineNC",
  "TabLine",
  "TabLineSel",
  "WinBar",
  "Pmenu",
  "PmenuKind",
  "PmenuExtra",
  "PmenuMatch",
  "PmenuMatchSel",
  "Search",
  "CurSearch",
  "Substitute",
  "Todo",
  "Folded",
  "CursorLineNr",
  "Title",
  "Directory",
  "ErrorMsg",
  "WarningMsg",
  "MoreMsg",
  "MatchParen",
  "DiffDelete",
  "GaanimPlayhead",
  "GaanimPlayheadText",
  "FlashLabel",
  "FlashMatch",
  "FlashCurrent",
  "TodoBgTODO",
  "TodoBgFIX",
  "TodoBgHACK",
  "TodoBgWARN",
  "TodoBgNOTE",
  "TodoBgPERF",
  "TodoBgTEST",
  "LazyH1",
  "LazyButtonActive",
  "MasonHeader",
  "TroubleCount",
  "GrugFarResultsMatch",
  "SnacksPickerMatch",
  "SnacksPickerDir",
  "BlinkCmpLabelMatch",
  "BlinkCmpLabelDetail",
  "WhichKey",
  "WhichKeyGroup",
  "WhichKeyDesc",
  "WhichKeySeparator",
  "RenderMarkdownCodeInline",
}

-- Text colors that land on any surface: the cursor line, floats, the
-- selection.
local text_colors =
  { "fg", "fg_dim", "comment", "violet", "blue", "teal", "cyan", "green", "gold", "orange", "red", "magenta" }
local surfaces = { "bg", "bg_cursor", "bg_float", "bg_visual" }

for _, variant in ipairs({ "light", "dark" }) do
  describe("colorscheme gaanim-" .. variant, function()
    it("sets 'background' and its name", function()
      vim.cmd.colorscheme("gaanim-" .. variant)
      eq(variant, vim.o.background)
      eq("gaanim-" .. variant, vim.g.colors_name)
      eq(theme.colors(variant).bg, hex(vim.api.nvim_get_hl(0, { name = "Normal" }).bg))
    end)

    it("reads every text group at 4.5:1 or more", function()
      vim.cmd.colorscheme("gaanim-" .. variant)
      local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
      for _, name in ipairs(text_groups) do
        local spec = vim.api.nvim_get_hl(0, { name = name, link = false })
        local fg, bg = hex(spec.fg or normal.fg), hex(spec.bg or normal.bg)
        local ratio = contrast(fg, bg)
        assert(ratio >= 4.5, ("%s: %s on %s is %.2f:1"):format(name, fg, bg, ratio))
      end
    end)

    it("keeps text colors at 4.5:1 on every surface", function()
      local c = theme.colors(variant)
      for _, fg in ipairs(text_colors) do
        for _, bg in ipairs(surfaces) do
          local ratio = contrast(c[fg], c[bg])
          assert(ratio >= 4.5, ("%s on %s is %.2f:1"):format(fg, bg, ratio))
        end
      end
      assert(contrast(c.comment, c.bg_hint) >= 4.5, "comment on bg_hint")
      assert(contrast(c.line_nr, c.bg) >= 3, "line numbers at 3:1")
    end)

    it("gives lualine a theme", function()
      local lualine = theme.lualine(variant)
      eq(theme.colors(variant).violet, lualine.normal.a.bg)
    end)
  end)
end

describe("colorscheme gaanim", function()
  it("follows 'background'", function()
    vim.o.background = "dark"
    vim.cmd.colorscheme("gaanim")
    eq(theme.colors("dark").bg, hex(vim.api.nvim_get_hl(0, { name = "Normal" }).bg))
    vim.o.background = "light"
    eq("gaanim", vim.g.colors_name)
    eq(theme.colors("light").bg, hex(vim.api.nvim_get_hl(0, { name = "Normal" }).bg))
  end)

  it("applies on_highlights", function()
    theme.setup({
      on_highlights = function(hl, c)
        hl.Comment = { fg = c.violet }
      end,
    })
    vim.cmd.colorscheme("gaanim")
    eq(theme.colors(vim.o.background).violet, hex(vim.api.nvim_get_hl(0, { name = "Comment" }).fg))
    theme.config.on_highlights = nil
    vim.cmd.colorscheme("gaanim")
  end)
end)
