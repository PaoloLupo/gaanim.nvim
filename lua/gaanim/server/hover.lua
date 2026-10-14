---@mod gaanim.server.hover What a line does on the timeline, and what a file is

local inspect = require("gaanim.inspect")
local server = require("gaanim.server")

local M = {}

---@param seconds number
---@return string
local function clock(seconds)
  return require("gaanim.outline").clock(seconds)
end

--- Markdown lines about what line `line` of `file` makes on the timeline.
---@param data gaanim.Timeline
---@param file string
---@param line integer
---@return string[]
function M.timeline_lines(data, file, line)
  local icons = require("gaanim.icons").get()
  local wanted = inspect.key(file)
  local function here(item)
    return item.file and item.line == line and inspect.key(item.file) == wanted
  end
  local out = {}
  for _, segment in ipairs(data.segments or {}) do
    if here(segment) then
      table.insert(
        out,
        ("%s segment **%s** · %s–%s · %.1f s · %d stops"):format(
          icons.segment,
          segment.name,
          clock(segment.start),
          clock(segment["end"]),
          segment["end"] - segment.start,
          #(segment.stops or {})
        )
      )
    end
    for i, stop in ipairs(segment.stops or {}) do
      if here(stop) then
        local name = (stop.name and stop.name ~= "") and ("`" .. stop.name .. "`") or "(unnamed)"
        table.insert(
          out,
          ("%s stop %s · %s · %d of %d in **%s**"):format(
            icons.stop,
            name,
            clock(stop.time),
            i,
            #segment.stops,
            segment.name
          )
        )
      end
    end
  end
  for _, marker in ipairs(data.markers or {}) do
    if here(marker) then
      table.insert(out, ("%s marker `%s` · %s"):format(icons.marker, marker.name, clock(marker.time)))
    end
  end
  for _, voiceover in ipairs(data.voiceovers or {}) do
    if here(voiceover) then
      table.insert(
        out,
        ("%s voiceover `%s` · %s–%s · %.1f s"):format(
          icons.voiceover,
          voiceover.key,
          clock(voiceover.start),
          clock(voiceover["end"]),
          voiceover["end"] - voiceover.start
        )
      )
    end
  end
  local plays = {}
  for _, play in ipairs(data.plays or {}) do
    if here(play) then
      table.insert(plays, play)
    end
  end
  if #plays > 0 then
    local shown = {}
    for i = 1, math.min(#plays, 6) do
      table.insert(shown, ("%s–%s"):format(clock(plays[i].start), clock(plays[i]["end"])))
    end
    local more = #plays > 6 and (" … %d more"):format(#plays - 6) or ""
    table.insert(
      out,
      ("%s play%s · %s%s"):format(
        icons.playing,
        #plays > 1 and ("s ×" .. #plays) or "",
        table.concat(shown, ", "),
        more
      )
    )
  end
  return out
end

--- `textDocument/hover`: the timeline entries of the line, and for a file
--- name in an asset call, the file. Nothing otherwise, so the Python
--- server's documentation stands alone.
function M.hover(params, reply)
  local project, buf = server.document(params)
  if not (project and buf) then
    reply(nil)
    return
  end
  local line = params.position.line + 1
  local col = params.position.character
  local parts = {}
  local data = not vim.bo[buf].modified and inspect.cached(project) or nil
  if data then
    local lines = M.timeline_lines(data, vim.api.nvim_buf_get_name(buf), line)
    if #lines > 0 then
      table.insert(parts, "**Timeline**\n\n" .. table.concat(lines, "  \n"))
    end
  end
  local assets = require("gaanim.server.assets")
  local ref
  for _, candidate in ipairs(assets.references(buf)) do
    if candidate.lnum == line and col >= candidate.first and col <= candidate.last then
      ref = candidate
      break
    end
  end
  local function done()
    if #parts == 0 then
      reply(nil)
    else
      reply({ contents = { kind = "markdown", value = table.concat(parts, "\n\n---\n\n") } })
    end
  end
  if not ref then
    done()
    return
  end
  local path = assets.resolve(project, ref.name)
  if not path then
    table.insert(parts, ("**Asset** `%s` not found"):format(ref.name))
    done()
    return
  end
  assets.describe(path, function(text)
    table.insert(parts, "**Asset**\n\n" .. text)
    done()
  end)
end

return M
