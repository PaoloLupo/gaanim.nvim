---@mod gaanim.outline Navigating segments, sections, stops and markers

local index = require("gaanim.index")
local project_mod = require("gaanim.project")
local ui = require("gaanim.ui")

local M = {}

M.icons = {
  section = { "§", "Title" },
  segment = { "▤", "Function" },
  voiceover = { "♪", "String" },
  stop = { "⏸", "Comment" },
  marker = { "◆", "Constant" },
}

---@param symbol gaanim.Symbol
---@param root string
---@return gaanim.PickItem
local function item(symbol, root)
  local icon = M.icons[symbol.kind]
  local name = symbol.name or "(unnamed)"
  local hint = vim.fs.relpath and vim.fs.relpath(root, symbol.file) or vim.fn.fnamemodify(symbol.file, ":t")
  hint = (hint or symbol.file) .. ":" .. symbol.lnum
  if symbol.title then
    name = name .. " · " .. symbol.title
  end
  if symbol.target then
    hint = ("%s  target %s"):format(hint, require("gaanim.script").clock(symbol.target))
  end
  local indent = (symbol.kind == "stop" or symbol.kind == "marker") and "  " or ""
  return {
    text = indent .. name,
    hint = hint,
    icon = icon[1],
    hl = icon[2],
    file = symbol.file,
    lnum = symbol.lnum,
    col = symbol.col,
    value = symbol,
  }
end

--- Lists the project's structure and jumps to the picked item.
---@param kinds? table<string, boolean> Only these kinds
function M.pick(kinds)
  local project = project_mod.require()
  if not project then
    return
  end
  kinds = kinds or index.structure
  local items = {}
  for _, symbol in ipairs(index.project_symbols(project)) do
    if kinds[symbol.kind] and M.icons[symbol.kind] then
      table.insert(items, item(symbol, project.root))
    end
  end
  ui.pick(items, {
    title = "Gaanim · " .. project.name,
    on_choice = function(choice)
      ui.jump(choice.file, choice.lnum, choice.col)
    end,
  })
end

--- Moves the cursor to the next or previous segment (or stop) in the buffer.
---@param direction 1|-1
---@param kinds? table<string, boolean>
function M.move(direction, kinds)
  kinds = kinds or { segment = true, section = true, voiceover = true }
  local symbols = index.buffer_symbols(0)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local count = vim.v.count1
  local target
  local first, last, step = 1, #symbols, 1
  if direction < 0 then
    first, last, step = #symbols, 1, -1
  end
  for i = first, last, step do
    local symbol = symbols[i]
    if kinds[symbol.kind] and ((direction > 0 and symbol.lnum > lnum) or (direction < 0 and symbol.lnum < lnum)) then
      target = symbol
      count = count - 1
      if count == 0 then
        break
      end
    end
  end
  if target then
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { target.lnum, target.col - 1 })
  end
end

return M
