---@mod gaanim.ui Pickers and prompts

local config = require("gaanim.config")

local M = {}

---@class gaanim.PickItem
---@field text string What the picker matches and shows
---@field hint? string Dimmed text after `text`
---@field icon? string
---@field hl? string Highlight of the icon
---@field file? string Previewed and jumped to
---@field lnum? integer
---@field col? integer
---@field value? any

---@return boolean
local function snacks_available()
  local choice = config.get().picker
  if choice == "select" then
    return false
  end
  local ok = pcall(require, "snacks.picker")
  return ok and _G.Snacks ~= nil and Snacks.picker ~= nil
end

--- Shows a list and calls `on_choice` with the picked item. Uses the snacks
--- picker (with a file preview) when it is installed, else `vim.ui.select`.
---@param items gaanim.PickItem[]
---@param opts { title: string, on_choice: fun(item: gaanim.PickItem) }
function M.pick(items, opts)
  if #items == 0 then
    vim.notify(opts.title .. ": nothing to show", vim.log.levels.INFO, { title = "Gaanim" })
    return
  end
  if snacks_available() then
    local has_files = items[1].file ~= nil
    Snacks.picker.pick({
      title = opts.title,
      items = vim.tbl_map(function(item)
        return {
          text = item.text .. (item.hint and (" " .. item.hint) or ""),
          file = item.file,
          pos = item.lnum and { item.lnum, (item.col or 1) - 1 } or nil,
          gaanim = item,
        }
      end, items),
      format = function(entry)
        local item = entry.gaanim
        local line = {}
        if item.icon then
          table.insert(line, { item.icon .. " ", item.hl or "Special" })
        end
        table.insert(line, { item.text })
        if item.hint then
          table.insert(line, { "  " .. item.hint, "Comment" })
        end
        return line
      end,
      preview = has_files and "file" or "none",
      layout = has_files and { preset = "default" } or { preset = "select" },
      sort = { fields = { "idx" } },
      matcher = { sort_empty = false },
      confirm = function(picker, entry)
        picker:close()
        if entry then
          vim.schedule(function()
            opts.on_choice(entry.gaanim)
          end)
        end
      end,
    })
    return
  end
  vim.ui.select(items, {
    prompt = opts.title,
    format_item = function(item)
      return (item.icon and (item.icon .. " ") or "") .. item.text .. (item.hint and ("  " .. item.hint) or "")
    end,
  }, function(item)
    if item then
      opts.on_choice(item)
    end
  end)
end

--- Opens a file at a line, reusing a window that already shows it.
---@param file string
---@param lnum? integer
---@param col? integer
function M.jump(file, lnum, col)
  local buf = vim.fn.bufnr(file)
  local win = buf ~= -1 and vim.fn.win_findbuf(buf)[1] or nil
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd.edit(vim.fn.fnameescape(file))
  end
  if lnum then
    local last = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { math.min(lnum, last), math.max((col or 1) - 1, 0) })
    vim.cmd("normal! zz")
  end
end

---@param prompt string
---@param default? string
---@param on_confirm fun(value: string)
function M.input(prompt, default, on_confirm)
  vim.ui.input({ prompt = prompt, default = default }, function(value)
    if value and vim.trim(value) ~= "" then
      on_confirm(vim.trim(value))
    end
  end)
end

--- A progress message: native in Neovim 0.12, a notification before.
---@param title string
---@return { update: fun(msg: string, percent?: integer), finish: fun(ok: boolean, msg: string) }
function M.progress(title)
  local native = vim.fn.has("nvim-0.12") == 1
  local id
  local function echo(msg, status, percent)
    if native then
      id = vim.api.nvim_echo({ { msg } }, status ~= "running", {
        id = id,
        kind = "progress",
        title = title,
        status = status,
        percent = percent,
        source = "gaanim",
      })
    elseif status ~= "running" or not id then
      id = true
      vim.notify(msg, status == "failed" and vim.log.levels.ERROR or vim.log.levels.INFO, { title = title })
    end
  end
  echo("starting", "running", 0)
  return {
    update = function(msg, percent)
      echo(msg, "running", percent)
    end,
    finish = function(ok, msg)
      echo(msg, ok and "success" or "failed", ok and 100 or nil)
    end,
  }
end

return M
