---@mod gaanim.commands The :Gaanim command

local M = {}

---@class gaanim.Subcommand
---@field desc string
---@field run fun(args: string[], opts: table)
---@field complete? fun(arglead: string, args: string[]): string[]

local function filter(list, arglead)
  return vim.tbl_filter(function(value)
    return vim.startswith(value, arglead)
  end, list)
end

--- The member paths of the current workspace, as last described (or now).
---@param arglead string
---@return string[]
local function member_paths(arglead)
  local workspace = require("gaanim.workspace").current(0, { quiet = true, cached = true })
  local paths = {}
  for _, member in ipairs(workspace and workspace.members or {}) do
    table.insert(paths, member.path)
  end
  -- `--members` takes several, comma-separated.
  local before, last = arglead:match("^(.*,)([^,]*)$")
  return vim.tbl_map(function(path)
    return (before or "") .. path
  end, filter(paths, last or arglead))
end

local WORKSPACE = { "members", "use", "check", "export", "new", "info" }

---@param args string[]
local function workspace_command(args)
  local ws_mod = require("gaanim.workspace")
  local action = args[1] or "members"
  local workspace = ws_mod.current(0)
  if not workspace then
    return
  end
  if action == "members" then
    ws_mod.pick(workspace, {
      actions = true,
      on_choice = function(member)
        ws_mod.open(workspace, member)
      end,
    })
  elseif action == "use" then
    local function use(member)
      ws_mod.use(workspace.root, member.root)
      require("gaanim.cli").notify(("Shared files of %s run as %s"):format(workspace.name, ws_mod.label(member)))
    end
    local member = args[2] and ws_mod.member(workspace, args[2])
    if member and not member.error then
      use(member)
    elseif args[2] then
      require("gaanim.cli").notify("No member " .. args[2] .. " in " .. workspace.name, vim.log.levels.ERROR)
    else
      ws_mod.pick(
        workspace,
        { title = "Shared files of " .. workspace.name .. " run as", valid = true, on_choice = use }
      )
    end
  elseif action == "check" then
    require("gaanim.check").workspace(workspace, args[2])
  elseif action == "export" then
    local preset, patterns = args[2], args[3]
    if preset and not require("gaanim.config").get().export.presets[preset] then
      -- `:Gaanim workspace export videos/*` picks the preset.
      preset, patterns = nil, preset
    end
    require("gaanim.export").workspace(workspace, preset, patterns, vim.list_slice(args, 4))
  elseif action == "new" then
    local kind, name = args[2], args[3]
    if kind and kind ~= "video" and kind ~= "slides" then
      kind, name = nil, kind
    end
    require("gaanim.new").member(workspace, kind, name)
  elseif action == "info" then
    ws_mod.info()
  else
    require("gaanim.cli").notify(
      "Usage: :Gaanim workspace [" .. table.concat(WORKSPACE, "|") .. "]",
      vim.log.levels.WARN
    )
  end
end

---@type table<string, gaanim.Subcommand>
M.subcommands = {
  new = {
    desc = "Create a project or workspace: new [slides|video|workspace] [name]",
    run = function(args)
      require("gaanim.new").new(args[1], args[2])
    end,
    complete = function(arglead, args)
      return #args <= 1 and filter(require("gaanim.new").kinds, arglead) or {}
    end,
  },
  projects = {
    desc = "Open one of your projects or workspaces",
    run = function()
      require("gaanim.new").projects()
    end,
  },
  workspace = {
    desc = "The workspace: workspace [members|use|check|export|new|info]",
    run = workspace_command,
    complete = function(arglead, args)
      if #args <= 1 then
        return filter(WORKSPACE, arglead)
      end
      local action = args[1]
      if (action == "use" or action == "check") and #args == 2 then
        return member_paths(arglead)
      elseif action == "export" and #args == 2 then
        return filter(require("gaanim.export").preset_names(), arglead)
      elseif action == "export" and #args == 3 then
        return member_paths(arglead)
      elseif action == "new" and #args == 2 then
        return filter({ "video", "slides" }, arglead)
      end
      return {}
    end,
  },
  preview = {
    desc = "Open the live preview: preview [here|only]",
    run = function(args)
      local preview = require("gaanim.preview")
      if args[1] == "here" then
        preview.here()
      elseif args[1] == "only" then
        local slide = preview.slide_at_cursor()
        if slide then
          preview.launch({ sections = { slide } })
        end
      else
        preview.launch({ args = args })
      end
    end,
    complete = function(arglead, args)
      return #args <= 1 and filter({ "here", "only" }, arglead) or {}
    end,
  },
  present = {
    desc = "Present fullscreen: present [here] [duration]",
    run = function(args)
      local preview = require("gaanim.preview")
      local opts = { present = true }
      for _, arg in ipairs(args) do
        if arg == "here" then
          if require("gaanim.caps").get().listen and require("gaanim.config").get().preview.listen then
            opts.follow = { file = vim.fs.normalize(vim.api.nvim_buf_get_name(0)), line = vim.fn.line(".") }
          else
            opts.from = preview.slide_at_cursor()
            if not opts.from then
              return
            end
          end
        elseif arg:match("^%d+[hms]") then
          opts.duration = arg
        elseif arg:match("^monitor=(%d+)$") then
          opts.monitor = tonumber(arg:match("(%d+)"))
        end
      end
      preview.launch(opts)
    end,
    complete = function(arglead)
      return filter({ "here", "20m", "45m", "1h", "monitor=1" }, arglead)
    end,
  },
  follow = {
    desc = "Make the preview follow the cursor: follow [on|off]",
    run = function(args)
      local on = args[1] == "on" or (args[1] ~= "off" and nil)
      require("gaanim.preview").follow(on)
    end,
    complete = function(arglead, args)
      return #args <= 1 and filter({ "on", "off" }, arglead) or {}
    end,
  },
  seek = {
    desc = "Move the preview: seek {seconds|segment|stop}",
    run = function(args)
      if #args == 0 then
        vim.notify("Usage: :Gaanim seek {seconds|segment|stop}", vim.log.levels.WARN, { title = "Gaanim" })
        return
      end
      require("gaanim.preview").seek(table.concat(args, " "))
    end,
    complete = function(arglead)
      local project = require("gaanim.project").current()
      if not project then
        return {}
      end
      local names, seen = {}, {}
      for _, symbol in ipairs(require("gaanim.index").project_symbols(project)) do
        local name = symbol.name
        if
          name
          and not seen[name]
          and (symbol.kind == "segment" or symbol.kind == "section" or symbol.kind == "stop")
        then
          seen[name] = true
          table.insert(names, name)
        end
      end
      return filter(names, arglead)
    end,
  },
  loop = {
    desc = "Loop a slide in the preview: loop [segment|START END|off] (default: the cursor's)",
    run = function(args)
      require("gaanim.preview").loop(#args > 0 and table.concat(args, " ") or nil)
    end,
    complete = function(arglead, args)
      if #args > 1 then
        return {}
      end
      local names = { "off" }
      local project = require("gaanim.project").current()
      for _, symbol in ipairs(project and require("gaanim.index").project_symbols(project) or {}) do
        if (symbol.kind == "segment" or symbol.kind == "section") and symbol.name then
          table.insert(names, symbol.name)
        end
      end
      return filter(names, arglead)
    end,
  },
  panel = {
    desc = "A playback panel for the preview: play, scrub, slides, loop (toggle)",
    run = function()
      require("gaanim.panel").toggle()
    end,
  },
  play = {
    desc = "Play the preview from where it rests",
    run = function()
      require("gaanim.preview").play(true)
    end,
  },
  pause = {
    desc = "Pause the preview",
    run = function()
      require("gaanim.preview").play(false)
    end,
  },
  live = {
    desc = "Live mode: changes reach the preview as you make them: live [on|off]",
    run = function(args)
      local on = args[1] == "on" or (args[1] ~= "off" and nil)
      require("gaanim.live").toggle(on)
    end,
    complete = function(arglead, args)
      return #args <= 1 and filter({ "on", "off" }, arglead) or {}
    end,
  },
  timeline = {
    desc = "The timeline from gaanim inspect, with times; jump and seek",
    run = function()
      require("gaanim.outline").timeline()
    end,
  },
  stop = {
    desc = "Close the preview or presentation of this project",
    run = function()
      require("gaanim.preview").stop()
    end,
  },
  check = {
    desc = "Check the project; problems go to quickfix and diagnostics",
    run = function()
      require("gaanim.check").run()
    end,
  },
  export = {
    desc = "Export: export [preset|output.ext] [here] [gaanim export options]",
    run = function(args)
      require("gaanim.export").export(args[1], vim.list_slice(args, 2))
    end,
    complete = function(arglead, args)
      if #args <= 1 then
        return filter(require("gaanim.export").preset_names(), arglead)
      end
      return filter({
        "here",
        "--from",
        "--to",
        "--fps",
        "--width",
        "--height",
        "--quality",
        "--transparent",
        "--fit",
        "--notes",
      }, arglead)
    end,
  },
  still = {
    desc = "Export one PNG: still [seconds|name|pick] (default: the cursor's instant)",
    run = function(args)
      local export = require("gaanim.export")
      if args[1] == "pick" then
        export.export("still")
      elseif args[1] then
        export.export("still", { "--frame", args[1] })
      else
        export.still_here()
      end
    end,
    complete = function(arglead, args)
      return #args <= 1 and filter({ "pick" }, arglead) or {}
    end,
  },
  outline = {
    desc = "Jump to a segment, section, stop or marker",
    run = function(args)
      local kinds
      if args[1] then
        kinds = {}
        for _, kind in ipairs(args) do
          kinds[kind] = true
        end
      end
      require("gaanim.outline").pick(kinds)
    end,
    complete = function(arglead)
      return filter({ "segment", "section", "stop", "marker", "voiceover" }, arglead)
    end,
  },
  script = {
    desc = "Narration script: script [open|toggle|goto]",
    run = function(args)
      require("gaanim.script").command(args[1] or "toggle")
    end,
    complete = function(arglead, args)
      return #args <= 1 and filter({ "open", "toggle", "goto" }, arglead) or {}
    end,
  },
  docs = {
    desc = "Search the documentation of the installed Gaanim: docs [text]",
    run = function(args)
      require("gaanim.docs").open(#args > 0 and table.concat(args, " ") or nil)
    end,
  },
  api = {
    desc = "Open the API entry of a name (default: the word under the cursor)",
    run = function(args)
      require("gaanim.docs").api(args[1])
    end,
  },
  log = {
    desc = "Show the output of gaanim commands",
    run = function()
      require("gaanim.cli").open_log()
    end,
  },
}

---@param opts table Arguments of a user command callback
function M.run(opts)
  local args = vim.deepcopy(opts.fargs)
  local name = table.remove(args, 1)
  if not name then
    local items = {}
    for key, sub in vim.spairs(M.subcommands) do
      table.insert(items, { text = key, hint = sub.desc, value = key })
    end
    require("gaanim.ui").pick(items, {
      title = "Gaanim",
      on_choice = function(item)
        M.subcommands[item.value].run({}, opts)
      end,
    })
    return
  end
  local sub = M.subcommands[name]
  if not sub then
    vim.notify("Unknown :Gaanim subcommand: " .. name, vim.log.levels.ERROR, { title = "Gaanim" })
    return
  end
  -- A command run from a workspace's shared module may first ask which
  -- member to run as; it then runs again with it.
  local project = require("gaanim.project")
  local previous = project.retry
  project.retry = function()
    sub.run(args, opts)
  end
  local ok, err = pcall(sub.run, args, opts)
  project.retry = previous
  if not ok then
    error(err, 0)
  end
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local words = vim.split(cmdline:gsub("^%s*%S+%s*", ""), "%s+", { trimempty = false })
  if #words <= 1 then
    local names = vim.tbl_keys(M.subcommands)
    table.sort(names)
    return filter(names, arglead)
  end
  local sub = M.subcommands[words[1]]
  if sub and sub.complete then
    return sub.complete(arglead, vim.list_slice(words, 2))
  end
  return {}
end

return M
