if vim.g.loaded_gaanim then
  return
end
vim.g.loaded_gaanim = true

vim.api.nvim_create_user_command("Gaanim", function(opts)
  require("gaanim.commands").run(opts)
end, {
  nargs = "*",
  desc = "Gaanim: create, preview, check, export and present projects",
  complete = function(arglead, cmdline)
    return require("gaanim.commands").complete(arglead, cmdline)
  end,
})

---@param lhs string
---@param rhs function
---@param desc string
local function plug(lhs, rhs, desc)
  vim.keymap.set("n", "<Plug>(" .. lhs .. ")", rhs, { desc = desc })
end

local function cmd(line)
  return function()
    vim.cmd("Gaanim " .. line)
  end
end

plug("gaanim-new", cmd("new"), "Gaanim: new project")
plug("gaanim-projects", cmd("projects"), "Gaanim: open a project")
plug("gaanim-preview", cmd("preview"), "Gaanim: live preview")
plug("gaanim-preview-here", cmd("preview here"), "Gaanim: preview at the line under the cursor")
plug("gaanim-follow", cmd("follow"), "Gaanim: preview follows the cursor (toggle)")
plug("gaanim-play", cmd("play"), "Gaanim: play the preview")
plug("gaanim-pause", cmd("pause"), "Gaanim: pause the preview")
plug("gaanim-timeline", cmd("timeline"), "Gaanim: timeline")
plug("gaanim-live", cmd("live"), "Gaanim: live mode (toggle)")
plug("gaanim-loop", function()
  require("gaanim.preview").toggle_loop()
end, "Gaanim: loop the slide under the cursor (toggle)")
plug("gaanim-nudge-up", function()
  require("gaanim.nudge").nudge(1)
end, "Gaanim: increase the number under the cursor")
plug("gaanim-nudge-down", function()
  require("gaanim.nudge").nudge(-1)
end, "Gaanim: decrease the number under the cursor")
plug("gaanim-preview-only", cmd("preview only"), "Gaanim: preview only the slide under the cursor")
plug("gaanim-present", cmd("present"), "Gaanim: present")
plug("gaanim-present-here", cmd("present here"), "Gaanim: present from the line under the cursor")
plug("gaanim-stop", cmd("stop"), "Gaanim: close preview")
plug("gaanim-check", cmd("check"), "Gaanim: check")
plug("gaanim-export", cmd("export"), "Gaanim: export")
plug("gaanim-still", cmd("still"), "Gaanim: export the frame at the cursor")
plug("gaanim-outline", cmd("outline"), "Gaanim: outline")
plug("gaanim-script", cmd("script toggle"), "Gaanim: narration script")
plug("gaanim-script-goto", cmd("script goto"), "Gaanim: jump between script and scene")
plug("gaanim-docs", cmd("docs"), "Gaanim: documentation")
plug("gaanim-api", cmd("api"), "Gaanim: API entry of the word under the cursor")
plug("gaanim-log", cmd("log"), "Gaanim: command output")
plug("gaanim-next-slide", function()
  require("gaanim.outline").move(1)
end, "Gaanim: next segment")
plug("gaanim-prev-slide", function()
  require("gaanim.outline").move(-1)
end, "Gaanim: previous segment")
plug("gaanim-next-stop", function()
  require("gaanim.outline").move(1, { stop = true })
end, "Gaanim: next stop")
plug("gaanim-prev-stop", function()
  require("gaanim.outline").move(-1, { stop = true })
end, "Gaanim: previous stop")

local group = vim.api.nvim_create_augroup("gaanim", { clear = true })

local function highlights()
  vim.api.nvim_set_hl(0, "GaanimPlayhead", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "GaanimPlayheadText", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "GaanimPlaying", { link = "LspReferenceText", default = true })
end
highlights()
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })

-- A save in a project checks it once the saves settle; the check itself is
-- skipped when `check.on_save` is off.
vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = { "*.py", "*.md", "gaanim.toml" },
  callback = function(args)
    local root = vim.fs.root(args.buf, "gaanim.toml")
    if root then
      if package.loaded["gaanim.inspect"] then
        require("gaanim.inspect").invalidate(vim.fs.normalize(root))
      end
      require("gaanim.check").on_save(args.buf)
      if package.loaded["gaanim.server"] and args.file:match("%.py$") then
        local project = require("gaanim.project").current(args.buf)
        if project then
          require("gaanim.server").update(project)
        end
      end
    end
  end,
})

-- Once the script window has been opened, keep it on the slide under the
-- cursor and keep the spoken-time estimates fresh.
vim.api.nvim_create_autocmd("CursorMoved", {
  group = group,
  pattern = "*.py",
  callback = function()
    if package.loaded["gaanim.script"] then
      require("gaanim.script").follow()
    end
    if package.loaded["gaanim.preview"] then
      require("gaanim.preview").on_cursor()
    end
  end,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost", "InsertLeave" }, {
  group = group,
  pattern = "*.py",
  callback = function(args)
    if package.loaded["gaanim.script"] then
      require("gaanim.script").refresh(args.buf)
    end
  end,
})

-- The Gaanim language server, for the Python files of Gaanim projects.
local function attach(buf)
  if vim.bo[buf].filetype == "python" and vim.fs.root(buf, "gaanim.toml") then
    require("gaanim.server").attach(buf)
  end
end
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "python",
  callback = function(args)
    attach(args.buf)
  end,
})
-- Buffers opened before the plugin loaded (it loads lazily).
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then
    attach(buf)
  end
end

local asset_timer = vim.uv.new_timer()
vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave", "TextChanged" }, {
  group = group,
  pattern = "*.py",
  callback = function(args)
    if not package.loaded["gaanim.server"] then
      return
    end
    asset_timer:stop()
    asset_timer:start(300, 0, function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          require("gaanim.server.assets").publish(args.buf)
        end
      end)
    end)
  end,
})

-- Live mode writes changed project files once the changes settle.
vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
  group = group,
  pattern = { "*.py", "*.md", "gaanim.toml" },
  callback = function(args)
    if package.loaded["gaanim.live"] then
      require("gaanim.live").on_change(args.buf, false)
    end
  end,
})
vim.api.nvim_create_autocmd("TextChangedI", {
  group = group,
  pattern = { "*.py", "*.md" },
  callback = function(args)
    if package.loaded["gaanim.live"] then
      require("gaanim.live").on_change(args.buf, true)
    end
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(args)
    if require("gaanim.config").get().lsp then
      require("gaanim.lsp").attach(args.buf, args.data.client_id)
    end
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    if package.loaded["gaanim.cli"] and require("gaanim.config").get().preview.stop_on_exit then
      require("gaanim.cli").stop_all()
    end
  end,
})
