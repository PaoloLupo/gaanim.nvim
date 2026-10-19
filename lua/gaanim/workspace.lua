---@mod gaanim.workspace Workspaces: projects that share code, assets and Python
---
--- A `gaanim.toml` with a `[workspace]` table makes its folder a workspace:
--- its `members` are projects that share the Python folders and assets of
--- `[workspace.shared]` (`src/` and `assets/` by default) and one `.venv` at
--- the root. `gaanim project <PATH> --json` says, without running Python,
--- what a file belongs to: its project, its workspace and every member, the
--- folders its scripts find on `sys.path` and the interpreter. The plugin
--- asks it in the background and keeps each answer until a `gaanim.toml` is
--- written.
---
--- The workspace's own files (a shared module in `src/`) run as part of a
--- member: the one whose files were entered last, its active member.

local M = {}

---@class gaanim.Member
---@field path string Folder relative to the workspace, with `/`
---@field name string
---@field group string Its `members` entry's group, else its parent folder
---@field root string
---@field kind? "video"|"slides" Nil when its manifest is invalid
---@field entry? string
---@field error? string Why its manifest cannot be read

---@class gaanim.Workspace
---@field name string
---@field root string
---@field manifest string
---@field cover? string
---@field python string[] Shared Python folders
---@field assets string[] Shared asset folders
---@field members gaanim.Member[]

---@class gaanim.DescribedProject
---@field name string
---@field display_name string `channel › intro` in a workspace
---@field kind "video"|"slides"
---@field root string
---@field manifest string
---@field entry string
---@field assets_dir string
---@field output_dir string
---@field language? string

---@class gaanim.Description What `gaanim project --json` says of a path
---@field path string
---@field project? gaanim.DescribedProject
---@field workspace? gaanim.Workspace
---@field python { paths: string[], venv?: string, interpreter?: string }

local windows = vim.fn.has("win32") == 1

--- A path as the plugin writes it: `/`-separated, without Windows' `\\?\`.
---@param path any
---@return string?
local function plain(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return vim.fs.normalize((path:gsub("^\\\\%?\\", "")))
end

--- A path in the form two paths compare in.
---@param path string
---@return string
local function comparable(path)
  path = vim.fs.normalize(path)
  return windows and path:lower() or path
end

---@param a string?
---@param b string?
---@return boolean
function M.same(a, b)
  return a ~= nil and b ~= nil and comparable(a) == comparable(b)
end

--- Whether `path` is `folder` or lies inside it.
---@param path string
---@param folder string
---@return boolean
function M.within(path, folder)
  local p, f = comparable(path), comparable(folder):gsub("/$", "")
  return p == f or p:sub(1, #f + 1) == f .. "/"
end

---@param list any[]
---@param fn fun(value: any): any
---@return any[]
local function map(list, fn)
  local out = {}
  for _, value in ipairs(type(list) == "table" and list or {}) do
    local mapped = fn(value)
    if mapped ~= nil then
      table.insert(out, mapped)
    end
  end
  return out
end

-- Manifests -----------------------------------------------------------------

---@class gaanim.ManifestInfo
---@field project boolean It names a project: `kind` or `entry` at the top
---@field workspace boolean It has a `[workspace]` table
---@field name? string
---@field python? string[] `[workspace.shared]` python, as written
---@field assets? string[] `[workspace.shared]` assets, as written

---@type table<string, { stamp: string, info: gaanim.ManifestInfo }>
local manifests = {}

--- The quoted strings of a TOML value, in order.
---@param value string
---@return string[]
local function strings(value)
  local found = {}
  for _, text in value:gmatch("([\"'])(.-)%1") do
    table.insert(found, text)
  end
  return found
end

--- What the `gaanim.toml` in `root` declares, read in Lua so autocommands
--- and statuslines can ask: nil when there is none.
---@param root string
---@return gaanim.ManifestInfo?
function M.manifest(root)
  local path = vim.fs.joinpath(root, "gaanim.toml")
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then
    return nil
  end
  local stamp = ("%d:%d:%d"):format(stat.mtime.sec, stat.mtime.nsec or 0, stat.size)
  local cached = manifests[path]
  if cached and cached.stamp == stamp then
    return cached.info
  end
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a") or ""
  file:close()
  ---@type gaanim.ManifestInfo
  local info = { project = false, workspace = false }
  local section, key, pending
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    line = line:gsub("^%s+", ""):gsub("%s#[^\"']*$", "")
    if pending then
      -- An array that goes on over several lines.
      pending = pending .. " " .. line
      if line:find("]", 1, true) then
        info[key] = strings(pending)
        pending = nil
      end
    else
      local header = line:match("^%[%s*([%w_%.%-]+)%s*%]")
      if header then
        section = header
        if header == "workspace" or vim.startswith(header, "workspace.") then
          info.workspace = true
        end
      elseif not section then
        if line:match("^kind%s*=") or line:match("^entry%s*=") then
          info.project = true
        end
        info.name = info.name or line:match("^name%s*=%s*[\"'](.-)[\"']")
      elseif section == "workspace.shared" then
        local name, value = line:match("^(%w+)%s*=%s*(.*)$")
        if name == "python" or name == "assets" then
          if value:find("[", 1, true) and not value:find("]", 1, true) then
            key, pending = name, value
          else
            info[name] = strings(value)
          end
        end
      end
    end
  end
  manifests[path] = { stamp = stamp, info = info }
  return info
end

--- Whether the folder holds a workspace's manifest that names no project
--- of its own, so its files belong to the workspace itself.
---@param root string
---@return boolean
function M.is_root(root)
  local info = M.manifest(root)
  return info ~= nil and info.workspace and not info.project
end

--- The nearest workspace at or above `folder`: the first folder with a
--- `gaanim.toml` that has a `[workspace]` table, looking up to the folder
--- that holds `.git`.
---@param folder string
---@return string?
function M.root_above(folder)
  local dir = vim.fs.normalize(folder)
  for _ = 1, 64 do
    local info = M.manifest(dir)
    if info and info.workspace then
      return dir
    end
    if vim.uv.fs_stat(vim.fs.joinpath(dir, ".git")) then
      return nil
    end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir or parent == "." then
      return nil
    end
    dir = parent
  end
end

-- What `gaanim project` says ------------------------------------------------

---@type table<string, { description?: gaanim.Description, error?: string, waiting?: fun(d?: gaanim.Description, err?: string)[] }>
local described = {}

---@type table<string, gaanim.Workspace> The workspaces described, by root
M.workspaces = {}

---@type table<string, string|false> Of each project described: its workspace's root, or false
local member_of = {}

--- The cache key of a path: a folder, or the folder of a file, which is all
--- the answer depends on.
---@param path string
---@return string
local function key_of(path)
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "directory" then
    return comparable(path)
  end
  return comparable(vim.fs.dirname(path)) .. "/*"
end

---@param member table
---@return gaanim.Member
local function decode_member(member)
  local error = type(member.error) == "string" and member.error:gsub("\\\\%?\\", "") or nil
  return {
    path = member.path,
    name = member.name or member.path,
    group = member.group or "",
    root = plain(member.root),
    kind = member.kind,
    entry = plain(member.entry),
    error = error,
  }
end

--- Turns the JSON of `gaanim project --json` into a description, with every
--- path written the plugin's way.
---@param object table
---@return gaanim.Description
function M.decode(object)
  local python = type(object.python) == "table" and object.python or {}
  ---@type gaanim.Description
  local description = {
    path = plain(object.path),
    python = {
      paths = map(python.paths, plain),
      venv = plain(python.venv),
      interpreter = plain(python.interpreter),
    },
  }
  local project = object.project
  if type(project) == "table" then
    description.project = {
      name = project.name,
      display_name = project.display_name or project.name,
      kind = project.kind,
      root = plain(project.root),
      manifest = plain(project.manifest),
      entry = plain(project.entry),
      assets_dir = plain(project.assets_dir),
      output_dir = plain(project.output_dir),
      language = project.language,
    }
  end
  local workspace = object.workspace
  if type(workspace) == "table" then
    description.workspace = {
      name = workspace.name,
      root = plain(workspace.root),
      manifest = plain(workspace.manifest),
      cover = plain(workspace.cover),
      python = map(workspace.python, plain),
      assets = map(workspace.assets, plain),
      members = map(workspace.members, decode_member),
    }
  end
  return description
end

--- Keeps what a description tells about workspaces and their members.
---@param description gaanim.Description
function M.remember(description)
  local workspace = description.workspace
  if workspace then
    M.workspaces[comparable(workspace.root)] = workspace
    for _, member in ipairs(workspace.members) do
      member_of[comparable(member.root)] = workspace.root
    end
  end
  if description.project then
    member_of[comparable(description.project.root)] = workspace and workspace.root or false
  end
end

--- The description in a finished `gaanim project`, or why there is none.
---@param result vim.SystemCompleted
---@return gaanim.Description?, string?
local function parse(result)
  if result.code == 0 then
    local ok, object = pcall(vim.json.decode, result.stdout or "", { luanil = { object = true, array = true } })
    if ok and type(object) == "table" then
      local description = M.decode(object)
      M.remember(description)
      return description
    end
    return nil, "gaanim project printed no JSON"
  end
  local text = vim.trim((result.stderr or "") .. "\n" .. (result.stdout or ""))
  text = text:match("✗%s+%S+%s+(.-)%s*$") or text
  return nil, (text:gsub("\\\\%?\\", ""))
end

---@param path string
---@return string[]
local function command(path)
  return vim.list_extend(require("gaanim.cli").executable() or {}, { "project", path, "--json" })
end

local NO_PROJECT = "this gaanim cannot describe workspaces: `gaanim project` comes with `gaanim update`"

--- What `gaanim project` says of `path`, a file or a folder. With `on_done`
--- it runs in the background (and answers at once when the answer is
--- known); without, it waits for the answer. Nil, with the reason, when the
--- installed gaanim has no `gaanim project` or the manifest above is invalid.
---@param path string
---@param on_done? fun(description?: gaanim.Description, err?: string)
---@return gaanim.Description?, string?
function M.describe(path, on_done)
  path = vim.fs.normalize(path)
  local key = key_of(path)
  local entry = described[key]
  if entry and not entry.waiting then
    if on_done then
      on_done(entry.description, entry.error)
    end
    return entry.description, entry.error
  end
  ---@param description? gaanim.Description
  ---@param err? string
  local function finish(running, description, err)
    if described[key] == running then
      described[key] = { description = description, error = err }
    end
    local waiting = running.waiting or {}
    running.waiting = nil
    for _, callback in ipairs(waiting) do
      callback(description, err)
    end
    vim.api.nvim_exec_autocmds("User", { pattern = "GaanimWorkspace", data = { path = path } })
  end
  if on_done then
    if entry then
      table.insert(entry.waiting, on_done)
      return nil
    end
    local running = { waiting = { on_done } }
    described[key] = running
    require("gaanim.caps").load(function(can)
      if not can.project then
        finish(running, nil, NO_PROJECT)
        return
      end
      local ok = pcall(vim.system, command(path), { text = true, env = { NO_COLOR = "1" } }, function(result)
        vim.schedule(function()
          finish(running, parse(result))
        end)
      end)
      if not ok then
        finish(running, nil, "could not run gaanim project")
      end
    end)
    return nil
  end
  if not (require("gaanim.cli").available() and require("gaanim.caps").get().project) then
    return nil, NO_PROJECT
  end
  local ok, result = pcall(function()
    return vim.system(command(path), { text = true, env = { NO_COLOR = "1" } }):wait(10000)
  end)
  local description, err
  if ok and result then
    description, err = parse(result)
  else
    err = "could not run gaanim project"
  end
  if entry then
    finish(entry, description, err)
  else
    described[key] = { description = description, error = err }
  end
  return description, err
end

--- Forgets every answer, after a manifest changes or a member is created.
function M.invalidate()
  described, member_of, manifests = {}, {}, {}
  M.workspaces = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.b[buf].gaanim_root = nil
      vim.b[buf].gaanim_workspace = nil
    end
  end
end

--- The workspace a project is a member of, as last described; nil when it
--- is not one or that is not known yet (it is asked in the background).
---@param project gaanim.Project
---@return gaanim.Workspace?
function M.of(project)
  local root = member_of[comparable(project.root)]
  if root then
    return M.workspaces[comparable(root)]
  end
  if root == nil and project.kind ~= "script" and M.root_above(vim.fs.dirname(project.root)) then
    M.describe(project.entry, function() end)
  end
end

--- The absolute shared folders of the workspace at `root` under `key`
--- ("python" or "assets"): as described, else as its manifest lists them,
--- else its `src/` or `assets/` when it exists.
---@param root string
---@param key "python"|"assets"
---@return string[]
function M.shared(root, key)
  local workspace = M.workspaces[comparable(root)]
  if workspace then
    return workspace[key]
  end
  local info = M.manifest(root) or {}
  local listed = info[key] or { key == "python" and "src" or "assets" }
  local folders = {}
  for _, name in ipairs(listed) do
    local folder = vim.fs.normalize(vim.fs.joinpath(root, name))
    local stat = vim.uv.fs_stat(folder)
    if stat and stat.type == "directory" then
      table.insert(folders, folder)
    end
  end
  return folders
end

--- Whether `file` lies in one of the shared Python folders of the
--- workspace at `root`: a module its members import.
---@param root string
---@param file string
---@return boolean
function M.is_shared(root, file)
  for _, folder in ipairs(M.shared(root, "python")) do
    if M.within(file, folder) then
      return true
    end
  end
  return false
end

--- The shared asset folders a project finds files in after its own: its
--- workspace's, when it is a member of one.
---@param project gaanim.Project
---@return string[]
function M.shared_assets(project)
  local workspace = M.of(project)
  if workspace then
    return workspace.assets
  end
  if member_of[comparable(project.root)] == false or project.kind == "script" then
    return {}
  end
  -- Not described yet: the workspace above, as its manifest says.
  local root = M.root_above(vim.fs.dirname(project.root))
  return root and M.shared(root, "assets") or {}
end

-- The active member ----------------------------------------------------------

---@type table<string, string> The member each workspace's own files run as, by workspace root
M.active = {}

--- Makes the member at `member` the one the workspace's own files run as.
---@param root string Workspace root
---@param member string Member root
function M.use(root, member)
  root, member = vim.fs.normalize(root), vim.fs.normalize(member)
  if M.active[root] == member then
    return
  end
  M.active[root] = member
  vim.api.nvim_exec_autocmds("User", { pattern = "GaanimMember", data = { workspace = root, root = member } })
end

--- Called when a buffer is entered: a member's file makes that member the
--- active one, and what `gaanim project` says of the file is fetched for
--- completion and assets.
---@param buf integer
function M.on_enter(buf)
  if vim.b[buf].gaanim_workspace == false or vim.bo[buf].buftype ~= "" then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local root = name ~= "" and vim.fs.root(buf, "gaanim.toml")
  if not root then
    vim.b[buf].gaanim_workspace = false
    return
  end
  root = vim.fs.normalize(root)
  local workspace = M.is_root(root) and root or M.root_above(vim.fs.dirname(root))
  vim.b[buf].gaanim_workspace = workspace or false
  if not workspace then
    return
  end
  if workspace == root then
    M.describe(name, function() end)
    return
  end
  local known = member_of[comparable(root)]
  if known then
    M.use(known, root)
  elseif known == nil then
    M.describe(name, function(description)
      local project = description and description.project
      if project and description.workspace and M.same(project.root, root) then
        M.use(description.workspace.root, root)
      end
    end)
  end
end

-- Members --------------------------------------------------------------------

---@param pattern string
---@param name string
---@return boolean
local function wildcard(pattern, name)
  if windows then
    pattern, name = pattern:lower(), name:lower()
  end
  local lua = "^" .. pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
  return name:match(lua) ~= nil
end

--- Whether a member path matches a pattern written like `members`, where
--- `*` stands for any run of characters within a folder name.
---@param pattern string
---@param path string
---@return boolean
function M.matches(pattern, path)
  local wanted = vim.split(vim.trim(pattern):gsub("^%./", ""):gsub("/+$", ""), "/", { plain = true })
  local parts = vim.split(path, "/", { plain = true })
  if #wanted ~= #parts then
    return false
  end
  for i, part in ipairs(parts) do
    if not wildcard(wanted[i], part) then
      return false
    end
  end
  return true
end

--- The members `patterns` names (comma-separated paths or patterns, as
--- `--members` takes them), or every member.
---@param workspace gaanim.Workspace
---@param patterns? string
---@return gaanim.Member[]
function M.select(workspace, patterns)
  if not patterns or vim.trim(patterns) == "" then
    return workspace.members
  end
  local list = vim.split(patterns, ",", { trimempty = true })
  return vim.tbl_filter(function(member)
    for _, pattern in ipairs(list) do
      if M.matches(pattern, member.path) then
        return true
      end
    end
    return false
  end, workspace.members)
end

--- The member whose folder holds `path`.
---@param workspace gaanim.Workspace
---@param path string
---@return gaanim.Member?
function M.member_at(workspace, path)
  for _, member in ipairs(workspace.members) do
    if M.within(path, member.root) then
      return member
    end
  end
end

--- The member at a path relative to the workspace, or at a root.
---@param workspace gaanim.Workspace
---@param path string
---@return gaanim.Member?
function M.member(workspace, path)
  for _, member in ipairs(workspace.members) do
    if member.path == path or M.same(member.root, path) then
      return member
    end
  end
end

--- `1 member`, `3 members`.
---@param count integer
---@return string
function M.count(count)
  return count == 1 and "1 member" or (count .. " members")
end

--- How a member is named in lists: `group › name`.
---@param member gaanim.Member
---@return string
function M.label(member)
  return member.group ~= "" and (member.group .. " › " .. member.name) or member.name
end

--- The workspace of a buffer (or of the current directory): the one it is a
--- member of, or whose own folders it is in, described afresh (members may
--- have come or gone) unless `cached`. Tells the user when there is none,
--- unless `quiet`.
---@param buf? integer
---@param opts? { quiet?: boolean, cached?: boolean }
---@return gaanim.Workspace?
function M.current(buf, opts)
  buf, opts = buf or 0, opts or {}
  local quiet = opts.quiet
  local name = vim.api.nvim_buf_get_name(buf)
  local start = name ~= "" and vim.bo[buf].buftype == "" and name or (vim.uv.cwd() or ".")
  local function say(msg)
    if not quiet then
      vim.notify(msg, vim.log.levels.WARN, { title = "Gaanim" })
    end
  end
  local root = vim.fs.root(start, "gaanim.toml")
  root = root and vim.fs.normalize(root)
  local above = root and (M.is_root(root) and root or M.root_above(vim.fs.dirname(root)))
  if not above then
    say("No Gaanim workspace here (no gaanim.toml with [workspace] above this file)")
    return nil
  end
  if not opts.cached then
    described[key_of(vim.fs.normalize(start))] = nil
  end
  local description, err = M.describe(start)
  if description and description.workspace then
    return description.workspace
  end
  if not err then
    -- A project in the workspace's folder that its `members` leaves out.
    if not opts.cached then
      described[key_of(above)] = nil
    end
    description, err = M.describe(above)
    if description and description.workspace then
      return description.workspace
    end
  end
  say(err or "No Gaanim workspace here")
end

--- The project of a member, as the rest of the plugin works with it.
---@param member gaanim.Member
---@return gaanim.Project?
function M.project(member)
  return member.root and require("gaanim.project").load(member.root) or nil
end

--- Opens a member: it becomes the active one, the editor enters the
--- workspace and its entry script opens (its manifest when it is invalid).
---@param workspace gaanim.Workspace
---@param member gaanim.Member
function M.open(workspace, member)
  if not member.error then
    M.use(workspace.root, member.root)
  end
  require("gaanim.project").enter(workspace.root)
  vim.cmd.edit(vim.fn.fnameescape(member.entry or vim.fs.joinpath(member.root, "gaanim.toml")))
end

---@class gaanim.MemberPickOpts
---@field title? string
---@field on_choice fun(member: gaanim.Member)
---@field actions? boolean Also offer to add a member, check and export them all
---@field valid? boolean Only members whose manifest reads

--- Picks a member, grouped as the manifest says, with invalid ones in red.
---@param workspace gaanim.Workspace
---@param opts gaanim.MemberPickOpts
function M.pick(workspace, opts)
  local icons = require("gaanim.icons").get()
  local active = M.active[vim.fs.normalize(workspace.root)]
  local items = {}
  for _, member in ipairs(workspace.members) do
    if not (opts.valid and member.error) then
      local hint = member.path
      if member.error then
        hint = hint .. "  " .. member.error
      elseif M.same(active, member.root) then
        hint = hint .. "  (active)"
      end
      table.insert(items, {
        text = M.label(member),
        hint = hint,
        icon = member.error and icons.failed or icons[member.kind] or icons.video,
        hl = member.error and "DiagnosticError" or nil,
        file = member.entry or vim.fs.joinpath(member.root, "gaanim.toml"),
        lnum = 1,
        value = member,
      })
    end
  end
  if opts.actions then
    local function action(text, hint, icon, run)
      table.insert(items, { text = text, hint = hint, icon = icon, file = workspace.manifest, lnum = 1, value = run })
    end
    action("New video…", "add a video member", icons.video, function()
      require("gaanim.new").member(workspace, "video")
    end)
    action("New presentation…", "add a slides member", icons.slides, function()
      require("gaanim.new").member(workspace, "slides")
    end)
    if #workspace.members > 0 then
      action("Check all", "gaanim check on every member", "✓", function()
        require("gaanim.check").workspace(workspace)
      end)
      action(
        "Export all…",
        "each member to " .. require("gaanim.config").get().workspace.output,
        icons.still,
        function()
          require("gaanim.export").workspace(workspace)
        end
      )
    end
  end
  require("gaanim.ui").pick(items, {
    title = opts.title or (workspace.name .. " · " .. M.count(#workspace.members)),
    on_choice = function(item)
      if type(item.value) == "function" then
        item.value()
      else
        opts.on_choice(item.value)
      end
    end,
  })
end

--- Opens the workspace at `root`: its only member, or one picked.
---@param root string
function M.open_root(root)
  local description, err = M.describe(root)
  local workspace = description and description.workspace
  if not workspace then
    require("gaanim.cli").notify(err or ("No workspace in " .. root), vim.log.levels.ERROR)
    return
  end
  local valid = vim.tbl_filter(function(member)
    return not member.error
  end, workspace.members)
  if #workspace.members == 0 then
    require("gaanim.project").enter(workspace.root)
    vim.cmd.edit(vim.fn.fnameescape(workspace.manifest))
    require("gaanim.cli").notify(workspace.name .. " has no members yet: :Gaanim workspace new")
  elseif #valid == 1 and #workspace.members == 1 then
    M.open(workspace, valid[1])
  else
    M.pick(workspace, {
      actions = true,
      on_choice = function(member)
        M.open(workspace, member)
      end,
    })
  end
end

--- For a workspace's own file when no member is active: the only member,
--- or one picked, which becomes the active one. `retry` runs once it is
--- picked (the command that asked).
---@param root string Workspace root
---@param retry? fun()
---@return gaanim.Project?
function M.choose(root, retry)
  local description, err = M.describe(root)
  local workspace = description and description.workspace
  if not workspace then
    require("gaanim.cli").notify(err or ("No workspace in " .. root), vim.log.levels.WARN)
    return nil
  end
  local valid = vim.tbl_filter(function(member)
    return not member.error
  end, workspace.members)
  if #valid == 0 then
    require("gaanim.cli").notify(
      ("%s has no members to run yet: :Gaanim workspace new"):format(workspace.name),
      vim.log.levels.WARN
    )
    return nil
  end
  if #valid == 1 then
    M.use(workspace.root, valid[1].root)
    return M.project(valid[1])
  end
  M.pick(workspace, {
    title = "Shared files of " .. workspace.name .. " run as",
    valid = true,
    on_choice = function(member)
      M.use(workspace.root, member.root)
      if retry then
        retry()
      else
        require("gaanim.cli").notify(("Shared files of %s run as %s"):format(workspace.name, M.label(member)))
      end
    end,
  })
  return nil
end

--- A summary of what a buffer belongs to, for `:Gaanim workspace info`.
---@param description gaanim.Description
---@return string[]
function M.info_lines(description)
  local lines = {}
  local workspace, project = description.workspace, description.project
  local function rel(path)
    return path and vim.fs.normalize(vim.fn.fnamemodify(path, ":~:.")) or "—"
  end
  if workspace then
    table.insert(lines, ("Workspace  %s  %s"):format(workspace.name, rel(workspace.root)))
    local active = M.active[vim.fs.normalize(workspace.root)]
    for _, member in ipairs(workspace.members) do
      local mark = member.error and "✗" or (M.same(active, member.root) and "●" or "·")
      table.insert(
        lines,
        ("  %s %-24s %s%s"):format(
          mark,
          M.label(member),
          member.path,
          member.error and ("  " .. member.error) or (member.kind and ("  " .. member.kind) or "")
        )
      )
    end
    table.insert(
      lines,
      "Shared Python  " .. (#workspace.python > 0 and table.concat(map(workspace.python, rel), ", ") or "—")
    )
    table.insert(
      lines,
      "Shared assets  " .. (#workspace.assets > 0 and table.concat(map(workspace.assets, rel), ", ") or "—")
    )
  end
  if project then
    table.insert(lines, ("Project    %s · %s  %s"):format(project.display_name, project.kind, rel(project.root)))
  end
  table.insert(
    lines,
    "Python     " .. (description.python.interpreter or "no environment yet; opening the project prepares it")
  )
  for i, path in ipairs(description.python.paths) do
    table.insert(lines, (i == 1 and "sys.path   " or "           ") .. path)
  end
  return lines
end

--- Shows what the current file belongs to in a scratch window.
function M.info()
  local name = vim.api.nvim_buf_get_name(0)
  local description, err = M.describe(name ~= "" and name or (vim.uv.cwd() or "."))
  if not description then
    require("gaanim.cli").notify(err or "Nothing to describe", vim.log.levels.WARN)
    return
  end
  local lines = M.info_lines(description)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.cmd("botright " .. math.min(#lines, 20) .. "split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
end

return M
