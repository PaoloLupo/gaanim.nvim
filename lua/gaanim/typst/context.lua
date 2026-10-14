---@mod gaanim.typst.context Is the cursor in Typst math?
---
--- Gaanim reads Typst math in two places of a scene's Python: every string
--- passed to `equation(...)` (`scene.text.equation("x^2 + y")`, without `$`),
--- and the `$...$` spans of any other text. This scanner walks the Python up
--- to the cursor (strings, comments, brackets) without a parser, so it works
--- with or without Tree-sitter.

local M = {}

local OPEN = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local CLOSE = { [")"] = true, ["]"] = true, ["}"] = true }

---@class gaanim.TypstContext
---@field math boolean The cursor is in Typst math
---@field call? string Last name of the call whose argument the string is
---@field keyword boolean The string is a keyword argument (`color="..."`)
---@field content string String content from its start to the cursor
---@field prefix string Dotted name being typed (`arrow.r.do`), maybe ""

--- Whether `$` at `i` is escaped by a backslash.
---@param text string
---@param i integer
---@return boolean
local function escaped(text, i)
  local count = 0
  i = i - 1
  while i > 0 and text:sub(i, i) == "\\" do
    count = count + 1
    i = i - 1
  end
  return count % 2 == 1
end

--- Unescaped `$` signs in `text`.
---@param text string
---@return integer
local function dollars(text)
  local count = 0
  for i = 1, #text do
    if text:sub(i, i) == "$" and not escaped(text, i) then
      count = count + 1
    end
  end
  return count
end

--- Scans Python source and describes the string the end of `text` is in,
--- or returns nil when it ends outside a string.
---@param text string Source from the file start to the cursor
---@return gaanim.TypstContext?
function M.scan(text)
  local stack = {} ---@type { char: string, name?: string, sep: integer }[]
  local i, n = 1, #text
  local string_start, quote, triple, raw
  while i <= n do
    local c = text:sub(i, i)
    if string_start then
      if c == "\\" and not raw then
        i = i + 2
      elseif triple and text:sub(i, i + 2) == quote:rep(3) then
        string_start = nil
        i = i + 3
      elseif not triple and c == quote then
        string_start = nil
        i = i + 1
      elseif not triple and c == "\n" then
        -- An unclosed one-line string ends with its line.
        string_start = nil
        i = i + 1
      else
        i = i + 1
      end
    elseif c == "#" then
      local newline = text:find("\n", i, true)
      if not newline then
        return nil
      end
      i = newline + 1
    elseif c == '"' or c == "'" then
      local prefix = text:sub(math.max(1, i - 3), i - 1):match("([%a]*)$") or ""
      local before = text:sub(i - #prefix - 1, i - #prefix - 1)
      if #prefix > 2 or not prefix:lower():match("^[rbfu]*$") or before:match("[%w_]") then
        prefix = ""
      end
      raw = prefix:lower():find("r", 1, true) ~= nil
      quote = c
      triple = text:sub(i, i + 2) == c:rep(3)
      i = i + (triple and 3 or 1)
      string_start = i
    elseif OPEN[c] then
      local name = c == "(" and text:sub(math.max(1, i - 120), i - 1):match("([%a_][%w_%.]*)%s*$") or nil
      table.insert(stack, { char = c, name = name, sep = i })
      i = i + 1
    elseif CLOSE[c] then
      table.remove(stack)
      i = i + 1
    else
      if c == "," and #stack > 0 then
        stack[#stack].sep = i
      end
      i = i + 1
    end
  end
  if not string_start then
    return nil
  end
  local content = text:sub(string_start)
  local frame = stack[#stack]
  local call, keyword = nil, false
  if frame and frame.char == "(" then
    call = frame.name and frame.name:match("([%a_][%w_]*)$")
    local opening = string_start - (triple and 3 or 1)
    local before = text:sub(frame.sep + 1, opening - 1):gsub("[%a]*$", "")
    keyword = before:match("[%a_][%w_]*%s*=%s*$") ~= nil
  end
  local equation = call == "equation" and not keyword
  local math = equation or dollars(content) % 2 == 1
  local prefix = ""
  if math then
    prefix = content:match("([%a][%w%.]*)$") or ""
    local before = content:sub(1, #content - #prefix)
    -- `#name` is Typst code, and `\name` an escape: not math names.
    if before:match("[#\\]$") then
      return { math = false, call = call, keyword = keyword, content = content, prefix = "" }
    end
  end
  return { math = math, call = call, keyword = keyword, content = content, prefix = prefix }
end

--- The context at a cursor in a buffer.
---@param buf integer
---@param row integer 1-based
---@param col integer 0-based byte column
---@return gaanim.TypstContext?
function M.at(buf, row, col)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, row, false)
  if #lines == 0 then
    return nil
  end
  lines[#lines] = lines[#lines]:sub(1, col)
  return M.scan(table.concat(lines, "\n"))
end

return M
