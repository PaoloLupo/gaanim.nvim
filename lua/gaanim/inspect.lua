---@mod gaanim.inspect The timeline with its script lines
---
--- `gaanim inspect --json` runs the scene without a window and lists every
--- segment, stop, marker, voiceover and `play` with its times and the script
--- line that made it. With it the plugin knows the instant each line of code
--- stands for, even for names built at run time. Needs a Gaanim with
--- `inspect` (see |gaanim.caps|); without it the plugin reads the Python.

local cli = require("gaanim.cli")

local M = {}

---@class gaanim.TimelineStop
---@field name? string
---@field time number
---@field file? string
---@field line? integer

---@class gaanim.TimelineSegment
---@field name string
---@field section? string
---@field start number
---@field ["end"] number
---@field file? string
---@field line? integer
---@field stops gaanim.TimelineStop[]

---@class gaanim.Timeline
---@field schema integer
---@field script string
---@field duration number
---@field segments gaanim.TimelineSegment[]
---@field sections { key: string, start: number, ["end"]: number }[]
---@field markers { name: string, time: number, file?: string, line?: integer }[]
---@field voiceovers { key: string, start: number, ["end"]: number, file?: string, line?: integer }[]
---@field plays { start: number, ["end"]: number, file?: string, line?: integer }[]

---@class gaanim.TimelinePoint
---@field kind "segment"|"stop"|"marker"|"voiceover"|"play"
---@field name? string
---@field segment? string
---@field time number The instant the line stands for
---@field file string
---@field line integer

---@type table<string, { data?: gaanim.Timeline, stale: boolean, waiting?: fun(data?: gaanim.Timeline)[] }>
M.cache = {}

--- A path in the form both sides compare.
---@param path string
---@return string
function M.key(path)
  path = vim.fs.normalize(path)
  return vim.fn.has("win32") == 1 and path:lower() or path
end

--- The timeline among the JSON objects `inspect` printed: the last one with
--- a `schema`, since the script's own prints come first.
---@param objects table[]
---@return gaanim.Timeline?
function M.parse(objects)
  for i = #objects, 1, -1 do
    if objects[i].schema and objects[i].segments then
      return objects[i]
    end
  end
end

--- The cached timeline, even if a save made it stale.
---@param project gaanim.Project
---@return gaanim.Timeline?
function M.cached(project)
  local entry = M.cache[project.root]
  return entry and entry.data
end

--- Calls `on_data` with the project's timeline, running `inspect` when the
--- cache is empty or stale. Without `inspect` support it gets nil.
---@param project gaanim.Project
---@param on_data fun(data?: gaanim.Timeline)
function M.get(project, on_data)
  if not require("gaanim.caps").get().inspect then
    on_data(nil)
    return
  end
  local entry = M.cache[project.root] or { stale = true }
  M.cache[project.root] = entry
  if entry.data and not entry.stale then
    on_data(entry.data)
    return
  end
  if entry.waiting then
    table.insert(entry.waiting, on_data)
    return
  end
  entry.waiting = { on_data }
  cli.run({ "inspect", project.target, "--json" }, {
    cwd = project.root,
    key = "inspect:" .. project.root,
    on_exit = function(_, _, objects)
      local data = M.parse(objects)
      if data then
        entry.data, entry.stale = data, false
      end
      local waiting = entry.waiting or {}
      entry.waiting = nil
      for _, callback in ipairs(waiting) do
        callback(data or entry.data)
      end
      vim.api.nvim_exec_autocmds("User", { pattern = "GaanimInspect", data = { root = project.root } })
    end,
  })
end

--- Marks a project's timeline as stale after a save.
---@param root string
function M.invalidate(root)
  if M.cache[root] then
    M.cache[root].stale = true
  end
end

--- Every line that stands for an instant, by the rules of the preview's
--- `follow`: a segment rests at its first stop (else its end), a stop and a
--- marker at their time, a voiceover at its start and a `play` at its end.
---@param data gaanim.Timeline
---@return gaanim.TimelinePoint[]
function M.points(data)
  local points = {}
  local function add(kind, name, segment, time, file, line)
    if file and line then
      table.insert(points, { kind = kind, name = name, segment = segment, time = time, file = file, line = line })
    end
  end
  for _, segment in ipairs(data.segments or {}) do
    local rest = segment.stops and segment.stops[1] and segment.stops[1].time or segment["end"]
    add("segment", segment.name, segment.name, rest, segment.file, segment.line)
    for _, stop in ipairs(segment.stops or {}) do
      add("stop", stop.name, segment.name, stop.time, stop.file, stop.line)
    end
  end
  for _, marker in ipairs(data.markers or {}) do
    add("marker", marker.name, nil, marker.time, marker.file, marker.line)
  end
  for _, voiceover in ipairs(data.voiceovers or {}) do
    add("voiceover", voiceover.key, nil, voiceover.start, voiceover.file, voiceover.line)
  end
  for _, play in ipairs(data.plays or {}) do
    add("play", nil, nil, play["end"], play.file, play.line)
  end
  return points
end

--- The instant line `line` of `file` stands for: what was made on that line,
--- else on the nearest line above it in the same file.
---@param data gaanim.Timeline
---@param file string
---@param line integer
---@return gaanim.TimelinePoint?
function M.point_at(data, file, line)
  local wanted = M.key(file)
  local best
  for _, point in ipairs(M.points(data)) do
    if point.line <= line and M.key(point.file) == wanted then
      if not best or point.line > best.line or (point.line == best.line and point.time > best.time) then
        best = point
      end
    end
  end
  return best
end

--- The segment shown at `time`.
---@param data gaanim.Timeline
---@param time number
---@return gaanim.TimelineSegment?
function M.segment_at(data, time)
  local found
  for _, segment in ipairs(data.segments or {}) do
    if segment.start <= time + 1e-6 then
      found = segment
    end
  end
  return found
end

--- Where a segment (and optionally one of its stops) was declared.
---@param data gaanim.Timeline
---@param segment? string
---@param stop? string
---@return { file: string, line: integer }?
function M.location(data, segment, stop)
  for _, candidate in ipairs(data.segments or {}) do
    if segment == nil or candidate.name == segment then
      if stop ~= nil then
        for _, s in ipairs(candidate.stops or {}) do
          if (s.name or "") == stop and s.file and s.line then
            return { file = s.file, line = s.line }
          end
        end
      elseif candidate.file and candidate.line then
        return { file = candidate.file, line = candidate.line }
      end
    end
  end
end

return M
