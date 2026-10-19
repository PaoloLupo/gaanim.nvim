---@mod gaanim.server.completion Typst math and asset paths

local config = require("gaanim.config")
local server = require("gaanim.server")

local M = {}

local FILE, FOLDER = 17, 19

--- `textDocument/completion`: Typst math inside `equation(...)` strings and
--- `$...$`, and file names inside the strings of asset calls.
function M.complete(params, reply)
  local project, buf = server.document(params)
  if not (project and buf) then
    reply(nil)
    return
  end
  local row, col = params.position.line + 1, params.position.character
  local ctx = require("gaanim.typst.context").at(buf, row, col)
  if not ctx then
    reply(nil)
    return
  end
  if ctx.math then
    if not config.get().server.typst then
      reply(nil)
      return
    end
    reply({ isIncomplete = false, items = require("gaanim.typst").items(ctx.prefix) })
    return
  end
  local assets = require("gaanim.server.assets")
  local extensions = ctx.call and assets.calls[ctx.call]
  if extensions == nil or ctx.keyword or ctx.content:find("\n", 1, true) then
    reply(nil)
    return
  end
  -- Replace everything typed in the string so far with the whole name.
  local range = {
    start = { line = row - 1, character = col - #ctx.content },
    ["end"] = { line = row - 1, character = col },
  }
  local items = {}
  for _, file in ipairs(assets.files(project, extensions)) do
    table.insert(items, {
      label = file.name,
      kind = FILE,
      filterText = file.name,
      textEdit = { range = range, newText = file.name },
      labelDetails = { description = assets.size(file.size) .. (file.shared and " · shared" or "") },
      documentation = { kind = "markdown", value = ("`%s`"):format(vim.fn.fnamemodify(file.path, ":~:.")) },
    })
  end
  if #items == 0 then
    table.insert(items, {
      label = "(no matching files in " .. assets.where(project) .. ")",
      kind = FOLDER,
      textEdit = { range = range, newText = ctx.content },
    })
  end
  reply({ isIncomplete = false, items = items })
end

return M
