---@mod gaanim.preview Live preview and presenting

local cli = require("gaanim.cli")
local config = require("gaanim.config")
local index = require("gaanim.index")
local project_mod = require("gaanim.project")

local M = {}

---@class gaanim.LaunchOpts
---@field present? boolean
---@field from? string Segment or Section key to start at
---@field sections? string[] Only these segments or Section keys
---@field duration? string
---@field monitor? integer
---@field args? string[]

---@type table<string, string> Arguments of each running process, to spot changes
local launched = {}

---@type table<string, { state: "starting"|"reloading"|"ready"|"failed", detail?: string, id: table }>
M.status = {}

---@param name string
---@return string
local function escape_commas(name)
  return (name:gsub(",", "\\,"))
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

---@param opts? gaanim.LaunchOpts
function M.launch(opts)
  opts = opts or {}
  local project = project_mod.require()
  if not project then
    return
  end
  local cfg = config.get()
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
  table.insert(args, project.target)

  local key = (opts.present and "present:" or "preview:") .. project.root
  local signature = table.concat(args, "\0")
  if cli.running(key) then
    if launched[key] == signature then
      cli.notify(opts.present and "Already presenting" or "Preview already open; it reloads when you save")
      return
    end
    cli.stop(key)
  end
  launched[key] = signature
  local title = opts.present and "Presenting " or "Previewing "
  local scope = opts.from and (" from " .. opts.from)
    or (opts.sections and (" " .. table.concat(opts.sections, ", ")) or "")
  cli.notify(title .. project.name .. scope)
  -- Saving a file in Neovim makes the preview reload. Its output says how
  -- each reload went: a traceback and `✗ python` when the script fails,
  -- `✓ ready` when the scene is back.
  local pending = {}
  local id = {}
  local function set_status(state, detail)
    M.status[project.root] = { state = state, detail = detail, id = id }
  end
  set_status("starting")
  ---@type vim.SystemObj?
  local job
  job = cli.run(args, {
    cwd = project.root,
    key = key,
    env = cfg.preview.editor and { GAANIM_EDITOR = require("gaanim.remote").editor_command() } or nil,
    on_line = function(line)
      local label, text = line:match("^%s%s%S+%s+(%S+)%s*(.*)$")
      if label == "reload" or label == "watch" then
        pending = {}
        set_status(label == "reload" and "reloading" or "starting", text)
      elseif label == "ready" then
        pending = {}
        set_status("ready", text)
        local check = require("gaanim.check")
        if check.last[project.root] and check.last[project.root].status == "error" then
          check.run({ project = project, quiet = true })
        end
      elseif label == "python" and line:find("✗", 1, true) then
        local report = require("gaanim.check").parse(project, vim.list_extend({ "  ✗ python    " .. text }, pending))
        require("gaanim.check").publish(project, report)
        set_status("failed", report.summary)
        cli.notify("✗ " .. report.summary, vim.log.levels.ERROR)
        pending = {}
      else
        table.insert(pending, line)
      end
      vim.api.nvim_exec_autocmds("User", { pattern = "GaanimPreview", data = { root = project.root } })
    end,
    on_exit = function(code, lines)
      local last = M.status[project.root]
      if last and last.id == id then
        M.status[project.root] = nil
      end
      if launched[key] == signature and not cli.running(key) then
        launched[key] = nil
      end
      vim.api.nvim_exec_autocmds("User", { pattern = "GaanimPreview", data = { root = project.root } })
      if code == 0 or cli.was_stopped(job) then
        return
      end
      -- It never got ready: the output since the last reload says why.
      if last and last.id == id and last.state ~= "ready" then
        local since = {}
        for _, line in ipairs(lines) do
          if line:match("^%s%s%S+%s+ready%s") or line:match("^%s%s%S+%s+reload%s") then
            since = {}
          else
            table.insert(since, line)
          end
        end
        local report = require("gaanim.check").parse(project, since)
        if #report.items > 0 then
          require("gaanim.check").publish(project, report)
          cli.notify(("✗ %s (exit %d)"):format(report.items[1].text, code), vim.log.levels.ERROR)
          return
        end
      end
      cli.notify(("gaanim exited with %d; see :Gaanim log"):format(code), vim.log.levels.WARN)
    end,
  })
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
  cli.notify(any and ("Closed " .. project.name) or "Nothing running for this project")
end

---@param project gaanim.Project
---@return { preview: boolean, present: boolean }
function M.state(project)
  return { preview = cli.running("preview:" .. project.root), present = cli.running("present:" .. project.root) }
end

return M
