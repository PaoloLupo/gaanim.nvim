-- Runs the specs in tests/spec with no dependencies:
--   nvim --headless --clean -l tests/run.lua [filter]
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(here)))
vim.opt.rtp:prepend(root)
vim.cmd("runtime plugin/gaanim.lua")

_G.FIXTURES = vim.fs.joinpath(root, "tests", "fixtures")

local results = { passed = 0, failed = 0 }
local current = {}

function _G.describe(name, fn)
  table.insert(current, name)
  fn()
  table.remove(current)
end

function _G.it(name, fn)
  local title = table.concat(current, " › ") .. " › " .. name
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    results.passed = results.passed + 1
  else
    results.failed = results.failed + 1
    io.stdout:write("FAIL " .. title .. "\n" .. tostring(err) .. "\n\n")
  end
end

function _G.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(
      ("%sexpected %s, got %s"):format(message and (message .. ": ") or "", vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

--- A path as the system writes it: with backslashes on Windows.
function _G.native(path)
  return vim.fn.has("win32") == 1 and (path:gsub("/", "\\")) or path
end

local filter = arg[1]
local specs = vim.fn.glob(vim.fs.joinpath(root, "tests", "spec", "*_spec.lua"), false, true)
table.sort(specs)
for _, spec in ipairs(specs) do
  if not filter or spec:find(filter, 1, true) then
    dofile(spec)
  end
end

io.stdout:write(("%d passed, %d failed\n"):format(results.passed, results.failed))
os.exit(results.failed == 0 and 0 or 1)
