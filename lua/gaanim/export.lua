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
  local progress = ui.progress("Gaanim export")
  progress.update(vim.fs.basename(output), 0)
  cli.run(cmd, {
    cwd = project.root,
    key = "export:" .. output,
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
    on_exit = function(code, lines)
      local done
      for _, line in ipairs(lines) do
        done = line:match("^%s%s✓%s+%S+%s+(.*)$") or done
      end
      if code == 0 then
        progress.finish(true, done or ("wrote " .. output))
        if config.get().export.open then
          vim.ui.open(output)
        end
        return
      end
      local report = require("gaanim.check").parse(project, lines)
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
        icon = "◆",
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
  table.insert(items, { text = "Type a time…", icon = "⏱", value = false })
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
