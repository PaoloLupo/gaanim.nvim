local check = require("gaanim.check")
local project_mod = require("gaanim.project")

describe("check", function()
  local root = vim.fs.joinpath(FIXTURES, "talk")
  local project = project_mod.load(root)
  local main = vim.fs.joinpath(root, "main.py")
  local script = vim.fs.joinpath(root, "assets", "narration", "script.md")

  it("passes a clean report", function()
    local report = check.parse(project, {
      "  ▸ check     main.py · presentation",
      "              3 segments · 4 stops · 4.2 seconds · 16×9",
      "  ✓ pass      Ready to present",
    })
    eq("pass", report.status)
    eq("Ready to present", report.summary)
    eq({}, report.items)
  end)

  it("points warnings at the script line, mark or segment they name", function()
    local report = check.parse(project, {
      "  ! warning   script.md: section `Intro` (line 3) matches no segment or voiceover",
      "  ! warning   segment `Problem`: mark 1 is [stop: question] but stop 1 is `asked`",
      "  ! warning   segment `Closing` has no speaker notes",
      "  ! warning   a 16:9 frame is expected",
      "  ✓ pass      with 4 warnings",
    })
    eq("warning", report.status)
    local where = vim.tbl_map(function(item)
      return { vim.fs.normalize(item.filename), item.lnum }
    end, report.items)
    eq({ { script, 3 }, { script, 17 }, { main, 27 }, { project.manifest, 1 } }, where)
  end)

  it("finds the stop a mark refers to", function()
    local report = check.parse(project, {
      "  ! warning   segment `Problem`: mark 1 is [stop q] but stop 1 is `question`",
    })
    eq(23, report.items[1].lnum)
  end)

  it("turns a traceback into an error at the project's frame", function()
    local report = check.parse(project, {
      "  ✗ check     could not load project: Traceback (most recent call last):",
      '  File "<string>", line 3, in <module>',
      '  File "<frozen runpy>", line 287, in run_path',
      '  File "' .. main:gsub("/", "\\") .. '", line 13, in <module>',
      "    scene.play([title.animate.wrte()])",
      "AttributeError: 'Anim' object has no attribute 'wrte'",
    })
    eq("error", report.status)
    eq(main, report.items[1].filename)
    eq(13, report.items[1].lnum)
    eq("AttributeError: 'Anim' object has no attribute 'wrte'", report.items[1].text)
  end)

  it("reads the error a preview prints after its traceback", function()
    local report = check.parse(project, {
      "  ✗ python    Script failed · fix it and save to reload",
      "Traceback (most recent call last):",
      '  File "' .. main .. '", line 30, in <module>',
      "NameError: name 'x' is not defined",
    })
    eq(30, report.items[1].lnum)
    eq("NameError: name 'x' is not defined", report.items[1].text)
  end)
end)
