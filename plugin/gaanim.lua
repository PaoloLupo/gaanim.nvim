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
plug("gaanim-preview-here", cmd("preview here"), "Gaanim: preview from the slide under the cursor")
plug("gaanim-preview-only", cmd("preview only"), "Gaanim: preview only the slide under the cursor")
plug("gaanim-present", cmd("present"), "Gaanim: present")
plug("gaanim-present-here", cmd("present here"), "Gaanim: present from the slide under the cursor")
plug("gaanim-stop", cmd("stop"), "Gaanim: close preview")
plug("gaanim-check", cmd("check"), "Gaanim: check")
plug("gaanim-export", cmd("export"), "Gaanim: export")
plug("gaanim-still", cmd("still"), "Gaanim: export a still")
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

-- A save in a project checks it once the saves settle; the check itself is
-- skipped when `check.on_save` is off.
vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = { "*.py", "*.md", "gaanim.toml" },
  callback = function(args)
    if vim.fs.root(args.buf, "gaanim.toml") then
      require("gaanim.check").on_save(args.buf)
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
