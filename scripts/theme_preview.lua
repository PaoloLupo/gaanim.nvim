-- Renders a sample of the Gaanim colorscheme, light and dark side by side, to
-- an HTML page: a scene with inlay hints, code lenses and diagnostics as the
-- Gaanim server and basedpyright draw them, and the editor's UI groups.
--   nvim --headless --clean -l scripts/theme_preview.lua [out.html]
-- Python is colored by Treesitter when its parser is installed (as
-- nvim-treesitter does, under stdpath("data")/site).
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(here)))
local out = arg[1] or vim.fs.joinpath(vim.fn.stdpath("cache"), "gaanim-theme-preview.html")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fs.joinpath(vim.fn.stdpath("data"), "site"))
vim.cmd("packadd nvim.tohtml")
vim.o.guifont = "JetBrainsMono Nerd Font,JetBrains Mono,Cascadia Mono,Consolas:h11"
vim.o.columns, vim.o.lines = 110, 60
vim.o.termguicolors = true

local code = {
  '"""Sales 2026: the quarter in three slides."""',
  "",
  "from dataclasses import dataclass",
  "",
  "from gaanim import Scene, Transition, lecture, title_slide",
  "",
  "",
  "@dataclass(frozen=True)",
  "class Quarter:",
  "    name: str",
  "    sales: float",
  "",
  "    def label(self) -> str:",
  '        return f"{self.name}: {self.sales:.1f} M€\\n"',
  "",
  "",
  'scene = Scene(theme="gaanim")',
  'QUARTERS = [Quarter("Q1", 1.2), Quarter("Q2", 2.75), Quarter("Q3", 3.1)]',
  "",
  'cover = scene.segment("Cover", template=title_slide, target=30)',
  'title = scene.text("Sales 2026", role="title")',
  "scene.play([title.animate.write().duration(0.8)])",
  'scene.stop("title")',
  "",
  "# TODO: a chart per quarter, not one for the year",
  'chart = scene.segment("Chart", Transition.slide(0.5, "left"), template=lecture)',
  "bars = [scene.viz.bar(q.sales, label=q.label()) for q in QUARTERS if q.sales > 1]",
  "scene.play([bar.animate.grow() for bar in bars], lag=0.15)",
  "scene.stop(undefined_name)",
  "",
  "scene.render()",
}

local ui = {
  "  Normal text on the editor background            ",
  "  Cursor line                                     ",
  "  Visual selection                                ",
  "  Search match   Current match                    ",
  "  Pmenu item                     Function  [LSP]  ",
  "  Pmenu selected                 Method    [LSP]  ",
  "  Float with its border, title and text           ",
  "  StatusLine  NORMAL  main.py   󰐊 0:01.8 Cover    ",
  "  DiffAdd line                                    ",
  "  DiffDelete line                                 ",
  "  DiffChange line with DiffText inside            ",
  "  Error  Warn  Info  Hint  Ok                     ",
  "  TODO  FIX  HACK  WARN  NOTE  PERF  TEST         ",
  "  Flash label  a  s  d   Directory/  Title        ",
}

local function hl(buf, ns, row, col, end_col, group)
  vim.api.nvim_buf_set_extmark(buf, ns, row, col, { end_col = end_col, hl_group = group, priority = 50 })
end

local function find(lines, row, text)
  local s = lines[row + 1]:find(text, 1, true)
  return s - 1, s - 1 + #text
end

--- The sample buffers, decorated, for the colorscheme loaded now.
local function render(variant)
  vim.cmd.colorscheme("gaanim-" .. variant)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, code)
  vim.bo[buf].filetype = "python"
  pcall(vim.treesitter.start, buf, "python")
  vim.wo.number = true
  local ns = vim.api.nvim_create_namespace("gaanim.preview")
  local function hint(row, text)
    vim.api.nvim_buf_set_extmark(buf, ns, row, #code[row + 1], {
      virt_text = { { " " }, { " " .. text .. " ", "LspInlayHint" } },
      virt_text_pos = "inline",
    })
  end
  local function lens(row, text)
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
      virt_lines = { { { text, "LspCodeLens" } } },
      virt_lines_above = true,
    })
  end
  lens(19, "󰐊 Preview  󰑖 Loop  󰋩 Still  󰍬 ≈0:08 / 0:30  󰔛 0:00.0–0:01.3")
  hint(21, "󰐊 0:00.0–0:00.8")
  hint(22, "󰏤 0:00.8")
  lens(25, "󰐊 Preview  󰑖 Loop  󰋩 Still  󰔛 0:01.3–0:02.6")
  hint(27, "󰐊 0:01.8–0:02.6")
  vim.api.nvim_buf_set_extmark(buf, ns, 21, 0, { sign_text = "󰐊", sign_hl_group = "GaanimPlayhead" })
  local s, e = find(code, 26, "QUARTERS")
  hl(buf, ns, 26, s, e, "LspReferenceText")
  hl(buf, ns, 17, 0, 8, "LspReferenceText")
  s, e = find(code, 20, '"Sales 2026"')
  hl(buf, ns, 20, s, e, "Visual")
  s, e = find(code, 13, "self.sales")
  hl(buf, ns, 13, s, e, "Search")
  vim.diagnostic.config({ virtual_text = true, underline = true, signs = false })
  vim.diagnostic.set(vim.api.nvim_create_namespace("gaanim.preview.diag"), buf, {
    {
      lnum = 28,
      col = 11,
      end_col = 25,
      severity = vim.diagnostic.severity.ERROR,
      message = '"undefined_name" is not defined',
    },
    { lnum = 2, col = 0, end_col = 33, severity = vim.diagnostic.severity.HINT, message = "Import is not accessed" },
    { lnum = 24, col = 2, end_col = 6, severity = vim.diagnostic.severity.WARN, message = "Unfinished slide" },
  })
  local code_html = require("tohtml").tohtml(0, { title = "gaanim-" .. variant, number_lines = true })

  local ubuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, ubuf)
  vim.api.nvim_buf_set_lines(ubuf, 0, -1, false, ui)
  vim.wo.number = false
  local function line(row, group)
    hl(ubuf, ns, row, 0, #ui[row + 1], group)
  end
  local function word(row, text, group)
    local a, b = find(ui, row, text)
    hl(ubuf, ns, row, a, b, group)
  end
  line(1, "CursorLine")
  line(2, "Visual")
  word(3, "Search match", "Search")
  word(3, "Current match", "CurSearch")
  line(4, "Pmenu")
  word(4, "Function", "PmenuKind")
  word(4, "[LSP]", "PmenuExtra")
  word(4, "Pm", "PmenuMatch")
  line(5, "PmenuSel")
  word(5, "Method", "PmenuKindSel")
  word(5, "[LSP]", "PmenuExtraSel")
  line(6, "NormalFloat")
  word(6, "border", "FloatBorder")
  word(6, "title", "FloatTitle")
  line(7, "StatusLine")
  word(7, "NORMAL", "lualine_a_normal")
  word(7, "󰐊 0:01.8 Cover", "GaanimPlayhead")
  line(8, "DiffAdd")
  line(9, "DiffDelete")
  line(10, "DiffChange")
  word(10, "DiffText", "DiffText")
  for _, kind in ipairs({ "Error", "Warn", "Info", "Hint", "Ok" }) do
    word(11, kind, "DiagnosticVirtualText" .. kind)
  end
  for _, kind in ipairs({ "TODO", "FIX", "HACK", "WARN", "NOTE", "PERF", "TEST" }) do
    word(12, kind, "TodoBg" .. kind)
  end
  for _, key in ipairs({ " a ", " s ", " d " }) do
    word(13, key, "FlashLabel")
  end
  word(13, "Directory/", "Directory")
  word(13, "Title", "Title")
  local lualine = require("gaanim.theme").lualine(variant)
  vim.api.nvim_set_hl(0, "lualine_a_normal", { fg = lualine.normal.a.fg, bg = lualine.normal.a.bg, bold = true })
  local ui_html = require("tohtml").tohtml(0, { title = "ui" })
  return table.concat(code_html, "\n"), table.concat(ui_html, "\n")
end

local function srcdoc(html)
  return (html:gsub("&", "&amp;"):gsub('"', "&quot;"))
end

local columns = {}
for _, variant in ipairs({ "light", "dark" }) do
  local code_html, ui_html = render(variant)
  local c = require("gaanim.theme").colors(variant)
  table.insert(
    columns,
    ([[<section style="background:%s;color:%s"><h2>gaanim-%s</h2>
<iframe class="code" srcdoc="%s"></iframe><iframe class="ui" srcdoc="%s"></iframe></section>]]):format(
      c.bg_float,
      c.fg,
      variant,
      srcdoc(code_html),
      srcdoc(ui_html)
    )
  )
end

local page = ([[<!doctype html>
<html><head><meta charset="utf-8"><title>Gaanim colorscheme</title>
<style>
  body { margin: 0; background: #888; font-family: "JetBrains Mono", Consolas, monospace; }
  main { display: grid; grid-template-columns: repeat(auto-fit, minmax(560px, 1fr)); }
  section { padding: 12px 16px 16px; }
  h2 { font-size: 14px; font-weight: 600; margin: 0 0 8px; }
  iframe { width: 100%%; border: 0; display: block; }
  iframe.code { height: 720px; }
  iframe.ui { height: 330px; margin-top: 8px; }
</style></head>
<body><main>%s</main></body></html>
]]):format(table.concat(columns, "\n"))

local file = assert(io.open(out, "w"))
file:write(page)
file:close()
io.stdout:write(out .. "\n")
