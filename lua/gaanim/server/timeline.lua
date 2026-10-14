---@mod gaanim.server.timeline Times as inlay hints, slides as code lenses

local config = require("gaanim.config")
local index = require("gaanim.index")
local inspect = require("gaanim.inspect")
local server = require("gaanim.server")

local M = {}

---@param seconds number
---@return string
local function clock(seconds)
  return require("gaanim.outline").clock(seconds)
end

---@param from number
---@param to number
---@return string
local function span(from, to)
  if math.abs(to - from) < 1e-6 then
    return clock(from)
  end
  return clock(from) .. "–" .. clock(to)
end

--- What `inspect` says happens on each line of a file: one label per line.
---@param data gaanim.Timeline
---@param file string
---@return table<integer, string[]>
function M.labels(data, file)
  local icons = require("gaanim.icons").get()
  local wanted = inspect.key(file)
  local lines = {}
  local function add(line, text)
    lines[line] = lines[line] or {}
    table.insert(lines[line], text)
  end
  local function here(item)
    return item.file and item.line and inspect.key(item.file) == wanted
  end
  for _, segment in ipairs(data.segments or {}) do
    if here(segment) then
      add(
        segment.line,
        ("%s %s · %.1fs"):format(icons.segment, span(segment.start, segment["end"]), segment["end"] - segment.start)
      )
    end
    for _, stop in ipairs(segment.stops or {}) do
      if here(stop) then
        add(stop.line, icons.stop .. " " .. clock(stop.time))
      end
    end
  end
  for _, marker in ipairs(data.markers or {}) do
    if here(marker) then
      add(marker.line, icons.marker .. " " .. clock(marker.time))
    end
  end
  for _, voiceover in ipairs(data.voiceovers or {}) do
    if here(voiceover) then
      add(voiceover.line, icons.voiceover .. " " .. span(voiceover.start, voiceover["end"]))
    end
  end
  -- Plays: one label per line, with how many when a loop plays several.
  local plays = {}
  for _, play in ipairs(data.plays or {}) do
    if here(play) then
      local entry = plays[play.line]
      if entry then
        entry.count = entry.count + 1
        entry.from = math.min(entry.from, play.start)
        entry.to = math.max(entry.to, play["end"])
      else
        plays[play.line] = { count = 1, from = play.start, to = play["end"] }
      end
    end
  end
  for line, entry in pairs(plays) do
    local times = entry.count > 1 and ("×%d "):format(entry.count) or ""
    add(line, icons.playing .. " " .. times .. span(entry.from, entry.to))
  end
  return lines
end

--- `textDocument/inlayHint`: the time of each line, at its end. Nothing
--- while the buffer has unsaved changes, since the times are of the file.
function M.inlay_hints(params, reply)
  local project, buf = server.document(params)
  if not (project and buf and config.get().server.hints) or vim.bo[buf].modified then
    reply(nil)
    return
  end
  local data = inspect.cached(project)
  if not data then
    reply(nil)
    return
  end
  local first = params.range and params.range.start.line or 0
  local last = params.range and params.range["end"].line or math.huge
  local hints = {}
  local file = vim.api.nvim_buf_get_name(buf)
  for line, labels in pairs(M.labels(data, file)) do
    local row = line - 1
    if row >= first and row <= last then
      local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
      if text then
        table.insert(hints, {
          position = { line = row, character = #text },
          label = table.concat(labels, "  "),
          paddingLeft = true,
        })
      end
    end
  end
  reply(hints)
end

---@param title string
---@param command? string
---@param arguments? table
---@return table
local function command(title, command_name, arguments)
  return { title = title, command = command_name or "", arguments = arguments }
end

--- `textDocument/codeLens`: over each slide, preview, still and script
--- lenses, its time and how long its script takes to say; over each
--- voiceover, whether its take is recorded.
function M.code_lenses(params, reply)
  local project, buf = server.document(params)
  if not (project and buf) then
    reply(nil)
    return
  end
  local icons = require("gaanim.icons").get()
  local uri = params.textDocument.uri
  local script = require("gaanim.script")
  local path, exists = script.path(project)
  local parsed = exists and path and script.parse(vim.fn.readfile(path)) or nil
  local data = not vim.bo[buf].modified and inspect.cached(project) or nil
  local segments = {}
  if data then
    for _, segment in ipairs(data.segments or {}) do
      segments[segment.name] = segment
    end
  end
  local lenses = {}
  local function lens(row, cmd)
    table.insert(
      lenses,
      { range = { start = { line = row, character = 0 }, ["end"] = { line = row, character = 0 } }, command = cmd }
    )
  end
  for _, symbol in ipairs(index.buffer_symbols(buf)) do
    local row = symbol.lnum - 1
    local at = { uri, symbol.lnum }
    if (symbol.kind == "segment" or symbol.kind == "section") and symbol.name then
      lens(row, command(icons.playing .. " Preview", "gaanim.preview", at))
      lens(row, command(icons.still .. " Still", "gaanim.still", at))
      local section = parsed and script.find_section(parsed, symbol.name)
      if section then
        local seconds = script.spoken(section.words)
        local text = "≈" .. script.clock(seconds)
        if symbol.target then
          text = text .. " / " .. script.clock(symbol.target)
        end
        lens(row, command(icons.voiceover .. " " .. text, "gaanim.script", at))
      else
        lens(row, command(icons.voiceover .. " Write script", "gaanim.script", at))
      end
      local segment = segments[symbol.name]
      if segment then
        lens(
          row,
          command(icons.time .. " " .. span(segment.start, segment["end"]), "gaanim.seek", { uri, symbol.name })
        )
      end
    elseif symbol.kind == "voiceover" and symbol.name then
      local recorded = script.has_take(project, symbol.name)
      lens(
        row,
        command(
          recorded and (icons.voiceover .. " take recorded") or (icons.voiceover .. " no take yet"),
          "gaanim.script",
          at
        )
      )
      lens(row, command(icons.playing .. " Preview", "gaanim.preview", at))
    end
  end
  reply(lenses)
end

return M
