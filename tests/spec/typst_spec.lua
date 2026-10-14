local context = require("gaanim.typst.context")
local typst = require("gaanim.typst")

--- The context at the `|` of a snippet of Python.
---@param source string
local function at(source)
  local cut = source:find("|", 1, true)
  return context.scan(source:sub(1, cut - 1))
end

describe("typst context", function()
  it("treats every string of equation(...) as math", function()
    local ctx = at('eq = scene.text.equation("x^2 + al|")')
    eq(true, ctx.math)
    eq("equation", ctx.call)
    eq("al", ctx.prefix)
  end)

  it("reads the dotted name being typed", function()
    eq("arrow.r.do", at('scene.text.equation("a arrow.r.do|")').prefix)
    eq("", at('scene.text.equation("a + |")').prefix)
  end)

  it("follows the arguments of a call across lines and parts", function()
    local ctx = at('scene.text.equation(\n    "a",\n    part,\n    "= sq|"\n)')
    eq(true, ctx.math)
    eq("sq", ctx.prefix)
  end)

  it("leaves keyword arguments of equation(...) alone", function()
    eq(false, at('scene.text.equation("x", color="re|")').math)
    eq(false, at('scene.text.equation("x", font = "New Comp|")').math)
  end)

  it("uses $...$ in other text", function()
    eq(true, at('scene.text("Energy $E = m c^2 + al|")').math)
    eq(false, at('scene.text("Energy $E$ is conserved, al|")').math)
    eq(false, at('scene.text("costs \\$5 and al|")').math)
  end)

  it("ignores code, comments and Typst code mode", function()
    eq(nil, at("scene.text.equation(al|"))
    eq(nil, at('# scene.text.equation("al|'))
    eq(false, at('scene.text.equation("#al|")').math)
    eq(nil, at('scene.text.equation("x")\nal|'))
  end)

  it("handles prefixes, triple quotes and escapes", function()
    eq(true, at('scene.text.equation(r"\\frac al|")').math)
    eq(true, at("scene.text.equation('''\nx = al|").math)
    eq(true, at('scene.text.equation("say \\"hi\\" al|")').math)
    eq(false, at('scene.text(f"{x} al|")').math)
  end)
end)

describe("typst items", function()
  local function find(items, label)
    for _, item in ipairs(items) do
      if item.label == label then
        return item
      end
    end
  end

  it("offers symbols with the character as icon, functions and operators", function()
    local items = typst.items("al")
    local alpha = find(items, "alpha")
    eq("α", alpha.kind_icon)
    eq("α", alpha.labelDetails.description)
    eq("frac", find(items, "frac(…)").filterText)
    eq(2, find(items, "frac(…)").insertTextFormat)
    eq(24, find(items, "sin").kind)
    eq("␣", find(items, "quad").kind_icon)
  end)

  it("offers the variants under a dotted name", function()
    local items = typst.items("arrow.r.")
    eq("⇒", find(items, "double").kind_icon)
    eq("⟹", find(items, "double.long").kind_icon)
    eq(nil, find(items, "alpha"))
  end)

  it("draws combining marks on a dotted circle and blanks as ␣", function()
    eq("◌\204\129", typst.glyph("\204\129"))
    eq("␣", typst.glyph("\194\160"))
    eq("∫", typst.glyph("∫"))
  end)

  it("knows codex's names and leaves deprecated ones out", function()
    local names = {}
    for _, entry in ipairs(require("gaanim.typst.symbols")) do
      names[entry[1]] = entry[2]
    end
    eq("0.3.0", require("gaanim.typst.symbols").version)
    eq("≤", names["lt.eq"])
    eq("∑", names["sum"])
    eq(nil, names["gt.tri"])
  end)

  it("completes in a scene buffer", function()
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(FIXTURES, "talk", "main.py")))
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { 'eq = scene.text.equation("x arrow.r.' })
    local row = vim.api.nvim_buf_line_count(0)
    local items = typst.items_at(0, { row, #vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] })
    eq("⇒", find(items, "double").kind_icon)
    eq(nil, typst.items_at(0, { 5, 0 }))
    vim.cmd("bwipeout!")
  end)
end)
