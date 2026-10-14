---@mod gaanim.server.actions Code actions on a scene's lines

local index = require("gaanim.index")
local server = require("gaanim.server")

local M = {}

---@param title string
---@param kind string
---@param command string
---@param arguments table
---@return lsp.CodeAction
local function action(title, kind, command, arguments)
  return { title = title, kind = kind, command = { title = title, command = command, arguments = arguments } }
end

--- `textDocument/codeAction`: write a slide's missing script, name an
--- unnamed stop, add a marker, and preview or export the line or its slide.
function M.code_actions(params, reply)
  local project, buf = server.document(params)
  if not (project and buf) then
    reply(nil)
    return
  end
  local uri = params.textDocument.uri
  local line = params.range.start.line + 1
  local at = { uri, line }
  local actions = {}
  local script = require("gaanim.script")
  local path, exists = script.path(project)
  local parsed = exists and path and script.parse(vim.fn.readfile(path)) or { sections = {} }
  for _, symbol in ipairs(index.buffer_symbols(buf)) do
    if symbol.lnum == line then
      if (symbol.kind == "segment" or symbol.kind == "voiceover") and symbol.name then
        if not script.find_section(parsed, symbol.name) then
          local what = symbol.kind == "segment" and "script" or "text"
          table.insert(
            actions,
            action(("Write the %s of “%s”"):format(what, symbol.name), "quickfix", "gaanim.script", at)
          )
        else
          table.insert(
            actions,
            action(("Open the script of “%s”"):format(symbol.name), "source", "gaanim.script", at)
          )
        end
      elseif symbol.kind == "stop" and not symbol.name then
        table.insert(actions, action("Name this stop", "quickfix", "gaanim.nameStop", at))
      end
    end
  end
  for _, diagnostic in ipairs(params.context and params.context.diagnostics or {}) do
    if (diagnostic.message or ""):find("no speaker notes", 1, true) then
      table.insert(actions, action("Write the speaker notes in the script", "quickfix", "gaanim.script", at))
      break
    end
  end
  vim.list_extend(actions, {
    action("Preview this line", "source", "gaanim.preview", at),
    action("Export the frame of this line", "source", "gaanim.still", at),
    action("Export this slide as a draft MP4", "source", "gaanim.exportSlide", at),
    action("Add a marker below", "source", "gaanim.addMarker", at),
  })
  reply(actions)
end

return M
