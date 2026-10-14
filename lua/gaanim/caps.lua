---@mod gaanim.caps What the installed gaanim can do
---
--- Newer Gaanim versions let an editor drive the preview (`--listen`), print
--- messages as JSON (`--message-format json`), list the timeline with its
--- script lines (`gaanim inspect`) and export by segment or stop name. The
--- plugin reads `gaanim --help` once to know which of these it can use, and
--- falls back to the plain CLI otherwise.

local M = {}

---@class gaanim.Caps
---@field listen boolean `--listen stdio`: drive the preview, hear the playhead
---@field json boolean `--message-format json`
---@field inspect boolean `gaanim inspect --json`
---@field names boolean `export --frame/--from/--to` take segment and stop names

--- What a help text says the executable supports.
---@param general string Output of `gaanim --help`
---@param export string Output of `gaanim export --help`
---@return gaanim.Caps
function M.parse(general, export)
  return {
    listen = general:find("--listen", 1, true) ~= nil,
    json = (general .. export):find("--message-format", 1, true) ~= nil,
    inspect = general:match("\n%s+inspect%s") ~= nil,
    names = export:find("<SECONDS|NAME>", 1, true) ~= nil,
  }
end

---@type table<string, gaanim.Caps>
local cache = {}

---@param cmd string[]
---@return string
local function help(cmd)
  local ok, result = pcall(function()
    return vim.system(cmd, { text = true, env = { NO_COLOR = "1" } }):wait(10000)
  end)
  if not ok or not result then
    return ""
  end
  return (result.stdout or "") .. (result.stderr or "")
end

--- The capabilities of the configured executable, read once.
---@return gaanim.Caps
function M.get()
  local cmd = require("gaanim.cli").executable()
  if not cmd then
    return { listen = false, json = false, inspect = false, names = false }
  end
  local key = table.concat(cmd, " ")
  if not cache[key] then
    local general = help(vim.list_extend(vim.deepcopy(cmd), { "--help" }))
    local export = help(vim.list_extend(vim.deepcopy(cmd), { "export", "--help" }))
    cache[key] = M.parse(general, export)
  end
  return cache[key]
end

--- Forget what was read, after the executable changes.
function M.reset()
  cache = {}
end

return M
