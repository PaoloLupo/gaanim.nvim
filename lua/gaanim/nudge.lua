---@mod gaanim.nudge Nudging the number under the cursor
---
--- Like CTRL-A and CTRL-X, but for decimals too: `0.8` steps by `0.1`,
--- `0.25` by `0.01`, `3` by `1`, times the count. With live mode on, each
--- nudge reaches the preview a moment later. Outside Gaanim projects it
--- falls back to CTRL-A and CTRL-X.

local M = {}

--- The number at or after a byte column of a line: its start and end
--- (1-based, inclusive) and its text.
---@param line string
---@param col integer 0-based cursor column
---@return integer? start, integer? finish, string? text
function M.find(line, col)
  local init = 1
  while true do
    local s, e = line:find("%-?%d+%.?%d*", init)
    if not s then
      return nil
    end
    local before = line:sub(s - 1, s - 1)
    local identifier = before:match("[%w_]") ~= nil
    if line:sub(s, s) == "-" and before:match("[%w_%)%]]") then
      -- `x-1` subtracts: the number starts after the minus.
      s = s + 1
      identifier = false
    end
    if not identifier and e >= col + 1 then
      return s, e, line:sub(s, e)
    end
    init = e + 1
  end
end

--- The text of `text` moved by `steps` of its own precision.
---@param text string
---@param steps integer
---@return string
function M.step(text, steps)
  local decimals = #(text:match("%.(%d*)$") or "")
  local value = tonumber(text) + steps * 10 ^ -decimals
  local result = ("%." .. decimals .. "f"):format(value)
  if decimals > 0 and text:sub(-1) == "." then
    result = result .. "."
  end
  if result:match("^%-0%.?0*$") then
    result = result:sub(2)
  end
  return result
end

--- Moves the number at or after the cursor by `direction` times the count.
---@param direction 1|-1
function M.nudge(direction)
  local count = vim.v.count1
  if not require("gaanim.project").current(0) then
    vim.cmd(("normal! %d%s"):format(count, direction > 0 and "\1" or "\24"))
    return
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local s, e, text = M.find(line, col)
  if not s then
    return
  end
  local new = M.step(text, direction * count)
  vim.api.nvim_buf_set_text(0, row - 1, s - 1, row - 1, e, { new })
  vim.api.nvim_win_set_cursor(0, { row, s - 1 + #new - 1 })
end

return M
