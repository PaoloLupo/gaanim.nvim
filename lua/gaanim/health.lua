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
  local venv = vim.fs.joinpath(project.root, ".venv")
  if vim.uv.fs_stat(venv) then
    health.ok(".venv found: Python language servers get pointed at it for completion")
  elseif project.kind ~= "script" then
    health.warn(
      "No .venv in the project",
      { "Open the project with gaanim once, or run `gaanim init <kind> . --force`" }
    )
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

return M
