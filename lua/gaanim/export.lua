---@mod gaanim.export Rendering videos, PDFs, bundles and stills

local cli = require("gaanim.cli")
local config = require("gaanim.config")
local index = require("gaanim.index")
local project_mod = require("gaanim.project")
local ui = require("gaanim.ui")

local M = {}

--- Preset names in the order the picker lists them.
---@return string[]
function M.preset_names()
  local presets = config.get().export.presets
  local order = { "mp4", "draft", "production", "webm", "mov", "gif", "webp", "pdf", "notes", "bundle", "still" }
  local names, seen = {}, {}
  for _, name in ipairs(order) do
    if presets[name] then
      table.insert(names, name)
      seen[name] = true
    end
  end
  local extra = {}
  for name in pairs(presets) do
    if not seen[name] then
      table.insert(extra, name)
    end
  end
  table.sort(extra)
  return vim.list_extend(names, extra)
end

---@param project gaanim.Project
---@param name string
---@param preset gaanim.ExportPreset
---@param frame? string
---@return string
local function default_output(project, name, preset, frame)
  local stem = project.name
  if name == "draft" or name == "notes" then
    stem = stem .. "-" .. name
  elseif frame then
    stem = stem .. "-" .. frame:gsub("[^%w%._-]", "_")
  end
  return vim.fs.joinpath(project.output_dir, stem .. "." .. preset.ext)
end

---@param project gaanim.Project
---@param output string
---@param args string[]
local function run(project, output, args)
  vim.fn.mkdir(vim.fs.dirname(output), "p")
  local cmd = { "export", project.target, "--output", output }
  vim.list_extend(cmd, args)
  local json = require("gaanim.caps").get().json
  if json then
    vim.list_extend(cmd, { "--message-format", "json" })
  end
  local progress = ui.progress("Gaanim export")
  local name = vim.fs.basename(output)
  progress.update(name, 0)
  cli.run(cmd, {
    cwd = project.root,
    key = "export:" .. output,
    on_json = function(object)
      if object.type == "progress" and object.percent then
        progress.update(("%s %d%%"):format(name, object.percent), object.percent)
      elseif object.type == "message" and object.level == "info" and object.label ~= "export" then
        progress.update(object.message or name)
      end
    end,
    on_line = function(line)
      local label, text = line:match("^%s%s▸%s+(%S+)%s+(.*)$")
      if label and label ~= "export" then
        progress.update(text)
      end
      local percent = line:match("(%d+)%%")
      if percent then
        progress.update(vim.trim(line:gsub("^%s*%S+%s+%S+%s+", "")), tonumber(percent))
      end
    end,
    on_exit = function(code, lines, objects)
      local done
      for _, line in ipairs(lines) do
        done = line:match("^%s%s✓%s+%S+%s+(.*)$") or done
      end
      for _, object in ipairs(objects) do
        if object.type == "message" and object.level == "success" then
          done = object.message or done
        end
      end
      if code == 0 then
        progress.finish(true, done or ("wrote " .. output))
        if config.get().export.open then
          vim.ui.open(output)
        end
        return
      end
      local report = #objects > 0 and require("gaanim.check").from_json(project, objects, lines)
        or require("gaanim.check").parse(project, lines)
      if #report.items > 0 then
        require("gaanim.check").publish(project, report)
      end
      progress.finish(false, report.summary ~= "" and report.summary or "export failed; see :Gaanim log")
    end,
  })
end

--- Exports with a preset name, or to an output path whose extension picks
--- the format. Extra arguments go to `gaanim export` as they are.
---@param target? string Preset name or output path
---@param extra? string[]
function M.export(target, extra)
  local project = project_mod.require()
  if not project then
    return
  end
  extra = extra or {}
  if not target then
    local presets = config.get().export.presets
    local items = vim.tbl_map(function(name)
      return { text = name, hint = presets[name].desc .. "  ." .. presets[name].ext, value = name }
    end, M.preset_names())
    ui.pick(items, {
      title = "Export " .. project.name,
      on_choice = function(item)
        M.export(item.value, extra)
      end,
    })
    return
  end
  local preset = config.get().export.presets[target]
  if not preset then
    if target:match("%.%w+$") then
      local output = vim.fs.normalize(vim.fn.fnamemodify(target, ":p"))
      run(project, output, extra)
    else
      cli.notify("Unknown export preset: " .. target, vim.log.levels.ERROR)
    end
    return
  end
  local here = false
  extra = vim.tbl_filter(function(arg)
    if arg == "here" then
      here = true
      return false
    end
    return true
  end, extra)
  if here then
    M.slide_range(project, function(range)
      if range then
        M.export(target, vim.list_extend({ "--from", range.from, "--to", range.to }, extra))
      end
    end)
    return
  end
  local args = vim.list_extend(vim.deepcopy(preset.args or {}), extra)
  if preset.ask == "frame" and not vim.tbl_contains(args, "--frame") then
    M.ask_frame(project, function(frame)
      vim.list_extend(args, { "--frame", frame })
      run(project, default_output(project, target, preset, frame), args)
    end)
    return
  end
  local frame
  for i, arg in ipairs(args) do
    if arg == "--frame" then
      frame = args[i + 1]
    end
  end
  run(project, default_output(project, target, preset, frame), args)
end

--- The `--output` of a workspace export: `workspace.output` under its root
--- (`{member}` is each member's path), with the preset's suffix and
--- extension, as `default_output` names a project's.
---@param workspace gaanim.Workspace
---@param name string Preset name
---@param preset gaanim.ExportPreset
---@param frame? string
---@return string
function M.workspace_output(workspace, name, preset, frame)
  local pattern = config.get().workspace.output
  if not pattern:find("{member}", 1, true) then
    pattern = pattern .. "/{member}"
  end
  local suffix = ""
  if name == "draft" or name == "notes" then
    suffix = "-" .. name
  elseif frame then
    suffix = "-" .. frame:gsub("[^%w%._-]", "_")
  end
  local output = pattern .. suffix .. "." .. preset.ext
  if not (output:match("^%a:[/\\]") or output:match("^/")) then
    output = vim.fs.joinpath(workspace.root, output)
  end
  return vim.fs.normalize(output)
end

--- Exports every member of a workspace (or those `patterns` names, as
--- `--members` takes them) with a preset, each in a `gaanim export` of its
--- own: `{member}` in the output becomes each member's path, so the files
--- repeat the workspace's layout.
---@param workspace gaanim.Workspace
---@param target? string Preset name
---@param patterns? string
---@param extra? string[]
function M.workspace(workspace, target, patterns, extra)
  extra = extra or {}
  local presets = config.get().export.presets
  if not target then
    local items = vim.tbl_map(function(name)
      return { text = name, hint = presets[name].desc .. "  ." .. presets[name].ext, value = name }
    end, M.preset_names())
    ui.pick(items, {
      title = "Export the members of " .. workspace.name,
      on_choice = function(item)
        M.workspace(workspace, item.value, patterns, extra)
      end,
    })
    return
  end
  local preset = presets[target]
  if not preset then
    cli.notify("Unknown export preset: " .. target, vim.log.levels.ERROR)
    return
  end
  local args = vim.list_extend(vim.deepcopy(preset.args or {}), extra)
  local frame
  for i, arg in ipairs(args) do
    if arg == "--frame" then
      frame = args[i + 1]
    end
  end
  if preset.ask == "frame" and not frame then
    -- Markers differ between members: a time, or a name each one has.
    ui.input("Time in seconds or marker of every member: ", nil, function(value)
      M.workspace(workspace, target, patterns, vim.list_extend(vim.deepcopy(extra), { "--frame", value }))
    end)
    return
  end
  local output = M.workspace_output(workspace, target, preset, frame)
  local members = vim.tbl_filter(function(member)
    return not member.error
  end, require("gaanim.workspace").select(workspace, patterns))
  if #members == 0 then
    cli.notify("No member to export in " .. workspace.name, vim.log.levels.WARN)
    return
  end
  for _, member in ipairs(members) do
    vim.fn.mkdir(vim.fs.dirname((output:gsub("{member}", member.path))), "p")
  end
  local cmd = { "export", workspace.root, "--output", output }
  if patterns and patterns ~= "" then
    vim.list_extend(cmd, { "--members", patterns })
  end
  vim.list_extend(cmd, args)
  vim.list_extend(cmd, { "--message-format", "json" })
  local progress = ui.progress("Gaanim export · " .. workspace.name)
  local total, index, current = #members, 0, nil
  local errors = {}
  progress.update(require("gaanim.workspace").count(total), 0)
  cli.run(cmd, {
    cwd = workspace.root,
    key = "export:" .. workspace.root,
    on_json = function(object)
      if object.type == "message" and object.label == "export" and object.level == "info" then
        local path = (object.message or ""):match("^(.-) · ")
        if path and require("gaanim.workspace").member(workspace, path) then
          index, current = index + 1, path
          progress.update(("%s (%d/%d)"):format(path, index, total), math.floor((index - 1) / total * 100))
        end
      elseif object.type == "progress" and object.percent and current then
        local overall = ((index - 1) + object.percent / 100) / total * 100
        progress.update(("%s %d%% (%d/%d)"):format(current, object.percent, index, total), math.floor(overall))
      elseif object.type == "message" and object.level == "error" then
        table.insert(errors, (current and (current .. ": ") or "") .. (object.message or "failed"))
      end
    end,
    on_exit = function(code, _, objects)
      local summary
      for _, object in ipairs(objects) do
        if object.type == "workspace" then
          summary = object
        end
      end
      local where = vim.fn.fnamemodify(vim.fs.dirname((output:gsub("{member}.*$", "x"))), ":~:.")
      if code == 0 then
        local count = require("gaanim.workspace").count(summary and summary.passed or total)
        progress.finish(true, ("exported %s to %s"):format(count, where))
        if config.get().export.open then
          vim.ui.open(vim.fs.dirname((output:gsub("{member}.*$", "x"))))
        end
        return
      end
      local text = summary
          and ("exported %d of %s"):format(
            summary.passed or 0,
            require("gaanim.workspace").count(summary.members or total)
          )
        or "export failed"
      if #errors > 0 then
        text = text .. " · " .. errors[#errors]
      end
      progress.finish(false, text .. "; see :Gaanim log")
    end,
  })
end

---@param seconds number
---@return string
local function seconds_arg(seconds)
  return (("%.3f"):format(seconds):gsub("0+$", ""):gsub("%.$", ""))
end

--- The instant the line under the cursor stands for, from `gaanim inspect`,
--- else the name of the stop or segment around it (when `export` takes
--- names). Calls `on_frame` with nil when neither is known.
---@param project gaanim.Project
---@param on_frame fun(frame?: string, label?: string)
function M.frame_at_cursor(project, on_frame)
  local file = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local inspect = require("gaanim.inspect")
  inspect.get(project, function(data)
    local point = data and inspect.point_at(data, file, line)
    if point then
      on_frame(seconds_arg(point.time), point.name or point.kind)
      return
    end
    if require("gaanim.caps").get().names then
      local here = index.at_cursor(0)
      local name = (here.stop and here.stop.name) or (here.segment and here.segment.name)
      if name then
        on_frame(name, name)
        return
      end
    end
    on_frame(nil)
  end)
end

--- Exports one PNG of the instant the line under the cursor stands for.
function M.still_here()
  local project = project_mod.require()
  if not project then
    return
  end
  M.frame_at_cursor(project, function(frame, label)
    if not frame then
      M.export("still")
      return
    end
    -- Named after what the line is (`talk-dato.png`), exported at its instant.
    local stem = project.name .. "-" .. tostring(label or frame):gsub("[^%w%._-]", "_")
    M.export(vim.fs.joinpath(project.output_dir, stem .. ".png"), { "--frame", frame })
  end)
end

--- The range of the slide under the cursor: by name when `export` takes
--- names, else its start and end from `gaanim inspect`.
---@param project gaanim.Project
---@param on_range fun(range?: { from: string, to: string })
function M.slide_range(project, on_range)
  local here = index.at_cursor(0)
  local name = here.segment and here.segment.name
  if name and require("gaanim.caps").get().names then
    on_range({ from = name, to = name })
    return
  end
  local inspect = require("gaanim.inspect")
  local file = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  local line = vim.api.nvim_win_get_cursor(0)[1]
  inspect.get(project, function(data)
    local point = data and inspect.point_at(data, file, line)
    local segment = point and inspect.segment_at(data, point.time)
    if segment then
      on_range({ from = seconds_arg(segment.start), to = seconds_arg(segment["end"]) })
    else
      cli.notify("No slide under the cursor to export", vim.log.levels.WARN)
      on_range(nil)
    end
  end)
end

--- Asks for an instant: one of the scene's markers, or a time in seconds.
---@param project gaanim.Project
---@param on_frame fun(frame: string)
function M.ask_frame(project, on_frame)
  local items = {}
  for _, symbol in ipairs(index.project_symbols(project)) do
    if symbol.kind == "marker" and symbol.name then
      table.insert(items, {
        text = symbol.name,
        hint = vim.fn.fnamemodify(symbol.file, ":t") .. ":" .. symbol.lnum,
        icon = require("gaanim.icons").get().marker,
        value = symbol.name,
      })
    end
  end
  local function ask_time()
    ui.input("Time in seconds or marker: ", nil, on_frame)
  end
  if #items == 0 then
    ask_time()
    return
  end
  table.insert(items, { text = "Type a time…", icon = require("gaanim.icons").get().time, value = false })
  ui.pick(items, {
    title = "Frame to export",
    on_choice = function(item)
      if item.value then
        on_frame(item.value)
      else
        ask_time()
      end
    end,
  })
end

return M
