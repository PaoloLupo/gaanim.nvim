---@mod gaanim.index Segments, sections, stops and markers of a project
---
--- Scans the project's Python files with Lua patterns. It reads the scene's
--- structure the way it is written (`scene.segment("Intro")`, `scene.stop()`),
--- so names built at run time are missed unless a pattern in
--- `outline.patterns` describes the project's own convention.

local config = require("gaanim.config")

local M = {}

---@alias gaanim.SymbolKind "segment"|"section"|"stop"|"marker"|"voiceover"|"script"|"assets"|"talk"

---@class gaanim.Symbol
---@field kind gaanim.SymbolKind
---@field name? string Nil for an unnamed stop
---@field file string
---@field lnum integer 1-based
---@field col integer 1-based
---@field target? number Planned seconds of a segment
---@field title? string Title of a section

local Q = "[\"']"
local NAME = "([^\"'\n]*)"

---@type gaanim.OutlinePattern[]
M.builtin = {
  { kind = "segment", pattern = "%.segment%(%s*" .. Q .. NAME .. Q },
  { kind = "segment", pattern = "%.segment%(%s*name%s*=%s*" .. Q .. NAME .. Q },
  { kind = "section", pattern = "%f[%w_]Section%(%s*" .. Q .. NAME .. Q },
  { kind = "stop", pattern = "%.stop%(%s*" .. Q .. NAME .. Q },
  { kind = "stop", pattern = "%.stop%(%s*%)" },
  { kind = "marker", pattern = "%.marker%(%s*" .. Q .. NAME .. Q },
  { kind = "voiceover", pattern = "%.voiceover%(%s*" .. Q .. NAME .. Q },
  -- Not shown in the outline: they tell where the script is and how long
  -- the talk should last.
  { kind = "script", pattern = "%.narration_script%(%s*" .. Q .. NAME .. Q },
  { kind = "assets", pattern = "%.load_project%(%s*()%)" },
  { kind = "assets", pattern = "%.assets_dir%(%s*" .. Q .. NAME .. Q },
  { kind = "talk", pattern = "%.target%(%s*([%d%.%s%*%+%-/]+)%)" },
}

--- Kinds that are part of the scene's structure, as the outline shows it.
M.structure = { segment = true, section = true, voiceover = true, stop = true, marker = true }

--- True when the text before a match, on its line, opens a comment.
---@param prefix string
---@return boolean
local function in_comment(prefix)
  local quote
  for i = 1, #prefix do
    local c = prefix:sub(i, i)
    if quote then
      if c == quote then
        quote = nil
      end
    elseif c == '"' or c == "'" then
      quote = c
    elseif c == "#" then
      return true
    end
  end
  return false
end

--- The text of a call's arguments, from just after `(` to its matching `)`.
---@param text string
---@param open integer Position of the `(`
---@return string
local function call_args(text, open)
  local depth, quote, i = 0, nil, open
  local limit = math.min(#text, open + 4000)
  while i <= limit do
    local c = text:sub(i, i)
    if quote then
      if c == "\\" then
        i = i + 1
      elseif c == quote then
        quote = nil
      end
    elseif c == '"' or c == "'" then
      quote = c
    elseif c == "(" or c == "[" or c == "{" then
      depth = depth + 1
    elseif c == ")" or c == "]" or c == "}" then
      depth = depth - 1
      if depth == 0 then
        return text:sub(open + 1, i - 1)
      end
    end
    i = i + 1
  end
  return text:sub(open + 1, limit)
end

--- Evaluates a plain arithmetic literal such as `4 * 60` or `90`.
---@param expr string
---@return number?
function M.eval_number(expr)
  expr = vim.trim(expr)
  if expr == "" or not expr:match("^[%d%.%s%*%+%-/%(%)]+$") then
    return nil
  end
  local fn = loadstring("return " .. expr)
  if not fn then
    return nil
  end
  setfenv(fn, {})
  local ok, value = pcall(fn)
  return ok and type(value) == "number" and value or nil
end

---@param text string
---@return integer[] starts Byte offset where each line starts
local function line_starts(text)
  local starts = { 1 }
  for pos in text:gmatch("()\n") do
    table.insert(starts, pos + 1)
  end
  return starts
end

---@param starts integer[]
---@param pos integer
---@return integer lnum, integer col
local function position(starts, pos)
  local lo, hi = 1, #starts
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if starts[mid] <= pos then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return lo, pos - starts[lo] + 1
end

--- Finds every symbol in a piece of Python source.
---@param text string
---@param file string
---@return gaanim.Symbol[]
function M.parse(text, file)
  local patterns = vim.list_extend(vim.deepcopy(M.builtin), config.get().outline.patterns or {})
  local starts = line_starts(text)
  local symbols, seen = {}, {}
  for _, spec in ipairs(patterns) do
    local init = 1
    while true do
      local s, e, name = text:find(spec.pattern, init)
      if not s then
        break
      end
      init = e + 1
      local lnum, col = position(starts, s)
      local key = lnum .. ":" .. col
      local prefix = text:sub(starts[lnum], s - 1)
      if not seen[key] and not in_comment(prefix) then
        seen[key] = true
        ---@type gaanim.Symbol
        local symbol = { kind = spec.kind, file = file, lnum = lnum, col = col }
        if type(name) == "string" and name ~= "" then
          symbol.name = name
        end
        if spec.kind == "talk" then
          symbol.target = M.eval_number(name)
          symbol.name = nil
        end
        local open = text:find("(", s, true)
        if open and open <= e and spec.kind ~= "talk" then
          local args = call_args(text, open)
          if spec.kind == "segment" then
            local expr = args:match("target%s*=%s*([^,\n]+)")
            symbol.target = expr and M.eval_number(expr:gsub("%)%s*$", "")) or nil
          elseif spec.kind == "section" then
            symbol.title = args:match("title%s*=%s*" .. Q .. NAME .. Q)
          end
        end
        table.insert(symbols, symbol)
      end
    end
  end
  table.sort(symbols, function(a, b)
    return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col)
  end)
  return symbols
end

---@type table<string, { mtime: integer, size: integer, symbols: gaanim.Symbol[] }>
local cache = {}

--- The text of a file, from its loaded buffer when it has unsaved edits.
---@param file string
---@return string? text
---@return boolean? unsaved
local function read(file)
  local buf = vim.fn.bufnr(file)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"), true
  end
  local handle = io.open(file, "rb")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  return text
end

---@param file string
---@return gaanim.Symbol[]
function M.file_symbols(file)
  local stat = vim.uv.fs_stat(file)
  local entry = cache[file]
  local text, unsaved = read(file)
  if not text then
    return {}
  end
  if
    not unsaved
    and stat
    and entry
    and entry.mtime == stat.mtime.nsec + stat.mtime.sec * 1e9
    and entry.size == stat.size
  then
    return entry.symbols
  end
  local symbols = M.parse(text:gsub("\r\n", "\n"), file)
  if not unsaved and stat then
    cache[file] = { mtime = stat.mtime.nsec + stat.mtime.sec * 1e9, size = stat.size, symbols = symbols }
  end
  return symbols
end

--- Every symbol of a project, file by file (the entry script first).
---@param project gaanim.Project
---@return gaanim.Symbol[]
function M.project_symbols(project)
  local all = {}
  for _, file in ipairs(require("gaanim.project").python_files(project)) do
    vim.list_extend(all, M.file_symbols(file))
  end
  return all
end

---@type table<integer, { tick: integer, symbols: gaanim.Symbol[] }>
local buffers = {}

--- Symbols of a buffer as it is now, parsed again only after it changes.
---@param buf integer
---@return gaanim.Symbol[]
function M.buffer_symbols(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local entry = buffers[buf]
  if entry and entry.tick == tick then
    return entry.symbols
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local symbols = M.parse(text, vim.fs.normalize(vim.api.nvim_buf_get_name(buf)))
  buffers[buf] = { tick = tick, symbols = symbols }
  return symbols
end

--- The slide around the cursor: the last segment (or section) declared at or
--- above it in this buffer, and the stops between it and the cursor.
---@param buf? integer
---@return { segment?: gaanim.Symbol, stop?: gaanim.Symbol, stop_index: integer }
function M.at_cursor(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local win = buf == vim.api.nvim_get_current_buf() and 0 or vim.fn.bufwinid(buf)
  local lnum = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or 1
  local result = { stop_index = 0 }
  for _, symbol in ipairs(M.buffer_symbols(buf)) do
    if symbol.lnum > lnum then
      break
    end
    if (symbol.kind == "segment" or symbol.kind == "section" or symbol.kind == "voiceover") and symbol.name then
      result.segment, result.stop, result.stop_index = symbol, nil, 0
    elseif symbol.kind == "stop" then
      result.stop, result.stop_index = symbol, result.stop_index + 1
    end
  end
  return result
end

--- Where a segment, section or voiceover named `name` is declared.
---@param project gaanim.Project
---@param name string
---@param kinds? table<string, boolean>
---@return gaanim.Symbol?
function M.find(project, name, kinds)
  kinds = kinds or { segment = true, section = true, voiceover = true }
  for _, symbol in ipairs(M.project_symbols(project)) do
    if kinds[symbol.kind] and symbol.name == name then
      return symbol
    end
  end
end

return M
