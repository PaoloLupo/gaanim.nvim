---@mod gaanim.server.symbols The scene's structure as document symbols

local index = require("gaanim.index")
local inspect = require("gaanim.inspect")
local server = require("gaanim.server")

local M = {}

-- LSP SymbolKind values.
local KIND = { segment = 3, section = 2, stop = 24, marker = 14, voiceover = 24 }

--- `textDocument/documentSymbol`: segments and sections, each holding its
--- stops, markers and voiceovers, with times when `inspect` knows them.
function M.document_symbols(params, reply)
  local project, buf = server.document(params)
  if not (project and buf) then
    reply(nil)
    return
  end
  local data = not vim.bo[buf].modified and inspect.cached(project) or nil
  local times = {}
  if data then
    for line, labels in pairs(require("gaanim.server.timeline").labels(data, vim.api.nvim_buf_get_name(buf))) do
      times[line] = table.concat(labels, "  ")
    end
  end
  local count = vim.api.nvim_buf_line_count(buf)
  local symbols, parent = {}, nil
  -- A segment spans from its line to the line before the next segment.
  local function close(next_row)
    if parent then
      parent.range["end"] = { line = next_row, character = 0 }
    end
  end
  for _, symbol in ipairs(index.buffer_symbols(buf)) do
    if KIND[symbol.kind] then
      local row = symbol.lnum - 1
      local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
      local line_range = { start = { line = row, character = 0 }, ["end"] = { line = row, character = #text } }
      local item = {
        name = symbol.name or ("(" .. symbol.kind .. ")"),
        detail = times[symbol.lnum] or symbol.kind,
        kind = KIND[symbol.kind],
        range = vim.deepcopy(line_range),
        selectionRange = line_range,
        children = {},
      }
      if symbol.kind == "segment" or symbol.kind == "section" then
        close(row)
        parent = item
        table.insert(symbols, item)
      elseif parent then
        table.insert(parent.children, item)
      else
        table.insert(symbols, item)
      end
    end
  end
  if parent then
    local text = vim.api.nvim_buf_get_lines(buf, count - 1, count, false)[1] or ""
    parent.range["end"] = { line = count - 1, character = #text }
  end
  reply(symbols)
end

return M
