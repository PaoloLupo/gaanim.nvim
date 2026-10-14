---@mod gaanim.typst.blink Typst math completion as a blink.cmp source
---
--- Add it to blink.cmp:
--- >lua
---   sources = {
---     default = { "lsp", "path", "snippets", "buffer", "gaanim_typst" },
---     providers = {
---       gaanim_typst = { name = "Typst", module = "gaanim.typst.blink", score_offset = 20 },
---     },
---   }
--- <
--- Each symbol shows the character it draws as its icon.

local typst = require("gaanim.typst")

local source = {}

function source.new(opts)
  return setmetatable({ opts = opts or {} }, { __index = source })
end

function source:enabled()
  return typst.enabled(0)
end

function source:get_trigger_characters()
  return { "." }
end

function source:get_completions(ctx, callback)
  local items = typst.items_at(ctx.bufnr, ctx.cursor) or {}
  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

return source
