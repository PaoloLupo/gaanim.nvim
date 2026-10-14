local index = require("gaanim.index")

---@param symbols gaanim.Symbol[]
---@param kinds table<string, boolean>
local function summary(symbols, kinds)
  local out = {}
  for _, s in ipairs(symbols) do
    if kinds[s.kind] then
      table.insert(out, ("%s:%s:%d"):format(s.kind, s.name or "", s.lnum))
    end
  end
  return out
end

describe("index", function()
  local root = vim.fs.joinpath(FIXTURES, "talk")
  local file = vim.fs.joinpath(root, "main.py")

  it("finds segments, stops, markers and voiceovers in order", function()
    local symbols = index.file_symbols(file)
    eq({
      "segment:Cover:10",
      "stop:title:14",
      "segment:Problem:17",
      "stop:question:23",
      "marker:answer:24",
      "stop::25",
      "segment:Closing:27",
      "voiceover:outro:28",
      "stop:thanks:30",
    }, summary(symbols, index.structure))
  end)

  it("skips calls inside comments", function()
    for _, s in ipairs(index.file_symbols(file)) do
      assert(s.name ~= "Commented out", "a commented call was indexed")
    end
  end)

  it("reads targets as arithmetic, on one line or several", function()
    local targets = {}
    for _, s in ipairs(index.file_symbols(file)) do
      if s.kind == "segment" or s.kind == "talk" then
        targets[s.name or s.kind] = s.target
      end
    end
    eq({ Cover = 30, Problem = 60, Closing = 90, talk = 240 }, targets)
  end)

  it("reads Section keys and titles", function()
    local symbols =
      index.parse('steps = [Section("4-1", [paso(a), paso(b)], title="Energy")]\nSectionStep(name=x)', "x.py")
    eq(1, #symbols)
    eq("section", symbols[1].kind)
    eq("4-1", symbols[1].name)
    eq("Energy", symbols[1].title)
  end)

  it("accepts project patterns", function()
    local config = require("gaanim.config")
    config.setup({ outline = { patterns = { { kind = "segment", pattern = '\nNAME%s*=%s*"([^"]+)"' } } } })
    local symbols = index.parse('"""Doc."""\nNAME = "Cover"\n', "slide.py")
    config.setup()
    eq("Cover", symbols[1] and symbols[1].name)
  end)

  it("knows the slide and stop under the cursor", function()
    vim.cmd.edit(vim.fn.fnameescape(file))
    vim.api.nvim_win_set_cursor(0, { 24, 0 })
    local here = index.at_cursor(0)
    eq("Problem", here.segment.name)
    eq(1, here.stop_index)
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    eq(nil, index.at_cursor(0).segment)
    vim.cmd("bwipeout!")
  end)

  it("evaluates only plain arithmetic", function()
    eq(240, index.eval_number("4 * 60"))
    eq(nil, index.eval_number("os.exit()"))
    eq(nil, index.eval_number("TOTAL"))
  end)
end)
