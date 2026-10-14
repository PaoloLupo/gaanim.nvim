---@mod gaanim.check `gaanim check` as quickfix items and diagnostics

local cli = require("gaanim.cli")
local config = require("gaanim.config")
local index = require("gaanim.index")
local project_mod = require("gaanim.project")

local M = {}

M.ns = vim.api.nvim_create_namespace("gaanim.check")

local GLYPHS = { ["✓"] = "pass", ["!"] = "warning", ["✗"] = "error", ["▸"] = "info" }

---@class gaanim.Report
---@field status "pass"|"warning"|"error"
---@field summary string
---@field items vim.quickfix.entry[]

--- Splits the report into entries: one per glyph line, with the lines that
--- follow it (a traceback) attached.
---@param lines string[]
---@return { level: string, label: string, text: string, more: string[] }[]
function M.entries(lines)
  local entries = {}
  for _, line in ipairs(lines) do
    local glyph, label, text = line:match("^%s%s(%S+)%s+(%S+)%s*(.*)$")
    if glyph and GLYPHS[glyph] then
      table.insert(entries, { level = GLYPHS[glyph], label = label, text = text, more = {} })
    elseif #entries > 0 and not line:match("^%[exit %d+%]$") then
      table.insert(entries[#entries].more, line)
    end
  end
  return entries
end

--- The frame of a Python traceback that points into the project, and the
--- exception line that ends it.
---@param lines string[]
---@param root string
---@return { file: string, lnum: integer }?, string?
function M.traceback(lines, root)
  local frame, message
  root = vim.fs.normalize(root):lower()
  for _, line in ipairs(lines) do
    local file, lnum = line:match('File "(.-)", line (%d+)')
    if file and not file:match("^<") then
      local path = vim.fs.normalize(file)
      if path:lower():sub(1, #root) == root or not frame then
        frame = { file = path, lnum = tonumber(lnum) }
      end
    end
    local exc = line:match("^%s*([%w_%.]+Error: .*)$")
      or line:match("^%s*([%w_%.]+Exception: .*)$")
      or line:match("^%s*([%w_%.]+Warning: .*)$")
    if exc then
      message = exc
    end
  end
  if not message then
    for i = #lines, 1, -1 do
      if vim.trim(lines[i]) ~= "" then
        message = vim.trim(lines[i])
        break
      end
    end
  end
  return frame, message
end

---@param path string
---@param needle string Plain text
---@param from? integer First line to search
---@return integer?
local function find_line(path, needle, from)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local lnum = 0
  for line in file:lines() do
    lnum = lnum + 1
    if lnum >= (from or 1) and line:find(needle, 1, true) then
      file:close()
      return lnum
    end
  end
  file:close()
  return nil
end

--- Gives a warning a place to point at: the line `(line N)` names, the
--- script mark it quotes, or the segment it is about.
---@param project gaanim.Project
---@param text string
---@return string? file, integer? lnum
function M.locate(project, text)
  local script = require("gaanim.script")
  local md, lnum = text:match("^([^:%s]+%.md): .-%(line (%d+)%)")
  if md then
    local path = script.path(project)
    if not path or vim.fs.basename(path) ~= md then
      path = vim.fs.joinpath(project.root, md)
    end
    return path, tonumber(lnum)
  end
  local segment = text:match("^segment `(.-)`") or text:match("^section `(.-)`") or text:match("segment `(.-)`")
  local mark = text:match("is (%[stop[^%]]*%])")
  if segment and mark then
    local path = script.path(project)
    local section = path and script.section_line(path, segment)
    local line = path and find_line(path, mark, section)
    if line then
      return path, line
    end
  end
  local stop = text:match("stop %d+ is `(.-)`") or text:match("stop `(.-)`")
  if stop then
    for _, symbol in ipairs(index.project_symbols(project)) do
      if symbol.kind == "stop" and symbol.name == stop then
        return symbol.file, symbol.lnum
      end
    end
  end
  if segment then
    local symbol = index.find(project, segment)
    if symbol then
      return symbol.file, symbol.lnum
    end
  end
  return nil
end

--- Turns the output of `gaanim check` into a report.
---@param project gaanim.Project
---@param lines string[]
---@return gaanim.Report
function M.parse(project, lines)
  local report = { status = "pass", summary = "", items = {} }
  for _, entry in ipairs(M.entries(lines)) do
    if entry.level == "pass" then
      report.summary = entry.text
    elseif entry.level == "error" then
      report.status = "error"
      local frame, message = M.traceback(entry.more, project.root)
      local text = message or entry.text
      if #entry.more == 0 then
        text = entry.text
      end
      table.insert(report.items, {
        filename = frame and frame.file or project.entry,
        lnum = frame and frame.lnum or 1,
        col = 1,
        type = "E",
        text = text,
      })
      report.summary = text
    elseif entry.level == "warning" then
      if report.status == "pass" then
        report.status = "warning"
      end
      local file, lnum = M.locate(project, entry.text)
      table.insert(report.items, {
        filename = file or (project.manifest or project.entry),
        lnum = lnum or 1,
        col = 1,
        type = "W",
        text = entry.text,
      })
    end
  end
  return report
end

---@param seconds number
---@return string
local function seconds_text(seconds)
  return ("%.1f s"):format(seconds)
end

--- Turns the JSON lines of `--message-format json` into a report. Gaanim
--- gives each diagnostic its file and line; a traceback (on stderr, in
--- `lines`) still places a script that failed to load.
---@param project gaanim.Project
---@param objects table[]
---@param lines? string[]
---@return gaanim.Report
function M.from_json(project, objects, lines)
  local report = { status = "pass", summary = "", items = {} }
  local fallback = project.manifest or project.entry
  for _, object in ipairs(objects) do
    if object.type == "diagnostic" or (object.type == "message" and object.level == "error") then
      local failed = object.level == "error"
      local file, lnum = object.file and vim.fs.normalize(object.file), object.line
      local message = object.message or ""
      if not file and message:find("Traceback", 1, true) then
        -- A script that failed to load: its traceback is in the message.
        local frame, exception = M.traceback(vim.split(message, "\n"), project.root)
        if frame then
          file, lnum = frame.file, frame.lnum
        end
        object.message = exception or message
      end
      if not file then
        if failed and lines then
          local frame = M.traceback(lines, project.root)
          if frame then
            file, lnum = frame.file, frame.lnum
          end
        else
          file, lnum = M.locate(project, object.message or "")
        end
      end
      table.insert(report.items, {
        filename = file or fallback,
        lnum = lnum or 1,
        col = object.column or 1,
        type = failed and "E" or "W",
        text = object.message or "",
      })
      if failed then
        report.status = "error"
        report.summary = object.message or report.summary
      elseif report.status == "pass" then
        report.status = "warning"
      end
    elseif object.type == "check" then
      local parts = {}
      if object.segments then
        table.insert(parts, ("%d segments"):format(object.segments))
      end
      if object.stops then
        table.insert(parts, ("%d stops"):format(object.stops))
      end
      if object.duration then
        table.insert(parts, seconds_text(object.duration))
      end
      if report.status ~= "error" then
        report.summary = (object.result == "fail" and "fail" or "ready") .. " · " .. table.concat(parts, " · ")
      end
      if object.result == "fail" and report.status ~= "error" then
        report.status = "error"
      end
    end
  end
  return report
end

---@type table<string, integer[]> Buffers that got diagnostics, per project
local marked = {}

---@param project gaanim.Project
---@param report gaanim.Report
function M.publish(project, report)
  for _, buf in ipairs(marked[project.root] or {}) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.diagnostic.reset(M.ns, buf)
    end
  end
  local per_buf = {}
  for _, item in ipairs(report.items) do
    local buf = vim.fn.bufadd(item.filename)
    per_buf[buf] = per_buf[buf] or {}
    table.insert(per_buf[buf], {
      lnum = item.lnum - 1,
      col = 0,
      severity = item.type == "E" and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
      source = "gaanim",
      message = item.text,
    })
  end
  marked[project.root] = {}
  for buf, diagnostics in pairs(per_buf) do
    table.insert(marked[project.root], buf)
    vim.diagnostic.set(M.ns, buf, diagnostics)
  end
  vim.fn.setqflist({}, " ", { title = "gaanim check · " .. project.name, items = report.items })
end

---@type table<string, gaanim.Report>
M.last = {}

---@param opts? { project?: gaanim.Project, quiet?: boolean }
function M.run(opts)
  opts = opts or {}
  local project = opts.project or project_mod.require()
  if not project then
    return
  end
  local key = "check:" .. project.root
  if cli.running(key) then
    cli.stop(key)
  end
  local args = { "check", project.target }
  if config.get().check.strict then
    table.insert(args, "--strict")
  end
  if require("gaanim.caps").get().json then
    vim.list_extend(args, { "--message-format", "json" })
  end
  cli.run(args, {
    cwd = project.root,
    key = key,
    on_exit = function(code, lines, objects)
      if code ~= 0 and code ~= 1 and #objects == 0 and #M.entries(lines) == 0 then
        cli.notify("gaanim check failed; see :Gaanim log", vim.log.levels.ERROR)
        return
      end
      local report = #objects > 0 and M.from_json(project, objects, lines) or M.parse(project, lines)
      M.last[project.root] = report
      M.publish(project, report)
      local mode = config.get().check.quickfix
      if mode == "always" or (mode == "errors" and report.status == "error") then
        vim.cmd("botright copen")
      end
      if report.status == "error" then
        cli.notify("✗ " .. report.summary, vim.log.levels.ERROR)
      elseif not opts.quiet then
        local warnings = #report.items
        if warnings > 0 then
          cli.notify(
            ("! %d warning%s · %s"):format(warnings, warnings == 1 and "" or "s", report.summary),
            vim.log.levels.WARN
          )
        else
          cli.notify("✓ " .. report.summary)
        end
      end
      vim.api.nvim_exec_autocmds("User", { pattern = "GaanimCheck", data = { root = project.root, report = report } })
    end,
  })
end

local timer = vim.uv.new_timer()

--- Called after a write: checks the project once the saves settle.
---@param buf integer
function M.on_save(buf)
  local opts = config.get().check
  if not opts.on_save then
    return
  end
  local project = project_mod.current(buf)
  if not project then
    return
  end
  timer:stop()
  timer:start(opts.debounce, 0, function()
    vim.schedule(function()
      M.run({ project = project, quiet = true })
    end)
  end)
end

return M
