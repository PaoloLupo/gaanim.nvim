---@mod gaanim.cli Running the gaanim executable

local config = require("gaanim.config")

local M = {}

local LOG_MAX = 3000

---@type string[]
local log = {}
---@type integer?
local log_buf

---@type table<string, vim.SystemObj>
M.jobs = {}

---@param msg string
---@param level? integer
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Gaanim" })
end

---@param lines string[]
local function append(lines)
  vim.list_extend(log, lines)
  if #log > LOG_MAX then
    log = vim.list_slice(log, #log - LOG_MAX + 1)
  end
  if log_buf and vim.api.nvim_buf_is_valid(log_buf) then
    vim.bo[log_buf].modifiable = true
    vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, log)
    vim.bo[log_buf].modifiable = false
    for _, win in ipairs(vim.fn.win_findbuf(log_buf)) do
      vim.api.nvim_win_set_cursor(win, { #log, 0 })
    end
  end
end

--- Opens the output of every command run from Neovim.
function M.open_log()
  if not (log_buf and vim.api.nvim_buf_is_valid(log_buf)) then
    log_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(log_buf, "gaanim://log")
    vim.bo[log_buf].bufhidden = "hide"
    vim.bo[log_buf].filetype = "gaanimlog"
  end
  vim.bo[log_buf].modifiable = true
  vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, log)
  vim.bo[log_buf].modifiable = false
  local win = vim.fn.win_findbuf(log_buf)[1]
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("botright 12split")
    vim.api.nvim_win_set_buf(0, log_buf)
  end
  vim.api.nvim_win_set_cursor(0, { math.max(#log, 1), 0 })
end

--- The executable and its fixed arguments, resolved on PATH.
---@return string[]?
function M.executable()
  local cmd = config.get().cmd
  local list = type(cmd) == "table" and vim.deepcopy(cmd) or { cmd }
  local path = vim.fn.exepath(list[1])
  if path == "" then
    M.notify(("`%s` is not on PATH; set `cmd` in the gaanim.nvim options"):format(list[1]), vim.log.levels.ERROR)
    return nil
  end
  list[1] = path
  return list
end

--- Splits streamed output into lines; `\r` progress updates count as lines.
---@param on_line fun(line: string)
---@return fun(err: string?, data: string?)
local function line_reader(on_line)
  local pending = ""
  return function(_, data)
    if not data then
      if pending ~= "" then
        local rest = pending
        pending = ""
        vim.schedule(function()
          on_line(rest)
        end)
      end
      return
    end
    pending = pending .. data
    local lines = {}
    while true do
      local cut = pending:find("[\r\n]")
      if not cut then
        break
      end
      local line = pending:sub(1, cut - 1)
      pending = pending:sub(cut + 1)
      if line ~= "" then
        table.insert(lines, line)
      end
    end
    if #lines > 0 then
      vim.schedule(function()
        for _, line in ipairs(lines) do
          on_line(line)
        end
      end)
    end
  end
end

---@class gaanim.RunOpts
---@field cwd? string
---@field key? string Tracks the process under this key (one at a time per key)
---@field env? table<string, string> Added to the inherited environment
---@field on_line? fun(line: string)
---@field on_exit? fun(code: integer, lines: string[])

--- Runs `gaanim <args>` asynchronously. Output goes to the log and, line by
--- line, to `on_line`; `on_exit` gets the exit code and every line.
---@param args string[]
---@param opts? gaanim.RunOpts
---@return vim.SystemObj?
function M.run(args, opts)
  opts = opts or {}
  local cmd = M.executable()
  if not cmd then
    return nil
  end
  vim.list_extend(cmd, args)
  local lines = {}
  append({ "", "$ " .. table.concat(cmd, " ") })
  local function on_line(line)
    table.insert(lines, line)
    append({ line })
    if opts.on_line then
      opts.on_line(line)
    end
  end
  local reader = line_reader(on_line)
  ---@type vim.SystemObj?
  local job
  local function on_exit(result)
    vim.schedule(function()
      if opts.key and M.jobs[opts.key] == job then
        M.jobs[opts.key] = nil
      end
      append({ ("[exit %d]"):format(result.code) })
      if opts.on_exit then
        -- Let the last scheduled output lines land first.
        vim.schedule(function()
          opts.on_exit(result.code, lines)
        end)
      end
    end)
  end
  local ok, err = pcall(function()
    job = vim.system(cmd, {
      cwd = opts.cwd,
      env = vim.tbl_extend("force", { NO_COLOR = "1" }, opts.env or {}),
      text = true,
      stdout = reader,
      stderr = reader,
    }, on_exit)
  end)
  if not ok then
    M.notify("Could not start gaanim: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end
  if opts.key then
    M.jobs[opts.key] = job
  end
  return job
end

---@param key string
---@return boolean
function M.running(key)
  local job = M.jobs[key]
  return job ~= nil and not job:is_closing()
end

---@type table<vim.SystemObj, boolean> Processes closed on purpose
local stopped = setmetatable({}, { __mode = "k" })

---@param key string
function M.stop(key)
  local job = M.jobs[key]
  if job then
    M.jobs[key] = nil
    stopped[job] = true
    pcall(job.kill, job, "sigterm")
  end
end

--- Whether a process ended because `stop` closed it.
---@param job vim.SystemObj?
---@return boolean
function M.was_stopped(job)
  return job ~= nil and stopped[job] == true
end

function M.stop_all()
  for key in pairs(M.jobs) do
    M.stop(key)
  end
end

return M
