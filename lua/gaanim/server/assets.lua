---@mod gaanim.server.assets Asset paths: completion, existence, information

local config = require("gaanim.config")
local server = require("gaanim.server")

local M = {}

local AUDIO = { "wav", "flac", "mp3", "m4a", "aac", "ogg", "opus" }

--- Calls whose first argument names a file, and the extensions they read.
--- `false` takes any file.
---@type table<string, string[]|false>
M.calls = {
  image = { "png", "jpg", "jpeg", "webp" },
  svg = { "svg" },
  audio = AUDIO,
  sfx = AUDIO,
  sound = AUDIO,
  video = { "mp4" },
  lottie = { "json", "lottie" },
  gltf = { "gltf", "glb" },
  narration_script = { "md" },
  preload = false,
}

--- Folders a relative name may resolve in, most likely first: the asset
--- directory, the project's `assets_dir`, `assets/` beside the entry
--- script, the script's folder and the project root.
---@param project gaanim.Project
---@return string[]
function M.bases(project)
  local entry_dir = vim.fs.dirname(project.entry)
  local list, seen = {}, {}
  for _, dir in ipairs({
    require("gaanim.script").base(project),
    project.assets_dir,
    vim.fs.joinpath(entry_dir, "assets"),
    entry_dir,
    project.root,
  }) do
    dir = vim.fs.normalize(dir)
    if not seen[dir] then
      seen[dir] = true
      table.insert(list, dir)
    end
  end
  return list
end

--- The file a name in the scene refers to, or nil when none exists.
---@param project gaanim.Project
---@param name string
---@return string?
function M.resolve(project, name)
  if name:match("^%a:[/\\]") or name:match("^/") then
    return vim.uv.fs_stat(name) and vim.fs.normalize(name) or nil
  end
  for _, base in ipairs(M.bases(project)) do
    local path = vim.fs.joinpath(base, name)
    if vim.uv.fs_stat(path) then
      return vim.fs.normalize(path)
    end
  end
end

--- Files under the asset directory with one of `extensions`, as names
--- relative to it.
---@param project gaanim.Project
---@param extensions string[]|false
---@return { name: string, path: string, size: integer }[]
function M.files(project, extensions)
  local base = vim.fs.normalize(project.assets_dir)
  if not vim.uv.fs_stat(base) then
    base = vim.fs.dirname(project.entry)
  end
  local wanted = {}
  for _, ext in ipairs(extensions or {}) do
    wanted[ext] = true
  end
  local ignore = {}
  for _, name in ipairs(config.get().outline.ignore) do
    ignore[name] = true
  end
  local files = {}
  for name, kind in
    vim.fs.dir(base, {
      depth = 5,
      skip = function(dir)
        return not ignore[vim.fs.basename(dir)]
      end,
    })
  do
    local ext = name:match("%.([%w]+)$")
    if kind == "file" and ext and (not extensions or wanted[ext:lower()]) then
      local path = vim.fs.joinpath(base, name)
      local stat = vim.uv.fs_stat(path)
      table.insert(files, { name = name:gsub("\\", "/"), path = path, size = stat and stat.size or 0 })
    end
  end
  table.sort(files, function(a, b)
    return a.name < b.name
  end)
  return files
end

---@class gaanim.AssetReference
---@field call string
---@field name string
---@field lnum integer 1-based
---@field first integer 0-based byte column where the name starts
---@field last integer 0-based byte column just after it

--- Literal file names given to asset calls in a buffer.
---@param buf integer
---@return gaanim.AssetReference[]
function M.references(buf)
  local refs = {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    for _, quote in ipairs({ '"', "'" }) do
      local pattern = "%.([%a_]+)%(%s*[rRbBuU]?" .. quote .. "()([^" .. quote .. "]*)()" .. quote
      local init = 1
      while true do
        local s, e, call, first, name, last = line:find(pattern, init)
        if not s then
          break
        end
        init = e + 1
        if M.calls[call] ~= nil and name ~= "" and not name:find("[{}]") then
          table.insert(refs, { call = call, name = name, lnum = lnum, first = first - 1, last = last - 1 })
        end
      end
    end
  end
  return refs
end

--- Warnings for names that resolve to no file.
---@param project gaanim.Project
---@param buf integer
---@return lsp.Diagnostic[]
function M.diagnostics(project, buf)
  local diagnostics = {}
  for _, ref in ipairs(M.references(buf)) do
    if not M.resolve(project, ref.name) then
      table.insert(diagnostics, {
        range = {
          start = { line = ref.lnum - 1, character = ref.first },
          ["end"] = { line = ref.lnum - 1, character = ref.last },
        },
        severity = vim.lsp.protocol.DiagnosticSeverity.Warning,
        source = "gaanim",
        message = ("%s: no file named %q in %s"):format(
          ref.call,
          ref.name,
          vim.fn.fnamemodify(project.assets_dir, ":~:.")
        ),
      })
    end
  end
  return diagnostics
end

--- Sends the asset diagnostics of a buffer.
---@param buf integer
function M.publish(buf)
  if not (vim.api.nvim_buf_is_valid(buf) and config.get().server.assets) then
    return
  end
  local project = require("gaanim.project").current(buf)
  if not project then
    return
  end
  server.publish(project.root, vim.uri_from_bufnr(buf), M.diagnostics(project, buf))
end

---@param size integer
---@return string
function M.size(size)
  if size >= 1024 * 1024 then
    return ("%.1f MB"):format(size / 1024 / 1024)
  elseif size >= 1024 then
    return ("%.0f KB"):format(size / 1024)
  end
  return size .. " B"
end

--- Markdown about a file: size, and from ffprobe its pixels or length.
---@param path string
---@param on_text fun(text: string)
function M.describe(path, on_text)
  local stat = vim.uv.fs_stat(path)
  local lines = { ("`%s`  %s"):format(vim.fn.fnamemodify(path, ":~:."), stat and M.size(stat.size) or "") }
  if vim.fn.executable("ffprobe") ~= 1 then
    on_text(table.concat(lines, "\n"))
    return
  end
  vim.system({
    "ffprobe",
    "-v",
    "error",
    "-show_entries",
    "stream=codec_type,width,height:format=duration",
    "-of",
    "json",
    path,
  }, { text = true }, function(result)
    local ok, info = pcall(vim.json.decode, result.stdout or "", { luanil = { object = true, array = true } })
    if ok and type(info) == "table" then
      for _, stream in ipairs(info.streams or {}) do
        if stream.width and stream.height then
          table.insert(lines, ("%d × %d px"):format(stream.width, stream.height))
          break
        end
      end
      local duration = info.format and tonumber(info.format.duration)
      if duration and duration > 0 then
        table.insert(lines, ("%.2f s"):format(duration))
      end
    end
    vim.schedule(function()
      on_text(table.concat(lines, "  \n"))
    end)
  end)
end

return M
