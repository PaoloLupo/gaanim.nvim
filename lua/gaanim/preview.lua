---@mod gaanim.preview Live preview and presenting
---
--- With a Gaanim that has `--listen`, the preview runs with `--listen stdio`:
--- the plugin moves it to the line under the cursor without restarting it,
--- can keep it following the cursor, and hears where it rests (`playhead`),
--- which it marks in the code and in the narration script. Older versions
--- restart the preview with `--from`.

local caps = require("gaanim.caps")
local cli = require("gaanim.cli")
local config = require("gaanim.config")
local index = require("gaanim.index")
local project_mod = require("gaanim.project")

local M = {}

M.ns = vim.api.nvim_create_namespace("gaanim.playhead")
M.animating_ns = vim.api.nvim_create_namespace("gaanim.animating")

---@class gaanim.LaunchOpts
---@field present? boolean
---@field from? string Segment or Section key to start at
---@field sections? string[] Only these segments or Section keys
---@field follow? { file: string, line: integer } Rest at the instant of this line once ready
---@field queue? table[] Commands to send once ready
---@field duration? string
---@field monitor? integer
---@field args? string[]

---@class gaanim.Playhead
---@field time number
---@field segment? string
---@field stop? string `""` at an unnamed stop, nil before the first stop
---@field playing boolean
---@field loop? number[] `{ start, end }` while the preview loops a range

---@class gaanim.PreviewStatus
---@field state "starting"|"reloading"|"ready"|"failed"
---@field detail? string
---@field key string Process key
---@field listen boolean The preview takes commands
---@field present boolean
---@field duration? number
---@field playhead? gaanim.Playhead
---@field queue table[] Commands waiting for the scene to be ready
---@field sends_timeline? boolean Its `ready` events carry the timeline
---@field loop_signature? string The loop range last seen, to spot changes

---@type table<string, gaanim.PreviewStatus>
M.status = {}

---@type table<string, boolean> Projects whose preview follows the cursor
M.following = {}

---@type table<string, string> Arguments of each running process, to spot changes
local launched = {}

---@param name string
---@return string
local function escape_commas(name)
  return (name:gsub(",", "\\,"))
end

---@param project gaanim.Project
local function changed(project)
  vim.api.nvim_exec_autocmds("User", { pattern = "GaanimPreview", data = { root = project.root } })
end

--- The slide name under the cursor, or nil with a message.
---@return string?
function M.slide_at_cursor()
  local here = index.at_cursor(0)
  if not (here.segment and here.segment.name) then
    cli.notify("No segment above the cursor in this file", vim.log.levels.WARN)
    return nil
  end
  return here.segment.name
end

--- The file and line under the cursor.
---@return { file: string, line: integer }
local function cursor_line()
  return {
    file = vim.fs.normalize(vim.api.nvim_buf_get_name(0)),
    line = vim.api.nvim_win_get_cursor(0)[1],
  }
end

--- Sends a command to the project's preview, or queues it until the scene
--- is ready. False when no preview of this project takes commands.
---@param project gaanim.Project
---@param command table
---@return boolean
function M.send(project, command)
  local status = M.status[project.root]
  if not (status and status.listen and cli.running(status.key)) then
    return false
  end
  if status.state == "ready" or status.state == "failed" then
    return cli.send(status.key, command)
  end
  table.insert(status.queue, command)
  return true
end

--- Where the code says the preview rests: the stop's line, else its
--- segment's, from `gaanim inspect` when known, else from the Python.
---@param project gaanim.Project
---@param playhead gaanim.Playhead
---@return { file: string, line: integer }?
local function playhead_location(project, playhead)
  local data = require("gaanim.inspect").cached(project)
  if data then
    local stop = playhead.stop ~= nil and playhead.stop ~= "" and playhead.stop or nil
    local found = (stop and require("gaanim.inspect").location(data, playhead.segment, stop))
      or require("gaanim.inspect").location(data, playhead.segment)
    if found then
      return found
    end
  end
  if playhead.stop and playhead.stop ~= "" then
    for _, symbol in ipairs(index.project_symbols(project)) do
      if symbol.kind == "stop" and symbol.name == playhead.stop then
        return { file = symbol.file, line = symbol.lnum }
      end
    end
  end
  local symbol = playhead.segment and index.find(project, playhead.segment)
  return symbol and { file = symbol.file, line = symbol.lnum } or nil
end

---@type table<integer, boolean>
local marked = {}

---@type table<integer, boolean>
local animating = {}

--- While the preview plays, highlights the lines whose `play` is animating
--- at the playhead (from `gaanim inspect`); clears them when it pauses.
---@param project gaanim.Project
---@param playhead gaanim.Playhead
function M.mark_animating(project, playhead)
  for buf in pairs(animating) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, M.animating_ns, 0, -1)
    end
  end
  animating = {}
  if not (playhead.playing and config.get().preview.animating) then
    return
  end
  local inspect = require("gaanim.inspect")
  local data = inspect.cached(project)
  if not data then
    if caps.get().inspect then
      inspect.get(project, function() end)
    end
    return
  end
  local time = playhead.time
  for _, play in ipairs(data.plays or {}) do
    if play.file and play.line and play.start <= time + 1e-6 and time < play["end"] then
      local buf = vim.fn.bufnr(vim.fs.normalize(play.file))
      if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and not vim.bo[buf].modified then
        local row = math.min(play.line, vim.api.nvim_buf_line_count(buf)) - 1
        vim.api.nvim_buf_set_extmark(buf, M.animating_ns, row, 0, {
          line_hl_group = "GaanimPlaying",
          sign_text = require("gaanim.icons").get()[playhead.loop and "loop" or "playing"],
          sign_hl_group = "GaanimPlayhead",
          priority = 15,
        })
        animating[buf] = true
      end
    end
  end
end

--- Marks the line the preview rests at, and moves the script window to the
--- slide being shown.
---@param project gaanim.Project
---@param playhead gaanim.Playhead
function M.on_playhead(project, playhead)
  for buf in pairs(marked) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    end
  end
  marked = {}
  if config.get().preview.marker then
    local where = playhead_location(project, playhead)
    local buf = where and vim.fn.bufnr(where.file)
    if buf and buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      local line = math.min(where.line, vim.api.nvim_buf_line_count(buf)) - 1
      vim.api.nvim_buf_set_extmark(buf, M.ns, line, 0, {
        sign_text = require("gaanim.icons").get()[playhead.loop and "loop" or (playhead.playing and "playing" or "paused")],
        sign_hl_group = "GaanimPlayhead",
        virt_text = {
          {
            ("  ◀ %s %s"):format(
              playhead.loop and "loop" or "preview",
              require("gaanim.script").clock(playhead.time)
            ),
            "GaanimPlayheadText",
          },
        },
        priority = 20,
      })
      marked[buf] = true
    end
  end
  M.mark_animating(project, playhead)
  if package.loaded["gaanim.script"] and playhead.segment then
    require("gaanim.script").show_slide(project, playhead.segment, playhead.stop)
  end
  vim.api.nvim_exec_autocmds(
    "User",
    { pattern = "GaanimPlayhead", data = { root = project.root, playhead = playhead } }
  )
end

---@param opts? gaanim.LaunchOpts
function M.launch(opts)
  opts = opts or {}
  local project = project_mod.require()
  if not project then
    return
  end
  local cfg = config.get()
  local can = caps.get()
  local listen = cfg.preview.listen and can.listen
  local args = {}
  if opts.present then
    table.insert(args, "--present")
    local duration = opts.duration or cfg.present.duration
    if duration then
      vim.list_extend(args, { "--duration", duration })
    end
    local monitor = opts.monitor or cfg.present.monitor
    if monitor then
      vim.list_extend(args, { "--monitor", tostring(monitor) })
    end
  end
  vim.list_extend(args, cfg.preview.args)
  if opts.from then
    vim.list_extend(args, { "--from", opts.from })
  end
  if opts.sections and #opts.sections > 0 then
    vim.list_extend(args, { "--sections", table.concat(vim.tbl_map(escape_commas, opts.sections), ",") })
  end
  vim.list_extend(args, opts.args or {})
  if listen then
    vim.list_extend(args, { "--listen", "stdio" })
  end
  if can.json then
    vim.list_extend(args, { "--message-format", "json" })
  end
  table.insert(args, project.target)

  local key = (opts.present and "present:" or "preview:") .. project.root
  local signature = table.concat(args, "\0")
  local follow = opts.follow and { cmd = "follow", file = opts.follow.file, line = opts.follow.line }
  if cli.running(key) then
    if launched[key] == signature then
      if follow and M.send(project, follow) then
        return
      end
      cli.notify(opts.present and "Already presenting" or "Preview already open; it reloads when you save")
      return
    end
    cli.stop(key)
  end
  launched[key] = signature
  local title = opts.present and "Presenting " or "Previewing "
  local scope = opts.from and (" from " .. opts.from)
    or (opts.sections and (" " .. table.concat(opts.sections, ", ")))
    or (follow and (" at line " .. follow.line))
    or ""
  cli.notify(title .. project.name .. scope)

  ---@type gaanim.PreviewStatus
  local status = { state = "starting", key = key, listen = listen, present = opts.present == true, queue = {} }
  if follow then
    table.insert(status.queue, follow)
  end
  vim.list_extend(status.queue, opts.queue or {})
  M.status[project.root] = status
  local pending = {} -- Lines since the last reload: a traceback, prints
  local function set(state, detail)
    status.state, status.detail = state, detail
    changed(project)
  end
  local function ready(detail)
    pending = {}
    set("ready", detail)
    for _, command in ipairs(status.queue) do
      cli.send(key, command)
    end
    status.queue = {}
    local check = require("gaanim.check")
    if check.last[project.root] and check.last[project.root].status == "error" then
      check.run({ project = project, quiet = true })
    end
  end
  local function failed(message, file, line)
    local report = {
      status = "error",
      summary = message,
      items = { { filename = file or project.entry, lnum = line or 1, col = 1, type = "E", text = message } },
    }
    if not file then
      report = require("gaanim.check").parse(project, vim.list_extend({ "  ✗ python    " .. message }, pending))
    end
    require("gaanim.check").publish(project, report)
    pending = {}
    set("failed", report.summary)
    local live = package.loaded["gaanim.live"] and require("gaanim.live").active(project.root)
    if not (live and cfg.live.quiet) then
      cli.notify("✗ " .. report.summary, vim.log.levels.ERROR)
    end
  end

  ---@type vim.SystemObj?
  local job
  job = cli.run(args, {
    cwd = project.root,
    key = key,
    stdin = listen,
    env = cfg.preview.editor and { GAANIM_EDITOR = require("gaanim.remote").editor_command() } or nil,
    on_json = function(object)
      local event, kind = object.event, object.type
      if event == "reload" or (kind == "reload" and object.phase == "start") then
        pending = {}
        set("reloading", object.cause)
      elseif event == "ready" then
        status.duration = object.duration
        -- Newer Gaanim sends the scene's timeline with each `ready`, the
        -- same object `gaanim inspect --json` prints: no second run needed.
        if type(object.timeline) == "table" and object.timeline.segments then
          status.sends_timeline = true
          require("gaanim.inspect").store(project, object.timeline)
          if package.loaded["gaanim.server"] then
            require("gaanim.server").refresh(project.root)
          end
        end
        ready(status.duration and ("%.1f s"):format(status.duration) or nil)
      elseif kind == "reload" and object.phase == "end" and not listen then
        ready(object.seconds and ("reloaded in %.2f s"):format(object.seconds) or nil)
      elseif event == "failed" then
        failed(object.message or "Script failed", object.file, object.line)
      elseif kind == "message" and object.level == "error" and object.label == "python" and not listen then
        failed(object.message or "Script failed", object.file, object.line)
      elseif event == "playhead" then
        status.playhead = {
          time = object.time or 0,
          segment = object.segment,
          stop = object.stop,
          playing = object.playing == true,
          loop = type(object.loop) == "table" and object.loop or nil,
        }
        -- Entering, leaving or moving a loop changes the slides' lenses.
        local loop = status.playhead.loop
        local signature = loop and (loop[1] .. ":" .. loop[2]) or nil
        if signature ~= status.loop_signature then
          status.loop_signature = signature
          if package.loaded["gaanim.server"] then
            require("gaanim.server").refresh(project.root)
          end
        end
        M.on_playhead(project, status.playhead)
        changed(project)
      elseif event == "error" then
        local message = object.message or "The preview could not do that"
        if message:find("unknown variant `loop`", 1, true) or message:find("unknown variant `unloop`", 1, true) then
          message = "Looping from Neovim needs a newer Gaanim (`gaanim update`); press L in the preview meanwhile"
        end
        cli.notify(message, vim.log.levels.WARN)
      end
    end,
    on_line = function(line)
      if can.json then
        table.insert(pending, line)
        return
      end
      -- Older versions: read the status lines meant for people.
      local label, text = line:match("^%s%s%S+%s+(%S+)%s*(.*)$")
      if label == "reload" or label == "watch" then
        pending = {}
        set(label == "reload" and "reloading" or "starting", text)
      elseif label == "ready" then
        ready(text)
      elseif label == "python" and line:find("✗", 1, true) then
        failed(text)
      else
        table.insert(pending, line)
      end
    end,
    on_exit = function(code, lines, objects)
      if M.status[project.root] == status then
        M.status[project.root] = nil
        M.following[project.root] = nil
        for buf in pairs(marked) do
          if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
          end
        end
        marked = {}
        M.mark_animating(project, { time = 0, playing = false })
      end
      if launched[key] == signature and not cli.running(key) then
        launched[key] = nil
      end
      changed(project)
      if code == 0 or cli.was_stopped(job) then
        return
      end
      -- It never got ready: the output says why.
      if status.state ~= "ready" then
        local report = #objects > 0 and require("gaanim.check").from_json(project, objects, lines)
          or require("gaanim.check").parse(project, lines)
        if #report.items > 0 then
          require("gaanim.check").publish(project, report)
          cli.notify(("✗ %s (exit %d)"):format(report.items[1].text, code), vim.log.levels.ERROR)
          return
        end
      end
      cli.notify(("gaanim exited with %d; see :Gaanim log"):format(code), vim.log.levels.WARN)
    end,
  })
  if not job then
    M.status[project.root] = nil
  end
end

--- Moves the preview to the instant of the line under the cursor, starting
--- it when it is closed. Older versions restart it from the cursor's segment.
---@param present? boolean
function M.here(present)
  local project = project_mod.require()
  if not project then
    return
  end
  local target = cursor_line()
  if M.send(project, { cmd = "follow", file = target.file, line = target.line }) then
    return
  end
  if caps.get().listen and config.get().preview.listen then
    M.launch({ present = present, follow = target })
    return
  end
  local slide = M.slide_at_cursor()
  if slide then
    M.launch({ present = present, from = slide })
  end
end

--- The name of the segment around the cursor: from the Python, else from
--- the timeline's instant of the cursor's line.
---@param project gaanim.Project
---@return string?
function M.segment_at_cursor(project)
  local here = index.at_cursor(0)
  if here.segment and here.segment.name then
    return here.segment.name
  end
  local inspect = require("gaanim.inspect")
  local data = inspect.cached(project)
  local point = data and inspect.point_at(data, vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0)[1])
  local segment = point and inspect.segment_at(data, point.time)
  return segment and segment.name
end

--- Loops a segment (by name, or the one around the cursor), a time range
--- (`"1.2 3.4"`), or stops looping (`"off"`). The preview plays the range
--- over and over, through its stops, and keeps it across reloads.
---@param target? string
function M.loop(target)
  local project = project_mod.require()
  if not project then
    return
  end
  local command
  if target == "off" then
    command = { cmd = "unloop" }
  elseif target and target:match("^%s*[%d%.]+%s+[%d%.]+%s*$") then
    local first, last = target:match("([%d%.]+)%s+([%d%.]+)")
    command = { cmd = "loop", start = tonumber(first), ["end"] = tonumber(last) }
  else
    local name = (target and target ~= "" and target ~= "here") and target or M.segment_at_cursor(project)
    if not name then
      cli.notify("No segment around the cursor to loop", vim.log.levels.WARN)
      return
    end
    command = { cmd = "loop", segment = name }
  end
  if M.send(project, command) then
    return
  end
  if command.cmd == "unloop" then
    return
  end
  if caps.get().listen and config.get().preview.listen then
    M.launch({ queue = { command } })
  else
    cli.notify("Looping from Neovim needs a Gaanim with --listen", vim.log.levels.WARN)
  end
end

--- The segment whose whole range the preview loops, if any.
---@param project gaanim.Project
---@return string?
function M.looped_segment(project)
  local status = M.status[project.root]
  local loop = status and status.playhead and status.playhead.loop
  local data = loop and require("gaanim.inspect").cached(project)
  for _, segment in ipairs(data and data.segments or {}) do
    if math.abs(segment.start - loop[1]) < 1e-3 and math.abs(segment["end"] - loop[2]) < 1e-3 then
      return segment.name
    end
  end
end

--- Loops the cursor's segment, or stops looping when the preview loops.
function M.toggle_loop()
  local project = project_mod.require()
  if not project then
    return
  end
  local status = M.status[project.root]
  if status and status.playhead and status.playhead.loop then
    M.loop("off")
  else
    M.loop()
  end
end

--- Rests the preview at a time (seconds), or at a segment, Section key or
--- stop by name.
---@param target string
function M.seek(target)
  local project = project_mod.require()
  if not project then
    return
  end
  local command
  local seconds = tonumber(target)
  if seconds then
    command = { cmd = "seek", time = seconds }
  else
    command = { cmd = "seek", segment = target }
    for _, symbol in ipairs(index.project_symbols(project)) do
      if symbol.kind == "stop" and symbol.name == target then
        command = { cmd = "seek", stop = target }
        break
      end
    end
  end
  if M.send(project, command) then
    return
  end
  if caps.get().listen and config.get().preview.listen then
    M.launch({ queue = { command } })
  else
    cli.notify("Moving the preview needs a Gaanim with --listen", vim.log.levels.WARN)
  end
end

---@param playing boolean
function M.play(playing)
  local project = project_mod.require()
  if project and not M.send(project, { cmd = playing and "play" or "pause" }) then
    cli.notify("No preview takes commands; open one with :Gaanim preview", vim.log.levels.WARN)
  end
end

--- Makes the preview follow the cursor through the code, or stop following.
---@param on? boolean Toggle when nil
function M.follow(on)
  local project = project_mod.require()
  if not project then
    return
  end
  if not (caps.get().listen and config.get().preview.listen) then
    cli.notify("Following the cursor needs a Gaanim with --listen (gaanim update)", vim.log.levels.WARN)
    return
  end
  if on == nil then
    on = not M.following[project.root]
  end
  M.following[project.root] = on or nil
  if on then
    local status = M.status[project.root]
    if not (status and status.listen and cli.running(status.key)) then
      M.launch({ follow = cursor_line() })
    else
      M.on_cursor(true)
    end
  end
  cli.notify(on and "The preview follows the cursor" or "The preview no longer follows the cursor")
  changed(project)
end

local follow_timer = vim.uv.new_timer()
---@type table<string, string>
local last_followed = {}

--- Called when the cursor moves: sends its line to a following preview.
---@param now? boolean Send without waiting
function M.on_cursor(now)
  if not next(M.following) then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "python" then
    return
  end
  local root = vim.b[buf].gaanim_root
  if root == nil then
    root = vim.fs.root(buf, "gaanim.toml") or false
    vim.b[buf].gaanim_root = root
  end
  if not (root and M.following[root]) then
    return
  end
  local target = cursor_line()
  local signature = target.file .. ":" .. target.line
  if last_followed[root] == signature then
    return
  end
  local function send()
    local project = project_mod.load(root)
    if project and M.send(project, { cmd = "follow", file = target.file, line = target.line }) then
      last_followed[root] = signature
    end
  end
  follow_timer:stop()
  if now then
    send()
  else
    follow_timer:start(config.get().preview.follow_delay, 0, vim.schedule_wrap(send))
  end
end

--- Stops the preview and presentation of the current project.
function M.stop()
  local project = project_mod.current()
  if not project then
    cli.stop_all()
    return
  end
  local any = false
  for _, prefix in ipairs({ "preview:", "present:" }) do
    if cli.running(prefix .. project.root) then
      any = true
      cli.stop(prefix .. project.root)
    end
  end
  M.following[project.root] = nil
  cli.notify(any and ("Closed " .. project.name) or "Nothing running for this project")
end

---@param project gaanim.Project
---@return { preview: boolean, present: boolean }
function M.state(project)
  return { preview = cli.running("preview:" .. project.root), present = cli.running("present:" .. project.root) }
end

return M
