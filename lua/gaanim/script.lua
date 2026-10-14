---@mod gaanim.script The narration script beside the scene
---
--- Gaanim reads the talk's script from Markdown: each `## name` section is
--- the speaker notes of the segment of that name (ignoring case) or the text
--- of `scene.voiceover("name")`, and a `[stop]` / `[stop name]` line marks
--- where the speaker advances. `# Title` ends a section, `###` lines are
--- notes that are not read and HTML comments are ignored. This module keeps
--- that file next to the code: it opens the section of the slide under the
--- cursor, follows the cursor, adds missing sections and estimates how long
--- each section takes to say.

local cli = require("gaanim.cli")
local config = require("gaanim.config")
local index = require("gaanim.index")
local project_mod = require("gaanim.project")

local M = {}

M.ns = vim.api.nvim_create_namespace("gaanim.script")

--- The header Gaanim writes at the top of a new script.
M.HEADER = {
  "# Script",
  "",
  '<!-- Each "## name" is the script of the slide of that name',
  '     or the text of scene.voiceover("name"). A [stop] line marks where',
  "     you advance. Save the file and the scene updates. -->",
}

---@param seconds number
---@return string
function M.clock(seconds)
  seconds = math.floor(seconds + 0.5)
  if seconds >= 3600 then
    return ("%d:%02d:%02d"):format(seconds / 3600, (seconds % 3600) / 60, seconds % 60)
  end
  return ("%d:%02d"):format(seconds / 60, seconds % 60)
end

--- The stop a line marks: `false` when it is no mark, `""` for `[stop]`.
---@param line string
---@return string|false
function M.mark(line)
  local inner = vim.trim(line):match("^%[(.*)%]$")
  if not inner then
    return false
  end
  inner = vim.trim(inner)
  if inner:sub(1, 4):lower() ~= "stop" then
    return false
  end
  local rest = inner:sub(5)
  if rest ~= "" and not rest:match("^[%s:]") then
    return false
  end
  return vim.trim((rest:gsub("^%s*:", "")))
end

---@class gaanim.ScriptSection
---@field name string
---@field lnum integer Line of the `##` heading
---@field last integer Last line of the section
---@field words integer Words read aloud
---@field marks { name: string, lnum: integer }[]

---@class gaanim.Script
---@field title? integer Line of the `# Title`
---@field sections gaanim.ScriptSection[]

--- Reads the sections of a script the way Gaanim does.
---@param lines string[]
---@return gaanim.Script
function M.parse(lines)
  local script = { sections = {} }
  local current
  local in_comment = false
  local function close(lnum)
    if current then
      current.last = lnum
      current = nil
    end
  end
  for lnum, line in ipairs(lines) do
    -- Drop HTML comments, which may span lines.
    local text, rest = "", line
    while rest ~= "" do
      if in_comment then
        local finish = rest:find("-->", 1, true)
        if not finish then
          rest = ""
        else
          rest = rest:sub(finish + 3)
          in_comment = false
        end
      else
        local start = rest:find("<!--", 1, true)
        if not start then
          text, rest = text .. rest, ""
        else
          text = text .. rest:sub(1, start - 1)
          rest = rest:sub(start + 4)
          in_comment = true
        end
      end
    end
    text = vim.trim(text)
    -- Like Markdown, `#word` is text; a heading needs a space after its marks.
    local marks, after = text:match("^(#+)(.*)$")
    local level = (marks and (after == "" or after:match("^%s"))) and #marks or 0
    if level > 2 then
      -- Notes for the author, not read.
    elseif level == 2 then
      close(lnum - 1)
      local name = vim.trim(vim.trim(after):gsub("#+$", ""))
      current = { name = name, lnum = lnum, last = lnum, words = 0, marks = {} }
      table.insert(script.sections, current)
    elseif level == 1 then
      close(lnum - 1)
      script.title = script.title or lnum
    elseif current then
      local mark = M.mark(text)
      if mark then
        table.insert(current.marks, { name = mark, lnum = lnum })
      else
        for word in text:gmatch("%S+") do
          if word:find("[%w\128-\255]") then
            current.words = current.words + 1
          end
        end
      end
    end
  end
  close(#lines)
  -- A section ends at its last line with anything written on it.
  for _, section in ipairs(script.sections) do
    while section.last > section.lnum and vim.trim(lines[section.last] or "") == "" do
      section.last = section.last - 1
    end
  end
  return script
end

---@param script gaanim.Script
---@param name string
---@return gaanim.ScriptSection?
function M.find_section(script, name)
  name = name:lower()
  for _, section in ipairs(script.sections) do
    if section.name:lower() == name then
      return section
    end
  end
end

---@param path string
---@return string[]
local function read_lines(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  local file = io.open(path, "r")
  if not file then
    return {}
  end
  local lines = {}
  for line in file:lines() do
    table.insert(lines, (line:gsub("\r$", "")))
  end
  file:close()
  return lines
end

--- Line of the `## name` heading in a script file.
---@param path string
---@param name string
---@return integer?
function M.section_line(path, name)
  local section = M.find_section(M.parse(read_lines(path)), name)
  return section and section.lnum
end

--- The folder relative names resolve in: the asset directory when the scene
--- sets one, else the entry script's folder.
---@param project gaanim.Project
---@param symbols? gaanim.Symbol[]
---@return string
function M.base(project, symbols)
  for _, symbol in ipairs(symbols or index.project_symbols(project)) do
    if symbol.kind == "assets" then
      return symbol.name and vim.fs.joinpath(project.root, symbol.name) or project.assets_dir
    end
  end
  return vim.fs.dirname(project.entry)
end

local TAKE_EXTENSIONS = { "wav", "flac", "mp3", "m4a", "aac", "ogg", "opus" }

--- Whether the narration take of a voiceover key has been recorded.
---@param project gaanim.Project
---@param key string
---@return boolean
function M.has_take(project, key)
  local dir = vim.fs.joinpath(M.base(project), "narration")
  for _, ext in ipairs(TAKE_EXTENSIONS) do
    if vim.uv.fs_stat(vim.fs.joinpath(dir, key .. "." .. ext)) then
      return true
    end
  end
  return false
end

--- Where the project's script is, or would be. The second result tells
--- whether the file exists.
---@param project gaanim.Project
---@return string? path, boolean exists
function M.path(project)
  local configured = config.get().script.path
  local symbols = index.project_symbols(project)
  local base = M.base(project, symbols)
  local candidates = {}
  if configured then
    table.insert(candidates, vim.fs.joinpath(project.root, configured))
  end
  for _, symbol in ipairs(symbols) do
    if symbol.kind == "script" and symbol.name then
      local name = symbol.name
      if name:match("^%a:[/\\]") or name:match("^/") then
        table.insert(candidates, name)
      else
        table.insert(candidates, vim.fs.joinpath(base, name))
        table.insert(candidates, vim.fs.joinpath(project.root, name))
      end
    end
  end
  table.insert(candidates, vim.fs.joinpath(base, "narration", "script.md"))
  table.insert(candidates, vim.fs.joinpath(project.assets_dir, "narration", "script.md"))
  for _, path in ipairs(candidates) do
    path = vim.fs.normalize(path)
    if vim.uv.fs_stat(path) then
      return path, true
    end
  end
  return vim.fs.normalize(candidates[1]), false
end

---@return integer? win
local function script_window(path)
  local buf = vim.fn.bufnr(path)
  if buf == -1 then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

--- Opens the script in a window at the side, without leaving the code.
---@param project gaanim.Project
---@param focus? boolean
---@return integer? win, integer? buf
function M.open(project, focus)
  local path, exists = M.path(project)
  if not path then
    return nil
  end
  if not exists then
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local lines = vim.list_extend(vim.deepcopy(M.HEADER), { "" })
    vim.fn.writefile(lines, path)
    cli.notify("Created " .. vim.fn.fnamemodify(path, ":~:."))
  end
  local win = script_window(path)
  local from = vim.api.nvim_get_current_win()
  if not win then
    vim.cmd(("botright vertical %dsplit %s"):format(config.get().script.width, vim.fn.fnameescape(path)))
    win = vim.api.nvim_get_current_win()
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].winfixwidth = true
    if not focus then
      vim.api.nvim_set_current_win(from)
    end
  elseif focus then
    vim.api.nvim_set_current_win(win)
  end
  local buf = vim.api.nvim_win_get_buf(win)
  M.attach(project, buf)
  M.decorate(project)
  return win, buf
end

--- Scrolls the script window to a section, keeping the focus where it is.
---@param win integer
---@param lnum integer
function M.reveal(win, lnum)
  vim.api.nvim_win_call(win, function()
    vim.api.nvim_win_set_cursor(win, { lnum, 0 })
    vim.cmd("normal! zt")
  end)
end

--- Adds a `## name` section with a mark per stop, after the section of the
--- segment before it. Returns the heading line.
---@param project gaanim.Project
---@param buf integer Script buffer
---@param name string
---@return integer
function M.add_section(project, buf, name)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local script = M.parse(lines)
  local order, stops, current = {}, {}, nil
  for _, symbol in ipairs(index.project_symbols(project)) do
    if (symbol.kind == "segment" or symbol.kind == "section" or symbol.kind == "voiceover") and symbol.name then
      table.insert(order, symbol.name)
      current = symbol.name
    elseif symbol.kind == "stop" and current == name then
      table.insert(stops, symbol.name or "")
    end
  end
  local at = #lines
  for i = #order, 1, -1 do
    if order[i] == name then
      for j = i - 1, 1, -1 do
        local before = M.find_section(script, order[j])
        if before then
          at = before.last
          break
        end
      end
      break
    end
  end
  local block = { "", "## " .. name, "" }
  for _, stop in ipairs(stops) do
    vim.list_extend(block, { stop == "" and "[stop]" or ("[stop " .. stop .. "]"), "" })
  end
  if at == #lines and vim.trim(lines[#lines] or "") == "" then
    table.remove(block, 1)
  end
  if lines[at + 1] and vim.trim(lines[at + 1]) == "" then
    table.remove(block)
  end
  vim.api.nvim_buf_set_lines(buf, at, at, false, block)
  return at + (block[1] == "" and 2 or 1)
end

--- Seconds it takes to say `words`.
---@param words integer
---@return number
function M.spoken(words)
  return words / config.get().script.wpm * 60
end

---@param seconds number
---@param target? number
---@return string
local function pace_hl(seconds, target)
  if not target then
    return "Comment"
  end
  if seconds <= target then
    return "DiagnosticOk"
  elseif seconds <= target * 1.15 then
    return "DiagnosticWarn"
  end
  return "DiagnosticError"
end

---@param seconds number
---@param target? number
---@return string
local function pace_text(seconds, target)
  local text = "≈" .. M.clock(seconds)
  if target then
    text = text .. " / " .. M.clock(target)
  end
  return text
end

--- Shows, at each section and at each segment, how long its script takes to
--- say against the segment's `target=`.
---@param project gaanim.Project
function M.decorate(project)
  if not config.get().script.timing then
    return
  end
  local path, exists = M.path(project)
  if not (path and exists) then
    return
  end
  local script = M.parse(read_lines(path))
  local symbols = index.project_symbols(project)
  local targets, talk = {}, nil
  for _, symbol in ipairs(symbols) do
    if symbol.name and symbol.target and (symbol.kind == "segment" or symbol.kind == "section") then
      targets[symbol.name:lower()] = symbol.target
    elseif symbol.kind == "talk" and symbol.target then
      talk = symbol.target
    end
  end
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    local total = 0
    for _, section in ipairs(script.sections) do
      local seconds = M.spoken(section.words)
      total = total + seconds
      local target = targets[section.name:lower()]
      vim.api.nvim_buf_set_extmark(buf, M.ns, section.lnum - 1, 0, {
        virt_text = { { "  " .. pace_text(seconds, target), pace_hl(seconds, target) } },
        hl_mode = "combine",
      })
    end
    if script.title then
      vim.api.nvim_buf_set_extmark(buf, M.ns, script.title - 1, 0, {
        virt_text = { { "  talk " .. pace_text(total, talk), pace_hl(total, talk) } },
      })
    end
  end
  for _, file in ipairs(project_mod.python_files(project)) do
    local code = vim.fn.bufnr(file)
    if code ~= -1 and vim.api.nvim_buf_is_loaded(code) then
      vim.api.nvim_buf_clear_namespace(code, M.ns, 0, -1)
      for _, symbol in ipairs(index.buffer_symbols(code)) do
        if symbol.name and (symbol.kind == "segment" or symbol.kind == "section" or symbol.kind == "voiceover") then
          local section = M.find_section(script, symbol.name)
          local chunks = {}
          if section then
            local seconds = M.spoken(section.words)
            table.insert(chunks, { "  ♪ " .. pace_text(seconds, symbol.target), pace_hl(seconds, symbol.target) })
          elseif symbol.kind ~= "section" then
            table.insert(chunks, { "  ♪ no script", "Comment" })
          end
          if symbol.kind == "voiceover" then
            local recorded = M.has_take(project, symbol.name)
            table.insert(
              chunks,
              { recorded and "  ● take" or "  ○ no take", recorded and "DiagnosticOk" or "Comment" }
            )
          end
          if #chunks > 0 then
            vim.api.nvim_buf_set_extmark(code, M.ns, symbol.lnum - 1, 0, { virt_text = chunks })
          end
        end
      end
    end
  end
end

--- Decorates the project of a code buffer, once its script exists.
---@param buf integer
function M.refresh(buf)
  local project = project_mod.current(buf)
  if project then
    M.decorate(project)
  end
end

---@type table<integer, boolean>
local attached = {}

--- Keeps the decorations of a script buffer up to date while it is edited.
---@param project gaanim.Project
---@param buf integer
function M.attach(project, buf)
  if attached[buf] then
    return
  end
  attached[buf] = true
  local group = vim.api.nvim_create_augroup("gaanim.script." .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = group,
    buffer = buf,
    callback = function()
      M.decorate(project)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      attached[buf] = nil
    end,
  })
end

---@type table<integer, string> Section each code window last showed
local followed = {}

--- Scrolls the script window to the section of the slide under the cursor.
function M.follow()
  if not config.get().script.follow then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "python" then
    return
  end
  local project = project_mod.current(buf)
  if not project then
    return
  end
  local path, exists = M.path(project)
  local win = exists and path and script_window(path)
  if not win then
    return
  end
  local here = index.at_cursor(buf)
  local name = here.segment and here.segment.name
  local code_win = vim.api.nvim_get_current_win()
  if not name or followed[code_win] == name then
    return
  end
  followed[code_win] = name
  local script_buf = vim.api.nvim_win_get_buf(win)
  local section = M.find_section(M.parse(vim.api.nvim_buf_get_lines(script_buf, 0, -1, false)), name)
  if section then
    local lnum = section.lnum
    local mark = section.marks[here.stop_index]
    if mark then
      lnum = mark.lnum
    end
    M.reveal(win, lnum)
  end
end

--- Jumps between a slide's code and its section: from the code to the
--- section (adding it when missing), from the script to the segment or to
--- the stop of the mark under the cursor.
---@param project gaanim.Project
function M.jump(project)
  local buf = vim.api.nvim_get_current_buf()
  local path = M.path(project)
  if path and vim.fs.normalize(vim.api.nvim_buf_get_name(buf)) == path then
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local script = M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local section
    for _, s in ipairs(script.sections) do
      if s.lnum <= lnum then
        section = s
      end
    end
    if not section then
      cli.notify("The cursor is in no section", vim.log.levels.WARN)
      return
    end
    local target = index.find(project, section.name)
    if not target then
      for _, symbol in ipairs(index.project_symbols(project)) do
        if symbol.name and symbol.name:lower() == section.name:lower() then
          target = symbol
          break
        end
      end
    end
    if not target then
      cli.notify(("No segment or voiceover named %q"):format(section.name), vim.log.levels.WARN)
      return
    end
    -- On a mark line: the matching stop after the segment.
    local mark_index
    for i, mark in ipairs(section.marks) do
      if mark.lnum <= lnum then
        mark_index = i
      end
    end
    local destination = target
    if mark_index then
      local count = 0
      for _, symbol in ipairs(index.file_symbols(target.file)) do
        if symbol.lnum > target.lnum then
          if symbol.kind == "segment" or symbol.kind == "section" or symbol.kind == "voiceover" then
            break
          end
          if symbol.kind == "stop" then
            count = count + 1
            if count == mark_index then
              destination = symbol
              break
            end
          end
        end
      end
    end
    require("gaanim.ui").jump(destination.file, destination.lnum, destination.col)
    return
  end
  local here = index.at_cursor(buf)
  if not (here.segment and here.segment.name) then
    cli.notify("No segment or voiceover above the cursor", vim.log.levels.WARN)
    return
  end
  local win, script_buf = M.open(project, true)
  if not (win and script_buf) then
    return
  end
  local script = M.parse(vim.api.nvim_buf_get_lines(script_buf, 0, -1, false))
  local section = M.find_section(script, here.segment.name)
  local lnum
  if section then
    lnum = (section.marks[here.stop_index] or section).lnum
  else
    lnum = M.add_section(project, script_buf, here.segment.name)
    cli.notify("Added the section of " .. here.segment.name)
  end
  vim.api.nvim_win_set_cursor(win, { lnum, 0 })
  vim.cmd("normal! zt")
  if not section then
    vim.api.nvim_win_set_cursor(win, { math.min(lnum + 2, vim.api.nvim_buf_line_count(script_buf)), 0 })
  end
end

---@param action "open"|"toggle"|"goto"
function M.command(action)
  local project = project_mod.require()
  if not project then
    return
  end
  if action == "goto" then
    M.jump(project)
  elseif action == "open" then
    M.open(project, true)
  else
    local path = M.path(project)
    local win = path and script_window(path)
    if win then
      vim.api.nvim_win_close(win, false)
    else
      M.open(project, false)
      followed = {}
      M.follow()
    end
  end
end

return M
