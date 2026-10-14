---@mod gaanim.outline Navigating segments, sections, stops and markers

local index = require("gaanim.index")
local project_mod = require("gaanim.project")
local ui = require("gaanim.ui")

local M = {}

local HL = { section = "Title", segment = "Function", voiceover = "String", stop = "Comment", marker = "Constant" }

--- The icon and highlight of a kind of symbol.
---@param kind string
---@return string icon, string hl
function M.icon(kind)
  return require("gaanim.icons").get()[kind], HL[kind]
end

---@param symbol gaanim.Symbol
---@param root string
---@return gaanim.PickItem
local function item(symbol, root)
  local icon, hl = M.icon(symbol.kind)
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
    icon = icon,
    hl = hl,
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
    if kinds[symbol.kind] and HL[symbol.kind] then
      table.insert(items, item(symbol, project.root))
    end
  end
  ui.pick(items, {
    title = "Gaanim · " .. project.name,
    on_choice = function(choice)
      ui.jump(choice.file, choice.lnum, choice.col)
      -- A preview that takes commands goes there too.
      local symbol = choice.value
      if symbol.kind == "stop" and symbol.name then
        require("gaanim.preview").send(project, { cmd = "seek", stop = symbol.name })
      elseif (symbol.kind == "segment" or symbol.kind == "section") and symbol.name then
        require("gaanim.preview").send(project, { cmd = "seek", segment = symbol.name })
      end
    end,
  })
end

--- Seconds as `m:ss.s`.
---@param seconds number
---@return string
function M.clock(seconds)
  local minutes = math.floor(seconds / 60)
  return ("%d:%04.1f"):format(minutes, seconds - minutes * 60)
end

---@param root string
---@param file? string
---@param line? integer
---@return string
local function where(root, file, line)
  if not (file and line) then
    return ""
  end
  local relative = vim.fs.relpath and vim.fs.relpath(root, vim.fs.normalize(file)) or vim.fn.fnamemodify(file, ":t")
  return ("%s:%d"):format(relative or file, line)
end

--- Items for the timeline `gaanim inspect` reports, in time order.
---@param project gaanim.Project
---@param data gaanim.Timeline
---@return gaanim.PickItem[]
function M.timeline_items(project, data)
  -- Each segment with its stops, in timeline order; markers and voiceovers
  -- go after the last of those at or before their time.
  local base, extra = {}, {}
  for _, segment in ipairs(data.segments or {}) do
    local label = segment.section and (segment.section .. " · " .. segment.name) or segment.name
    table.insert(base, {
      time = segment.start,
      item = {
        text = label,
        hint = ("%s–%s  %s"):format(
          M.clock(segment.start),
          M.clock(segment["end"]),
          where(project.root, segment.file, segment.line)
        ),
        icon = M.icon(segment.section and "section" or "segment"),
        hl = HL.segment,
        file = segment.file and vim.fs.normalize(segment.file),
        lnum = segment.line,
        value = { cmd = "seek", segment = segment.name },
      },
    })
    for _, stop in ipairs(segment.stops or {}) do
      table.insert(base, {
        time = stop.time,
        item = {
          text = "  " .. ((stop.name and stop.name ~= "") and stop.name or "(stop)"),
          hint = ("%s  %s"):format(M.clock(stop.time), where(project.root, stop.file, stop.line)),
          icon = M.icon("stop"),
          hl = HL.stop,
          file = stop.file and vim.fs.normalize(stop.file),
          lnum = stop.line,
          value = { cmd = "seek", time = stop.time },
        },
      })
    end
  end
  for _, marker in ipairs(data.markers or {}) do
    table.insert(extra, {
      time = marker.time,
      item = {
        text = "  " .. marker.name,
        hint = ("%s  %s"):format(M.clock(marker.time), where(project.root, marker.file, marker.line)),
        icon = M.icon("marker"),
        hl = HL.marker,
        file = marker.file and vim.fs.normalize(marker.file),
        lnum = marker.line,
        value = { cmd = "seek", time = marker.time },
      },
    })
  end
  for _, voiceover in ipairs(data.voiceovers or {}) do
    table.insert(extra, {
      time = voiceover.start,
      item = {
        text = "  " .. voiceover.key,
        hint = ("%s–%s  %s"):format(
          M.clock(voiceover.start),
          M.clock(voiceover["end"]),
          where(project.root, voiceover.file, voiceover.line)
        ),
        icon = M.icon("voiceover"),
        hl = HL.voiceover,
        file = voiceover.file and vim.fs.normalize(voiceover.file),
        lnum = voiceover.line,
        value = { cmd = "seek", time = voiceover.start },
      },
    })
  end
  table.sort(extra, function(a, b)
    return a.time < b.time
  end)
  for _, entry in ipairs(extra) do
    local at = 0
    for i, known in ipairs(base) do
      if known.time <= entry.time + 1e-9 then
        at = i
      end
    end
    table.insert(base, at + 1, entry)
  end
  return vim.tbl_map(function(entry)
    return entry.item
  end, base)
end

--- The timeline `gaanim inspect` reports, with times: picking an entry
--- jumps to its line and moves a preview that takes commands there.
function M.timeline()
  local project = project_mod.require()
  if not project then
    return
  end
  if not require("gaanim.caps").get().inspect then
    vim.notify("The timeline needs a Gaanim with `inspect`; showing the outline", vim.log.levels.WARN, {
      title = "Gaanim",
    })
    M.pick()
    return
  end
  require("gaanim.inspect").get(project, function(data)
    if not data then
      vim.notify("gaanim inspect failed; see :Gaanim log", vim.log.levels.ERROR, { title = "Gaanim" })
      return
    end
    ui.pick(M.timeline_items(project, data), {
      title = ("Timeline · %s · %s"):format(project.name, M.clock(data.duration or 0)),
      on_choice = function(choice)
        if choice.file and choice.lnum then
          ui.jump(choice.file, choice.lnum)
        end
        require("gaanim.preview").send(project, choice.value)
      end,
    })
  end)
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
