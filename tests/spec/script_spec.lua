local script = require("gaanim.script")
local project_mod = require("gaanim.project")

describe("script", function()
  local root = vim.fs.joinpath(FIXTURES, "talk")
  local path = vim.fs.joinpath(root, "assets", "narration", "script.md")

  it("reads stop marks the way Gaanim does", function()
    eq("", script.mark("[stop]"))
    eq("title", script.mark("  [stop title] "))
    eq("question", script.mark("[stop: question]"))
    eq("x", script.mark("[STOP x]"))
    eq(false, script.mark("[stopwatch]"))
    eq(false, script.mark("text [stop]"))
  end)

  it("splits sections, skipping comments and author notes", function()
    local parsed = script.parse(vim.fn.readfile(path))
    eq(1, parsed.title)
    local names, words, marks = {}, {}, {}
    for _, section in ipairs(parsed.sections) do
      table.insert(names, section.name)
      words[section.name] = section.words
      marks[section.name] = vim.tbl_map(function(m)
        return m.name
      end, section.marks)
    end
    eq({ "Cover", "problem", "Closing" }, names)
    eq(9, words.Cover, "the dictated comment is not read")
    eq(11, words.problem, "the ### note is not read")
    eq({ "question", "" }, marks.problem)
    eq(0, words.Closing)
  end)

  it("matches sections ignoring case", function()
    local parsed = script.parse(vim.fn.readfile(path))
    eq("problem", script.find_section(parsed, "Problem").name)
  end)

  it("finds the script in the asset directory", function()
    local p, exists = script.path(project_mod.load(root))
    eq(path, p)
    eq(true, exists)
  end)

  it("adds a missing section after the slide before it, with its stops", function()
    local project = project_mod.load(root)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Script", "", "## Cover", "Hi.", "", "## Closing", "Bye." })
    local lnum = script.add_section(project, buf, "Problem")
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq("## Problem", lines[lnum])
    eq({
      "# Script",
      "",
      "## Cover",
      "Hi.",
      "",
      "## Problem",
      "",
      "[stop question]",
      "",
      "[stop]",
      "",
      "## Closing",
      "Bye.",
    }, lines)
  end)

  it("formats clock times", function()
    eq("0:42", script.clock(42.4))
    eq("4:00", script.clock(240))
    eq("1:00:05", script.clock(3605))
  end)
end)
