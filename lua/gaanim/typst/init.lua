---@mod gaanim.typst Typst math completion in scene strings
---
--- Offers Typst's math symbols, with the character each one draws, and its
--- math functions inside `equation(...)` strings and the `$...$` spans of
--- other text. Symbols come from codex (`symbols.lua`, generated), the
--- functions from Typst's `math` module, both as Gaanim's Typst compiles them.

local context = require("gaanim.typst.context")

local M = {}

-- LSP CompletionItemKind values.
local KIND = { Function = 3, Constant = 21, Operator = 24, Module = 9, Snippet = 15 }
local SNIPPET = 2

---@class gaanim.TypstFunction
---@field [1] string Name
---@field [2] string Snippet body
---@field [3] string What it does

---@type gaanim.TypstFunction[]
M.functions = {
  { "frac", "frac(${1:a}, ${2:b})", "Fraction" },
  { "binom", "binom(${1:n}, ${2:k})", "Binomial coefficient" },
  { "sqrt", "sqrt(${1:x})", "Square root" },
  { "root", "root(${1:n}, ${2:x})", "n-th root" },
  { "vec", "vec(${1:a}, ${2:b})", "Column vector" },
  { "mat", "mat(${1:a}, ${2:b}; ${3:c}, ${4:d})", "Matrix: `,` between columns, `;` between rows" },
  { "cases", 'cases(${1:a} "if" ${2:x > 0}, ${3:b} "otherwise")', "Cases with a brace" },
  { "lr", "lr(${1:( x )})", "Scale delimiters to their content" },
  { "mid", "mid(${1:|})", "Delimiter scaled in the middle of `lr`" },
  { "abs", "abs(${1:x})", "Absolute value |x|" },
  { "norm", "norm(${1:x})", "Norm ‖x‖" },
  { "floor", "floor(${1:x})", "Floor ⌊x⌋" },
  { "ceil", "ceil(${1:x})", "Ceiling ⌈x⌉" },
  { "round", "round(${1:x})", "Round ⌊x⌉" },
  { "attach", "attach(${1:base}, t: ${2:top}, b: ${3:bottom})", "Attachments: t, b, tl, bl, tr, br" },
  { "scripts", "scripts(${1:x})", "Attachments as sub/superscripts" },
  { "limits", "limits(${1:x})", "Attachments as limits above and below" },
  { "stretch", "stretch(${1:arrow.r}, size: ${2:200%})", "Stretch a glyph" },
  { "accent", "accent(${1:x}, ${2:arrow})", "Accent over a base" },
  { "underline", "underline(${1:x})", "Line under" },
  { "overline", "overline(${1:x})", "Line over" },
  { "underbrace", "underbrace(${1:x}, ${2:label})", "Brace under, with a label" },
  { "overbrace", "overbrace(${1:x}, ${2:label})", "Brace over, with a label" },
  { "underbracket", "underbracket(${1:x}, ${2:label})", "Bracket under" },
  { "overbracket", "overbracket(${1:x}, ${2:label})", "Bracket over" },
  { "underparen", "underparen(${1:x}, ${2:label})", "Parenthesis under" },
  { "overparen", "overparen(${1:x}, ${2:label})", "Parenthesis over" },
  { "undershell", "undershell(${1:x}, ${2:label})", "Shell bracket under" },
  { "overshell", "overshell(${1:x}, ${2:label})", "Shell bracket over" },
  { "cancel", "cancel(${1:x})", "Strike through" },
  { "class", 'class("${1:normal}", ${2:x})', "Spacing class of an expression" },
  { "op", 'op("${1:name}")', "A text operator" },
  { "primes", "primes(${1:2})", "Prime marks" },
  { "upright", "upright(${1:x})", "Upright letters" },
  { "italic", "italic(${1:x})", "Italic letters" },
  { "bold", "bold(${1:x})", "Bold letters" },
  { "serif", "serif(${1:x})", "Serif letters" },
  { "sans", "sans(${1:x})", "Sans-serif letters" },
  { "cal", "cal(${1:x})", "Calligraphic letters" },
  { "scr", "scr(${1:x})", "Script letters" },
  { "frak", "frak(${1:x})", "Fraktur letters" },
  { "mono", "mono(${1:x})", "Monospace letters" },
  { "bb", "bb(${1:x})", "Blackboard bold letters" },
  { "display", "display(${1:x})", "Display size" },
  { "inline", "inline(${1:x})", "Inline size" },
  { "script", "script(${1:x})", "Script size" },
  { "sscript", "sscript(${1:x})", "Second-level script size" },
}

--- Accents that work as functions: `hat(x)`.
M.accents = {
  "grave",
  "acute",
  "hat",
  "tilde",
  "macron",
  "dash",
  "breve",
  "dot",
  "dot.double",
  "dot.triple",
  "dot.quad",
  "diaer",
  "circle",
  "acute.double",
  "caron",
  "arrow",
  "arrow.l",
  "arrow.l.r",
  "harpoon",
  "harpoon.lt",
}

--- Text operators, upright with their spacing: `sin`, `lim`…
M.operators = {
  "arccos",
  "arcsin",
  "arctan",
  "arg",
  "cos",
  "cosh",
  "cot",
  "coth",
  "csc",
  "csch",
  "ctg",
  "deg",
  "det",
  "dim",
  "exp",
  "gcd",
  "lcm",
  "hom",
  "id",
  "im",
  "inf",
  "ker",
  "lg",
  "lim",
  "liminf",
  "limsup",
  "ln",
  "log",
  "max",
  "min",
  "mod",
  "Pr",
  "sec",
  "sech",
  "sin",
  "sinc",
  "sinh",
  "sup",
  "tan",
  "tanh",
  "tg",
  "tr",
}

--- Spacing between math parts.
M.spaces = { thin = "1/6 em", med = "2/9 em", thick = "5/18 em", quad = "1 em", wide = "2 em" }

--- What a menu can show for a character: marks that combine with the one
--- before them get a dotted circle, and blanks a visible sign.
---@param text string
---@return string
function M.glyph(text)
  local blank = true
  for _, code in ipairs(vim.fn.str2list(text)) do
    local space = code <= 0x20
      or code == 0xA0
      or (code >= 0x2000 and code <= 0x200F)
      or (code >= 0x2028 and code <= 0x202F)
      or (code >= 0x205F and code <= 0x206F)
      or code == 0x3000
      or code == 0xFEFF
    blank = blank and space
  end
  if blank then
    return "␣"
  end
  local first = vim.fn.char2nr(text)
  local combining = (first >= 0x0300 and first <= 0x036F)
    or (first >= 0x1AB0 and first <= 0x1AFF)
    or (first >= 0x1DC0 and first <= 0x1DFF)
    or (first >= 0x20D0 and first <= 0x20FF)
    or (first >= 0xFE20 and first <= 0xFE2F)
  if combining then
    return "◌" .. text
  end
  return text
end

---@param text string
---@return string
local function codepoints(text)
  local out = {}
  for _, code in ipairs(vim.fn.str2list(text)) do
    table.insert(out, ("U+%04X"):format(code))
  end
  return table.concat(out, " ")
end

---@type { names: string[], text: table<string, string>, children: table<string, string[]> }?
local data

--- Symbols by name, and the names under each prefix.
local function load()
  if data then
    return data
  end
  data = { names = {}, text = {}, children = {} }
  for _, entry in ipairs(require("gaanim.typst.symbols")) do
    local name, text = entry[1], entry[2]
    table.insert(data.names, name)
    data.text[name] = text
  end
  return data
end

--- Symbol names one level under `parent` ("" for the top level), each with
--- the character of its own or its first variant.
---@param parent string
---@return { label: string, name: string, text: string }[]
local function symbols_under(parent)
  local d = load()
  local list = {}
  local seen = {}
  if parent == "" then
    for _, name in ipairs(d.names) do
      local base = name:match("^[^.]+")
      if not seen[base] then
        seen[base] = true
        table.insert(list, { label = base, name = base, text = d.text[base] or d.text[name] })
      end
    end
    return list
  end
  local start = parent .. "."
  for _, name in ipairs(d.names) do
    if vim.startswith(name, start) then
      table.insert(list, { label = name:sub(#start + 1), name = name, text = d.text[name] })
    end
  end
  return list
end

---@param name string
---@param text string
---@return lsp.MarkupContent
local function symbol_doc(name, text)
  return {
    kind = "markdown",
    value = ("`%s`  %s  %s\n\nTypst math symbol (codex %s)"):format(
      name,
      M.glyph(text),
      codepoints(text),
      require("gaanim.typst.symbols").version
    ),
  }
end

--- Completion items for a dotted name being typed in math: under `arrow.r.`
--- the variants of `arrow.r`; with no dot, symbols, functions, operators
--- and spaces.
---@param prefix string
---@return lsp.CompletionItem[]
function M.items(prefix)
  local parent = prefix:match("^(.*)%.[^.]*$") or ""
  local items = {}
  for _, symbol in ipairs(symbols_under(parent)) do
    local glyph = M.glyph(symbol.text)
    table.insert(items, {
      label = symbol.label,
      kind = KIND.Constant,
      kind_name = "Symbol",
      kind_icon = glyph,
      kind_hl = "Special",
      labelDetails = { description = glyph },
      insertText = symbol.label,
      documentation = symbol_doc(symbol.name, symbol.text),
    })
  end
  if parent ~= "" then
    for _, accent in ipairs(M.accents) do
      if vim.startswith(accent, parent .. ".") then
        local label = accent:sub(#parent + 2)
        table.insert(items, {
          label = label .. "(…)",
          filterText = label,
          kind = KIND.Function,
          labelDetails = { description = "accent" },
          insertText = label .. "(${1:x})",
          insertTextFormat = SNIPPET,
          documentation = { kind = "markdown", value = ("`%s(x)`: accent over x"):format(accent) },
        })
      end
    end
    return items
  end
  for _, fn in ipairs(M.functions) do
    table.insert(items, {
      label = fn[1] .. "(…)",
      filterText = fn[1],
      kind = KIND.Function,
      labelDetails = { description = fn[2]:gsub("%${%d+:([^}]*)}", "%1") },
      insertText = fn[2],
      insertTextFormat = SNIPPET,
      documentation = { kind = "markdown", value = ("`%s`: %s"):format(fn[1], fn[3]) },
    })
  end
  for _, accent in ipairs(M.accents) do
    if not accent:find(".", 1, true) then
      table.insert(items, {
        label = accent .. "(…)",
        filterText = accent,
        kind = KIND.Function,
        labelDetails = { description = "accent" },
        insertText = accent .. "(${1:x})",
        insertTextFormat = SNIPPET,
        documentation = { kind = "markdown", value = ("`%s(x)`: accent over x"):format(accent) },
      })
    end
  end
  for _, op in ipairs(M.operators) do
    table.insert(items, {
      label = op,
      kind = KIND.Operator,
      labelDetails = { description = "operator" },
      insertText = op,
      documentation = { kind = "markdown", value = ("`%s`: upright text operator"):format(op) },
    })
  end
  for name, size in vim.spairs(M.spaces) do
    table.insert(items, {
      label = name,
      kind = KIND.Constant,
      kind_icon = "␣",
      labelDetails = { description = "space " .. size },
      insertText = name,
      documentation = { kind = "markdown", value = ("`%s`: math space of %s"):format(name, size) },
    })
  end
  return items
end

--- Whether a buffer is a scene: Python in a Gaanim project, or importing it.
---@param buf integer
---@return boolean
function M.enabled(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  if vim.bo[buf].filetype ~= "python" then
    return false
  end
  local cached = vim.b[buf].gaanim_typst
  if cached == nil then
    cached = require("gaanim.project").current(buf) ~= nil
    vim.b[buf].gaanim_typst = cached
  end
  return cached
end

--- Items for the cursor, or nil outside Typst math.
---@param buf integer
---@param cursor integer[] { row (1-based), col (0-based) }
---@return lsp.CompletionItem[]?
function M.items_at(buf, cursor)
  local ctx = context.at(buf, cursor[1], cursor[2])
  if not (ctx and ctx.math) then
    return nil
  end
  return M.items(ctx.prefix)
end

return M
