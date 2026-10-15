---@mod gaanim.panel A playback panel for the preview
---
--- `:Gaanim panel` opens a floating panel, drawn with volt
--- (https://github.com/PaoloLupo/volt), that drives the project's preview:
--- play and pause, the previous and next slide, looping the slide it rests
--- on, a scrubber that seeks where you click, and the slides as a timeline of
--- blocks as long as they last, each a click away. While the preview plays,
--- the time runs on between the preview's own reports.

local cli = require("gaanim.cli")
local preview = require("gaanim.preview")

local M = {}

local XPAD = 2
local HEIGHT = 6

---@class gaanim.Panel
---@field project gaanim.Project
---@field buf integer
---@field win integer
---@field width integer Inner width of the panel's content
---@field heard? { time: number, at: number } The last playhead and when it came
---@field timer? uv.uv_timer_t
---@field augroup integer

---@type gaanim.Panel?
local current

---@param seconds number
---@return string
local function clock(seconds)
  return require("gaanim.outline").clock(math.max(0, seconds))
end

--- Whether the volt fork the panel draws with is installed.
---@return boolean
function M.available()
  local ok, ui = pcall(require, "volt.ui")
  return ok and type(ui) == "table" and ui.track ~= nil
end

--- The timeline the panel shows: the preview's playhead and duration, and
--- the segments `inspect` knows.
---@param project gaanim.Project
---@return { playhead?: gaanim.Playhead, duration: number, segments: table[] }
function M.timeline(project)
  local status = preview.status[project.root]
  local data = require("gaanim.inspect").cached(project)
  local segments = data and data.segments or {}
  local duration = status and status.duration or (data and data.duration)
  if not duration and #segments > 0 then
    duration = segments[#segments]["end"]
  end
  return { playhead = status and status.playhead, duration = duration or 0, segments = segments }
end

--- Where the preview is now: the last playhead, run on while it plays.
---@param panel { project: gaanim.Project, heard?: { time: number, at: number } }
---@param now? number Seconds, as `vim.uv.hrtime() / 1e9`
---@return number
function M.time(panel, now)
  local timeline = M.timeline(panel.project)
  local playhead = timeline.playhead
  if not playhead then
    return 0
  end
  local time = playhead.time
  if playhead.playing and panel.heard then
    time = panel.heard.time + ((now or vim.uv.hrtime() / 1e9) - panel.heard.at)
    local loop = playhead.loop
    if loop and loop[2] > loop[1] and time > loop[2] then
      time = loop[1] + (time - loop[1]) % (loop[2] - loop[1])
    end
  end
  return math.min(time, timeline.duration > 0 and timeline.duration or time)
end

--- The segment a time falls in, and its index.
---@param segments table[]
---@param time number
---@return table?, integer?
local function segment_at(segments, time)
  for i, segment in ipairs(segments) do
    if time < segment["end"] or i == #segments then
      if time >= segment.start then
        return segment, i
      end
    end
  end
end

--- Sends a command to the preview, or says why it cannot.
---@param project gaanim.Project
---@param command table
local function send(project, command)
  if not preview.send(project, command) then
    cli.notify("No preview takes commands; open one with :Gaanim preview", vim.log.levels.WARN)
  end
end

--- What the panel's controls do, by name.
---@param panel gaanim.Panel|{ project: gaanim.Project }
---@param action "toggle"|"prev"|"next"|"loop"|"back"|"forward"|"seek"|"segment"
---@param arg? any Seconds for "seek", a segment name for "segment"
function M.act(panel, action, arg)
  local project = panel.project
  local timeline = M.timeline(project)
  local playhead = timeline.playhead
  local time = M.time(panel)
  if action == "toggle" then
    send(project, { cmd = playhead and playhead.playing and "pause" or "play" })
  elseif action == "seek" then
    send(project, { cmd = "seek", time = arg })
  elseif action == "segment" then
    send(project, { cmd = "seek", segment = arg })
  elseif action == "back" or action == "forward" then
    local step = action == "back" and -1 or 1
    send(project, { cmd = "seek", time = math.max(0, math.min(timeline.duration, time + step)) })
  elseif action == "prev" or action == "next" then
    local segments = timeline.segments
    local segment, i = segment_at(segments, time)
    if not i then
      return
    end
    -- Back from inside a slide goes to its start, as players do.
    if action == "prev" and time - segment.start > 0.5 then
      i = i + 1
    end
    local target = segments[i + (action == "next" and 1 or -1)]
    if target then
      send(project, { cmd = "seek", segment = target.name })
    end
  elseif action == "loop" then
    if playhead and playhead.loop then
      send(project, { cmd = "unloop" })
    else
      local segment = segment_at(timeline.segments, time)
      if segment then
        send(project, { cmd = "loop", segment = segment.name })
      end
    end
  end
end

--- Lays the segments out as blocks in `width` cells, as long as they last,
--- one blank cell between them.
---@param segments table[]
---@param duration number
---@param width integer
---@return { segment: table, width: integer }[]
function M.blocks(segments, duration, width)
  local n = #segments
  if n == 0 or duration <= 0 then
    return {}
  end
  local room = width - (n - 1)
  local blocks, used = {}, 0
  for i, segment in ipairs(segments) do
    local cells
    if i == n then
      cells = room - used
    else
      cells = math.floor((segment["end"] - segment.start) / duration * room + 0.5)
      -- Leave a cell for each slide still to come.
      cells = math.max(1, math.min(cells, room - used - (n - i)))
    end
    used = used + cells
    table.insert(blocks, { segment = segment, width = math.max(cells, 1) })
  end
  return blocks
end

--- `text` cut or padded to `width` display cells.
---@param text string
---@param width integer
---@return string
local function fit(text, width)
  if vim.api.nvim_strwidth(text) > width then
    text = vim.fn.strcharpart(text, 0, math.max(width - 1, 0)) .. (width > 0 and "…" or "")
    while vim.api.nvim_strwidth(text) > width do
      text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 2) .. "…"
    end
  end
  return text .. string.rep(" ", width - vim.api.nvim_strwidth(text))
end

--- A line with `left` and `right` at either end of `width` cells.
local function spread(left, right, width)
  local used = 0
  for _, cell in ipairs(left) do
    used = used + vim.api.nvim_strwidth(cell[1])
  end
  for _, cell in ipairs(right) do
    used = used + vim.api.nvim_strwidth(cell[1])
  end
  local line = vim.list_extend({}, left)
  table.insert(line, { string.rep(" ", math.max(width - used, 1)) })
  return vim.list_extend(line, right)
end

--- The panel's sections, as volt draws them.
---@param panel gaanim.Panel|{ project: gaanim.Project, width: integer }
---@return { name: string, lines: fun(): table[] }[]
function M.layout(panel)
  local icons = require("gaanim.icons").get()
  local width = panel.width

  local function state()
    local timeline = M.timeline(panel.project)
    local time = M.time(panel)
    return timeline, time, segment_at(timeline.segments, time)
  end

  local function button(label, action, on)
    return {
      " " .. label .. " ",
      on and "GaanimPanelButtonOn" or "GaanimPanelButton",
      function()
        M.act(panel, action)
      end,
    }
  end

  return {
    {
      name = "status",
      lines = function()
        local timeline, time, segment = state()
        local playhead = timeline.playhead
        local icon = not playhead and icons.paused
          or playhead.loop and icons.loop
          or playhead.playing and icons.playing
          or icons.paused
        local where = segment and segment.name or ""
        if playhead and playhead.stop and playhead.stop ~= "" and segment and playhead.segment == segment.name then
          where = where .. " · " .. playhead.stop
        end
        return {
          spread({
            { icon .. " ", "GaanimPanelTime" },
            { clock(time), "GaanimPanelTime" },
            { " / " .. clock(timeline.duration), "GaanimPanelDim" },
          }, { { where, "GaanimPanelTitle" } }, width),
        }
      end,
    },
    {
      name = "scrubber",
      lines = function()
        local timeline, time = state()
        local duration = timeline.duration
        return {
          require("volt.ui").track({
            w = width,
            val = duration > 0 and time / duration or 0,
            thumb = "●",
            hlon = "GaanimPanelPlayed",
            hloff = "GaanimPanelTrack",
            hlthumb = "GaanimPanelThumb",
            on_pick = function(fraction)
              M.act(panel, "seek", math.floor(fraction * duration * 10 + 0.5) / 10)
            end,
          }),
        }
      end,
    },
    {
      name = "segments",
      lines = function()
        local timeline, _, segment = state()
        local blocks = M.blocks(timeline.segments, timeline.duration, width)
        if #blocks == 0 then
          return { { { fit("No timeline yet: save the scene or open the preview", width), "GaanimPanelDim" } } }
        end
        local line = {}
        for i, block in ipairs(blocks) do
          local name = block.segment.name
          table.insert(line, {
            fit(block.width > 2 and (" " .. name) or "", block.width),
            block.segment == segment and "GaanimPanelSegmentOn" or "GaanimPanelSegment",
            function()
              M.act(panel, "segment", name)
            end,
          })
          if i < #blocks then
            table.insert(line, { " " })
          end
        end
        return { line }
      end,
    },
    {
      name = "ticks",
      lines = function()
        local timeline = state()
        return { spread({ { clock(0), "GaanimPanelDim" } }, { { clock(timeline.duration), "GaanimPanelDim" } }, width) }
      end,
    },
    {
      name = "blank",
      lines = function()
        return { {} }
      end,
    },
    {
      name = "controls",
      lines = function()
        local timeline = state()
        local playhead = timeline.playhead
        local playing = playhead and playhead.playing
        local looping = playhead and playhead.loop ~= nil
        return {
          spread({
            button(icons.previous, "prev"),
            { " " },
            button(playing and (icons.paused .. " Pause") or (icons.playing .. " Play"), "toggle", playing),
            { " " },
            button(icons.next, "next"),
            { "  " },
            button(looping and (icons.unloop .. " Unloop") or (icons.loop .. " Loop"), "loop", looping),
          }, {
            { "␣ play  h l ±1s  [ ] slide  L loop  q close", "GaanimPanelDim" },
          }, width),
        }
      end,
    },
  }
end

--- Draws the panel again, if it is open.
function M.redraw()
  if current and vim.api.nvim_buf_is_valid(current.buf) then
    require("volt").redraw(current.buf, "all")
  end
end

local function stop_timer(panel)
  if panel.timer then
    panel.timer:stop()
    panel.timer:close()
    panel.timer = nil
  end
end

--- Keeps the time running while the preview plays.
local function tick(panel)
  local playhead = M.timeline(panel.project).playhead
  if playhead and playhead.playing then
    if not panel.timer then
      panel.timer = vim.uv.new_timer()
      panel.timer:start(100, 100, vim.schedule_wrap(M.redraw))
    end
  else
    stop_timer(panel)
  end
end

--- Closes the panel.
function M.close()
  local panel = current
  if not panel then
    return
  end
  current = nil
  stop_timer(panel)
  pcall(vim.api.nvim_del_augroup_by_id, panel.augroup)
  if vim.api.nvim_win_is_valid(panel.win) then
    vim.api.nvim_win_close(panel.win, true)
  end
  if vim.api.nvim_buf_is_valid(panel.buf) then
    vim.api.nvim_buf_delete(panel.buf, { force = true })
  end
end

--- Whether the panel is open.
---@return boolean
function M.is_open()
  return current ~= nil
end

--- Opens the panel for the current project, or closes it when it is open.
function M.toggle()
  if current then
    M.close()
    return
  end
  if not M.available() then
    cli.notify(
      "The panel needs volt with ui.track: install PaoloLupo/volt (a fork of nvzone/volt)",
      vim.log.levels.WARN
    )
    return
  end
  local project = require("gaanim.project").require()
  if not project then
    return
  end
  M.open(project)
end

--- Opens the panel for a project.
---@param project gaanim.Project
function M.open(project)
  local volt = require("volt")
  local columns = vim.o.columns
  local outer = math.max(math.min(columns - 4, 96), 40)
  local width = outer - 2 * XPAD
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = outer,
    height = HEIGHT,
    row = math.max(vim.o.lines - HEIGHT - 5, 0),
    col = math.floor((columns - outer) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. project.name .. " ",
    title_pos = "center",
  })
  vim.wo[win].winhighlight = "Normal:GaanimPanel,FloatBorder:GaanimPanelBorder,FloatTitle:GaanimPanelTitle"

  ---@type gaanim.Panel
  local panel = {
    project = project,
    buf = buf,
    win = win,
    width = width,
    augroup = vim.api.nvim_create_augroup("gaanim.panel", { clear = true }),
  }
  current = panel
  local playhead = M.timeline(project).playhead
  if playhead then
    panel.heard = { time = playhead.time, at = vim.uv.hrtime() / 1e9 }
  end

  volt.gen_data({
    { buf = buf, layout = M.layout(panel), xpad = XPAD, ns = vim.api.nvim_create_namespace("gaanim.panel") },
  })
  volt.run(buf, { h = HEIGHT, w = outer })
  require("volt.events").add(buf)

  local function map(lhs, action, desc)
    vim.keymap.set("n", lhs, function()
      M.act(panel, action)
    end, { buffer = buf, nowait = true, desc = "Gaanim panel: " .. desc })
  end
  map("<Space>", "toggle", "play or pause")
  map("h", "back", "back a second")
  map("l", "forward", "forward a second")
  map("[", "prev", "previous slide")
  map("]", "next", "next slide")
  map("L", "loop", "loop the slide (toggle)")
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, M.close, { buffer = buf, nowait = true, desc = "Gaanim panel: close" })
  end

  vim.api.nvim_create_autocmd("User", {
    group = panel.augroup,
    pattern = { "GaanimPlayhead", "GaanimPreview" },
    callback = function(args)
      if not (args.data and args.data.root == project.root) then
        return
      end
      if args.match == "GaanimPlayhead" and args.data.playhead then
        panel.heard = { time = args.data.playhead.time, at = vim.uv.hrtime() / 1e9 }
      end
      tick(panel)
      M.redraw()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = panel.augroup,
    pattern = tostring(win),
    callback = function()
      vim.schedule(M.close)
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = panel.augroup,
    callback = function()
      M.close()
      M.open(project)
    end,
  })
  tick(panel)
end

return M
