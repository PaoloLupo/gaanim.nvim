local M = {}

---@param cmd string[]
---@return string?
local function output(cmd)
  local ok, result = pcall(function()
    return vim.system(cmd, { text = true, env = { NO_COLOR = "1" } }):wait(10000)
  end)
  if not ok or result.code ~= 0 then
    return nil
  end
  return vim.trim((result.stdout or "") .. (result.stderr or ""))
end

function M.check()
  local health = vim.health
  health.start("gaanim.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10 or newer is required")
  end
  if vim.fn.has("nvim-0.12") ~= 1 then
    health.info("Neovim 0.12 shows exports as native progress messages; older versions use notifications")
  end

  local cmd = require("gaanim.config").get().cmd
  local exe = vim.fn.exepath(type(cmd) == "table" and cmd[1] or cmd)
  if exe == "" then
    health.error("`gaanim` is not on PATH", { "Install Gaanim or set `cmd` in the options" })
  else
    local version = output({ exe, "--version" })
    health.ok(("%s (%s)"):format(version or "gaanim", exe))
    local can = require("gaanim.caps").get()
    local function feature(on, name, what)
      if on then
        health.ok(name .. ": " .. what)
      else
        health.info(name .. " not available in this gaanim (`gaanim update` brings it): " .. what)
      end
    end
    feature(can.listen, "--listen", "move the preview from Neovim, follow the cursor, mark the playhead")
    feature(can.json, "--message-format json", "exact lines for diagnostics, export percent")
    feature(can.inspect, "inspect", "timeline with times, the instant of each line")
    feature(can.names, "export by name", "stills and ranges of the slide under the cursor")
    feature(
      can.project,
      "project",
      "workspaces: the shared .venv and src/ for completion, members, check and export of them all"
    )
    feature(can.init, "init JSON", "new members open as Gaanim made them; a folder `members` leaves out says so")
  end

  for _, tool in ipairs({ "ffmpeg", "ffprobe" }) do
    if vim.fn.executable(tool) == 1 then
      health.ok(tool .. " found")
    else
      health.warn(tool .. " not found", { "MP4, WebM, MOV, GIF and WebP exports and video clips need FFmpeg" })
    end
  end
  if vim.fn.executable("uv") == 1 then
    health.ok("uv found")
  else
    health.warn("uv not found", { "`gaanim init` uses uv to create the project's Python environment" })
  end

  local servers = vim.tbl_filter(function(exe)
    return vim.fn.executable(exe) == 1
  end, { "basedpyright-langserver", "pyright-langserver" })
  if #servers > 0 then
    health.ok(("%s found: it completes the Gaanim API from the project's .venv"):format(servers[1]))
  else
    health.warn("No Python language server (basedpyright or pyright)", {
      "Without one there is no completion or type checking of the Gaanim API",
      "In LazyVim, enable the lang.python extra (:LazyExtras)",
    })
  end

  local snacks = pcall(require, "snacks.picker")
  health.info(snacks and "Pickers: snacks.nvim" or "Pickers: vim.ui.select (install snacks.nvim for previews)")
  local server = vim.v.servername
  health.info(
    'Gaanim\'s "Open in the editor" reaches this Neovim at ' .. (server ~= "" and server or "(no server yet)")
  )

  M.workspace()

  health.start("gaanim.nvim: current project")
  local project = require("gaanim.project").current()
  if not project then
    health.info("No Gaanim project around the current buffer or directory")
    return
  end
  health.ok(("%s · %s · %s"):format(project.name, project.kind, project.root))
  if not vim.uv.fs_stat(project.entry) then
    health.error("Entry script missing: " .. project.entry)
  end
  local described = exe ~= ""
    and require("gaanim.caps").get().project
    and require("gaanim.workspace").describe(project.entry)
  local interpreter = described and described.python.interpreter
    or require("gaanim.lsp").fallback(project.root).interpreter
  if interpreter then
    health.ok("Python environment: " .. interpreter .. " (Python language servers get pointed at it)")
  elseif project.kind ~= "script" then
    health.warn(
      "No .venv for the project (nor its workspace)",
      { "Open the project with gaanim once, or run `gaanim init <kind> . --force`" }
    )
  end
  if described and #described.python.paths > 0 then
    health.info("sys.path: " .. table.concat(described.python.paths, ", "))
  end
  local docs = require("gaanim.docs").dir()
  if docs then
    health.ok("Bundled docs: " .. docs)
  else
    health.warn("No bundled docs found (`:Gaanim docs` needs them)")
  end
  local path, exists = require("gaanim.script").path(project)
  health.info(("Narration script: %s%s"):format(path or "?", exists and "" or " (not created yet)"))
end

--- The workspace around the current buffer: its members, any invalid one,
--- the shared folders and which member its shared modules run as.
function M.workspace()
  local health = vim.health
  local ws = require("gaanim.workspace")
  local name = vim.api.nvim_buf_get_name(0)
  local root = vim.fs.root(name ~= "" and name or (vim.uv.cwd() or "."), "gaanim.toml")
  root = root and vim.fs.normalize(root)
  local above = root and (ws.is_root(root) and root or ws.root_above(vim.fs.dirname(root)))
  if not above then
    return
  end
  health.start("gaanim.nvim: workspace")
  if not (require("gaanim.cli").available() and require("gaanim.caps").get().project) then
    health.warn("This gaanim cannot describe workspaces", { "`gaanim update` brings `gaanim project`" })
    return
  end
  local workspace = ws.current(0, { quiet = true })
  if not workspace then
    local _, err = ws.describe(above)
    health.error(err or ("Could not read the workspace in " .. above))
    return
  end
  local invalid = vim.tbl_filter(function(member)
    return member.error ~= nil
  end, workspace.members)
  health.ok(("%s · %d members · %s"):format(workspace.name, #workspace.members, workspace.root))
  for _, member in ipairs(invalid) do
    health.error(member.path .. ": " .. member.error)
  end
  if #workspace.members == 0 then
    health.warn("No members yet", { "`:Gaanim workspace new`, or list their folders in `members`" })
  end
  health.info("Shared Python: " .. (#workspace.python > 0 and table.concat(workspace.python, ", ") or "none"))
  health.info("Shared assets: " .. (#workspace.assets > 0 and table.concat(workspace.assets, ", ") or "none"))
  local active = ws.active[vim.fs.normalize(workspace.root)]
  local member = active and ws.member(workspace, active)
  health.info(
    member and ("Shared modules run as " .. ws.label(member))
      or "No active member yet: shared modules run as the member whose files you enter"
  )
end

return M
