# gaanim.nvim

Write [Gaanim](https://paololupo.github.io/gaanim/) videos and slides from
Neovim. The plugin drives the `gaanim` command: it creates projects, opens the
live preview at the slide under the cursor, turns problems into diagnostics,
exports, presents, and keeps the narration script beside the code.

```
:Gaanim new slides talk      create ~/dev/gaanim/talk and open main.py
:Gaanim preview here         preview from the slide under the cursor
:Gaanim script               the slide's script in a side window that follows you
:Gaanim export draft         a quick MP4 in exports/
:Gaanim present here 20m     present from this slide with a 20-minute clock
```

## What it does

- **Projects.** `:Gaanim new [slides|video] [name]` runs `gaanim init` (Python
  environment included) in `projects_dir` and opens the entry script;
  `:Gaanim projects` lists the projects there.
- **Live preview.** `:Gaanim preview` opens the preview window, which reloads
  on every save. `here` starts at the segment under the cursor (`--from`),
  `only` plays just that one (`--sections`). The preview's own output becomes
  feedback in Neovim: a failed reload puts the Python error on its line as a
  diagnostic, and the statusline shows `● ready`, `↻ reloading` or `✗ failed`.
- **Back to the code.** Previews started from Neovim get a `GAANIM_EDITOR`
  pointing at this Neovim, so the inspector, the console, a double click on
  the animation timeline and the error panel's *Open in the editor* jump to
  the line here.
- **Checks.** Saving a project file runs `gaanim check` in the background.
  Warnings and errors go to diagnostics and the quickfix list, pointed at the
  line they are about: the script mark, the segment or the stop they name.
- **Structure.** `:Gaanim outline` lists segments, sections, voiceovers,
  stops and markers across the project with a preview, and `<Plug>` motions
  move between slides and stops.
- **Narration script.** `:Gaanim script` opens `narration/script.md` at the
  side and keeps it on the section of the slide under the cursor (and on the
  mark of the stop you are in). `:Gaanim script goto` jumps between a slide's
  code and its section both ways, and adds the section, with a `[stop]` mark
  per stop, when it is missing. Each section and each segment shows how long
  its text takes to say against the segment's `target=` (green, amber, red),
  and the title shows the whole talk against `scene.slides.target()`.
  Voiceovers show whether their take is recorded.
- **Exports.** `:Gaanim export` picks a preset (MP4, draft, production, WebM,
  MOV, GIF, WebP, PDF, PDF with notes, `.gaanim` bundle, still) and shows
  progress; `:Gaanim export out/clip.webm --from intro --to outro` passes any
  `gaanim export` option. `:Gaanim still` exports one PNG at a marker or time.
- **Presenting.** `:Gaanim present [here] [20m] [monitor=1]`.
- **Docs.** `:Gaanim docs [text]` searches the documentation bundled with the
  project's Gaanim (it matches the installed version); `:Gaanim api [name]`
  opens an API entry, by default the word under the cursor.
- **Typst math completion.** Inside the strings of `scene.text.equation(...)`
  and the `$...$` of other text, a blink.cmp source offers Typst's math
  symbols with the character each one draws as its icon (`α alpha`,
  `⇒ arrow.r.double`; type `.` for a symbol's variants), its math functions
  (`frac`, `sqrt`, `mat`, `cases`, `bold`…) as snippets, accents, text
  operators and spaces. The names are the ones Gaanim's Typst compiles
  (codex 0.3.0; `scripts/gen_typst_symbols.py` regenerates the table).
- **Snippets** for scenes and scripts in `snippets/` (VS Code format).
- **Completion.** When basedpyright or pyright attaches to a project file, it
  is pointed at the project's `.venv`, where `gaanim init` installed the
  authoring package and its type stubs.
- `:checkhealth gaanim` checks `gaanim`, FFmpeg, uv, the project's `.venv`,
  its bundled docs and where its script is.

## Install

Needs Neovim 0.10+ (0.12 for native progress messages) and `gaanim` on
`PATH`. [snacks.nvim](https://github.com/folke/snacks.nvim) is optional and
gives the pickers a preview.

With lazy.nvim:

```lua
{
  "PaoloLupo/gaanim.nvim", -- or dir = "~/dev/gaanim.nvim"
  cmd = "Gaanim",
  ft = { "python", "markdown" },
  opts = {
    projects_dir = "~/dev/gaanim",
  },
  keys = {
    { "<leader>mn", "<Plug>(gaanim-new)", desc = "New project" },
    { "<leader>mo", "<Plug>(gaanim-projects)", desc = "Open project" },
    { "<leader>mp", "<Plug>(gaanim-preview)", desc = "Preview" },
    { "<leader>mh", "<Plug>(gaanim-preview-here)", desc = "Preview from here" },
    { "<leader>mP", "<Plug>(gaanim-present-here)", desc = "Present from here" },
    { "<leader>mq", "<Plug>(gaanim-stop)", desc = "Close preview" },
    { "<leader>mc", "<Plug>(gaanim-check)", desc = "Check" },
    { "<leader>me", "<Plug>(gaanim-export)", desc = "Export" },
    { "<leader>ms", "<Plug>(gaanim-outline)", desc = "Outline" },
    { "<leader>mt", "<Plug>(gaanim-script)", desc = "Script" },
    { "<leader>mg", "<Plug>(gaanim-script-goto)", desc = "Script ↔ code" },
    { "<leader>md", "<Plug>(gaanim-docs)", desc = "Docs" },
    { "<leader>mk", "<Plug>(gaanim-api)", desc = "API entry" },
    { "]v", "<Plug>(gaanim-next-slide)", ft = "python", desc = "Next slide" },
    { "[v", "<Plug>(gaanim-prev-slide)", ft = "python", desc = "Previous slide" },
    { "]V", "<Plug>(gaanim-next-stop)", ft = "python", desc = "Next stop" },
    { "[V", "<Plug>(gaanim-prev-stop)", ft = "python", desc = "Previous stop" },
  },
}
```

The plugin needs no `setup()`: the command and `<Plug>` mappings exist as
soon as it is on the runtimepath, and options can also go in `vim.g.gaanim`.

Statusline (lualine):

```lua
{ function() return require("gaanim").status() end }
```

Typst math completion with blink.cmp:

```lua
{
  "saghen/blink.cmp",
  opts = {
    sources = {
      default = { "lsp", "path", "snippets", "buffer", "gaanim_typst" },
      providers = {
        gaanim_typst = { name = "Typst", module = "gaanim.typst.blink", score_offset = 20 },
      },
    },
  },
}
```

Snippets with blink.cmp: add the plugin's `snippets` folder to
`sources.providers.snippets.opts.search_paths`. With LuaSnip:
`require("luasnip.loaders.from_vscode").lazy_load({ paths = { "<plugin>/snippets" } })`.

## Options

```lua
{
  cmd = "gaanim",                  -- or { "path/to/gaanim.exe" }
  projects_dir = nil,              -- where :Gaanim new creates projects
  new = { cd = "tcd", git = false },
  preview = { args = {}, stop_on_exit = true, editor = true },
  present = { duration = nil, monitor = nil },
  check = { on_save = true, strict = false, debounce = 400, quickfix = "errors" },
  export = { open = false, presets = { ... } }, -- see :h gaanim-export
  script = { path = nil, wpm = 150, follow = true, timing = true, width = 60 },
  outline = { patterns = {}, ignore = { ".venv", "exports", ... } },
  picker = "auto",                 -- "snacks" or "select"
  lsp = true,                      -- point pyright/basedpyright at .venv
}
```

`outline.patterns` teaches the outline a project's own way of naming slides.
A deck that keeps one slide per module with `NAME = "Cover"` can use:

```lua
outline = { patterns = { { kind = "segment", pattern = '\nNAME%s*=%s*"([^"]+)"' } } }
```

## Develop

```
nvim --headless --clean -l tests/run.lua
```

The tests need nothing but Neovim. `docs/investigacion.md` (Spanish) records
the research behind the design and the roadmap, including what Gaanim could
expose to make the editor and the preview work as one.
