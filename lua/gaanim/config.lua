---@mod gaanim.config Configuration

local M = {}

---@class gaanim.ExportPreset
---@field ext string Output extension, without the dot
---@field args? string[] Extra arguments for `gaanim export`
---@field desc string Shown in the export picker
---@field ask? "frame" Ask for a value before exporting

---@class gaanim.Config
---@field cmd string|string[] The `gaanim` executable, or a command list
---@field projects_dir? string Where `:Gaanim new` creates projects and `:Gaanim projects` looks
---@field new gaanim.NewConfig
---@field preview gaanim.PreviewConfig
---@field present gaanim.PresentConfig
---@field check gaanim.CheckConfig
---@field export gaanim.ExportConfig
---@field script gaanim.ScriptConfig
---@field outline gaanim.OutlineConfig
---@field picker "auto"|"snacks"|"select"
---@field icons "nerd"|"unicode"|table Nerd Font icons, plain characters, or overrides
---@field lsp boolean Point pyright/basedpyright at the project's .venv
---@field server gaanim.ServerConfig
---@field live gaanim.LiveConfig
---@field workspace gaanim.WorkspaceConfig

---@class gaanim.WorkspaceConfig
---@field output string Where `:Gaanim workspace export` writes, from the workspace's root; `{member}` is each member's path

---@class gaanim.ServerConfig
---@field enabled boolean Attach the Gaanim language server to project files
---@field hints boolean Times of plays, stops and segments as inlay hints
---@field lens boolean Code lenses over slides and voiceovers
---@field assets boolean Warn about asset names that resolve to no file
---@field typst boolean Typst math completion in equation strings

---@class gaanim.LiveConfig
---@field delay integer Milliseconds after a change before writing
---@field while_typing boolean Also write in insert mode, after `typing_delay`
---@field typing_delay integer
---@field quiet boolean Only diagnostics, no notifications, when a reload fails

---@class gaanim.NewConfig
---@field cd "tcd"|"cd"|"lcd"|false How to enter a new or picked project
---@field git boolean Run `git init` in a new project

---@class gaanim.PreviewConfig
---@field args string[] Extra arguments for every preview
---@field stop_on_exit boolean Close previews when Neovim exits
---@field editor boolean Make Gaanim's "Open in the editor" open lines in this Neovim
---@field listen boolean Drive the preview through `--listen stdio` when Gaanim has it
---@field marker boolean Mark the line the preview rests at
---@field animating boolean Highlight the lines whose plays are animating while the preview plays
---@field follow_delay integer Milliseconds a following preview waits for the cursor to settle

---@class gaanim.PresentConfig
---@field duration? string Planned length, e.g. "20m"
---@field monitor? integer Monitor index for `--present`

---@class gaanim.CheckConfig
---@field on_save boolean Run `gaanim check` when a project file is saved
---@field strict boolean Pass `--strict`
---@field debounce integer Milliseconds to wait after the last save
---@field quickfix "errors"|"always"|"never" When to open the quickfix list

---@class gaanim.ExportConfig
---@field open boolean Open the file when the export finishes
---@field presets table<string, gaanim.ExportPreset>

---@class gaanim.ScriptConfig
---@field path? string Narration script, relative to the project root
---@field wpm integer Words per minute used to estimate spoken time
---@field follow boolean Scroll the script window to the slide under the cursor
---@field timing boolean Show spoken time against each slide's target
---@field width integer Width of the script window

---@class gaanim.OutlinePattern
---@field kind gaanim.SymbolKind
---@field pattern string Lua pattern; its first capture is the name

---@class gaanim.OutlineConfig
---@field patterns gaanim.OutlinePattern[] Extra patterns for project conventions
---@field ignore string[] Directory names that are never scanned

---@type gaanim.Config
M.defaults = {
  cmd = "gaanim",
  projects_dir = nil,
  new = { cd = "tcd", git = false },
  preview = {
    args = {},
    stop_on_exit = true,
    editor = true,
    listen = true,
    marker = true,
    animating = true,
    follow_delay = 120,
  },
  present = { duration = nil, monitor = nil },
  check = { on_save = true, strict = false, debounce = 400, quickfix = "errors" },
  export = {
    open = false,
    presets = {
      mp4 = { ext = "mp4", desc = "MP4 video, 1080p 60 fps" },
      draft = { ext = "mp4", args = { "--quality", "draft" }, desc = "MP4 draft, 30 fps, fast" },
      production = { ext = "mp4", args = { "--quality", "production" }, desc = "MP4, best encode" },
      webm = { ext = "webm", desc = "WebM video (VP9)" },
      mov = { ext = "mov", desc = "ProRes MOV for video editors" },
      gif = { ext = "gif", desc = "Animated GIF" },
      webp = { ext = "webp", desc = "Animated WebP" },
      pdf = { ext = "pdf", desc = "PDF, a page per stop" },
      notes = { ext = "pdf", args = { "--notes" }, desc = "PDF with speaker notes" },
      bundle = { ext = "gaanim", desc = "Playback bundle (.gaanim)" },
      still = { ext = "png", ask = "frame", desc = "One PNG at a time or marker" },
    },
  },
  script = { path = nil, wpm = 150, follow = true, timing = true, width = 60 },
  outline = {
    patterns = {},
    ignore = { ".venv", "venv", ".git", "__pycache__", "exports", "snapshots", "node_modules", ".ruff_cache" },
  },
  picker = "auto",
  icons = "nerd",
  server = { enabled = true, hints = true, lens = true, assets = true, typst = true },
  live = { delay = 300, while_typing = false, typing_delay = 900, quiet = true },
  workspace = { output = "exports/{member}" },
  lsp = true,
}

---@type gaanim.Config?
local current

---@param opts? table
function M.setup(opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), vim.g.gaanim or {}, opts or {})
end

---@return gaanim.Config
function M.get()
  if not current then
    M.setup()
  end
  return current --[[@as gaanim.Config]]
end

return M
