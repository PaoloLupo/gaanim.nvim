# gaanim.nvim

Write [Gaanim](https://paololupo.github.io/gaanim/) videos and slides from
Neovim. The plugin drives the `gaanim` command: it creates projects, keeps the
live preview on the line you are editing, turns problems into diagnostics,
exports, presents, and keeps the narration script beside the code.

```
:Gaanim new slides talk      create ~/dev/gaanim/talk and open main.py
:Gaanim follow               the preview follows the cursor through the code
:Gaanim script               the slide's script in a side window
:Gaanim still                a PNG of the instant the cursor's line stands for
:Gaanim export draft here    a quick MP4 of the slide under the cursor
:Gaanim present here 20m     present from this line with a 20-minute clock
```

## What it does

- **Projects.** `:Gaanim new [slides|video] [name]` runs `gaanim init` (Python
  environment included) in `projects_dir` and opens the entry script;
  `:Gaanim projects` lists the projects there.
- **Live preview, driven from the code.** `:Gaanim preview` opens the preview,
  which reloads on every save. `:Gaanim preview here` moves it to the instant
  the line under the cursor stands for (the `play` that ends there, the stop,
  the segment) without restarting it, and `:Gaanim follow` keeps it there as
  you move. `:Gaanim seek {seconds|segment|stop}`, `:Gaanim play` and
  `:Gaanim pause` drive it too. Where the preview rests is marked in the code
  with a sign, and the statusline shows it (`󰏤 0:01.8 Problem·question`).
- **Errors where they happen.** A failed reload puts the Python error on its
  line as a diagnostic, without running anything else.
- **Back to the code.** Previews started from Neovim get a `GAANIM_EDITOR`
  pointing at this Neovim, so the inspector, the console, a double click on
  the animation timeline, the error panel and *Open and complete* open the
  line here.
- **Checks.** Saving a project file runs `gaanim check` in the background.
  Warnings and errors go to diagnostics and the quickfix list, on the line
  they are about.
- **Timeline and structure.** `:Gaanim timeline` lists the real timeline
  (segments, stops, markers, voiceovers) with times; picking an entry jumps to
  its line and moves the preview there. `:Gaanim outline` reads the Python
  without running it, and `<Plug>` motions move between slides and stops.
  The statusline shows the instant of the cursor's line (`󰔛 0:12.5`).
- **Narration script.** `:Gaanim script` opens `narration/script.md` at the
  side and keeps it on the section of the slide under the cursor, or of the
  slide the preview shows while you present. `:Gaanim script goto` jumps
  between a slide's code and its section both ways, and adds the section, with
  a `[stop]` mark per stop, when it is missing. Each section and segment shows
  how long its text takes to say against the segment's `target=` (green,
  amber, red), and the title shows the whole talk against
  `scene.slides.target()`. Voiceovers show whether their take is recorded.
- **Exports.** `:Gaanim export` picks a preset (MP4, draft, production, WebM,
  MOV, GIF, WebP, PDF, PDF with notes, `.gaanim` bundle, still) and shows its
  progress in percent. `here` limits it to the slide under the cursor;
  `:Gaanim export out/clip.webm --from intro --to outro` passes any
  `gaanim export` option. `:Gaanim still` exports the frame of the cursor's
  line, named after it (`talk-question.png`); `still pick` asks for a marker
  or time.
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
- **Python completion.** When basedpyright or pyright attaches to a project
  file, it is pointed at the project's `.venv`, where `gaanim init` installed
  the authoring package and its type stubs.
- **Snippets** for scenes and scripts in `snippets/` (VS Code format).
- `:checkhealth gaanim` checks `gaanim` and what it supports, FFmpeg, uv, a
  Python language server, the project's `.venv`, its bundled docs and script.

### Newer and older Gaanim

The plugin reads `gaanim --help` once and uses what the installed version
offers. Driving the preview (`here` without a restart, `follow`, `seek`,
`play`, the playhead) needs `--listen`; exact diagnostic lines and export
percent need `--message-format json`; `timeline`, the cursor's instant and
stills at the cursor need `inspect`; stills and ranges by slide name need
`export` to take names. Without them, `preview here` restarts the preview
from the cursor's segment and the rest reads the CLI's text output.

## Install

Needs Neovim 0.10+ (0.12 for native progress messages), a
[Nerd Font](https://www.nerdfonts.com) for the default icons, and `gaanim` on
`PATH`. [snacks.nvim](https://github.com/folke/snacks.nvim) is optional and
gives the pickers a preview.

With lazy.nvim, loading on the command, the keys, or a Python or Markdown
file:

```lua
{
  "PaoloLupo/gaanim.nvim",
  cmd = "Gaanim",
  ft = { "python", "markdown" },
  opts = {
    projects_dir = "~/dev/gaanim",
  },
  keys = {
    { "<leader>mn", "<Plug>(gaanim-new)", desc = "New project" },
    { "<leader>mo", "<Plug>(gaanim-projects)", desc = "Open project" },
    { "<leader>mp", "<Plug>(gaanim-preview)", desc = "Preview" },
    { "<leader>mh", "<Plug>(gaanim-preview-here)", desc = "Preview at cursor" },
    { "<leader>mf", "<Plug>(gaanim-follow)", desc = "Preview follows cursor" },
    { "<leader>mP", "<Plug>(gaanim-present-here)", desc = "Present from cursor" },
    { "<leader>mq", "<Plug>(gaanim-stop)", desc = "Close preview" },
    { "<leader>mc", "<Plug>(gaanim-check)", desc = "Check" },
    { "<leader>me", "<Plug>(gaanim-export)", desc = "Export" },
    { "<leader>mi", "<Plug>(gaanim-still)", desc = "Still at cursor" },
    { "<leader>ms", "<Plug>(gaanim-outline)", desc = "Outline" },
    { "<leader>mT", "<Plug>(gaanim-timeline)", desc = "Timeline" },
    { "<leader>mt", "<Plug>(gaanim-script)", desc = "Narration script" },
    { "<leader>mg", "<Plug>(gaanim-script-goto)", desc = "Script ↔ code" },
    { "<leader>md", "<Plug>(gaanim-docs)", desc = "Docs" },
    { "<leader>mk", "<Plug>(gaanim-api)", desc = "API entry at cursor" },
    { "]v", "<Plug>(gaanim-next-slide)", ft = "python", desc = "Next slide" },
    { "[v", "<Plug>(gaanim-prev-slide)", ft = "python", desc = "Previous slide" },
    { "]V", "<Plug>(gaanim-next-stop)", ft = "python", desc = "Next stop" },
    { "[V", "<Plug>(gaanim-prev-stop)", ft = "python", desc = "Previous stop" },
  },
}
```

The plugin needs no `setup()`: the command and `<Plug>` mappings exist as
soon as it is on the runtimepath, and options can also go in `vim.g.gaanim`.

Statusline (lualine), shown once the plugin has loaded so it never loads it:

```lua
{
  function() return require("gaanim").status() end,
  cond = function() return vim.g.loaded_gaanim == true end,
}
```

Typst math completion with blink.cmp, only in Python buffers:

```lua
{
  "saghen/blink.cmp",
  opts = {
    sources = {
      per_filetype = { python = { inherit_defaults = true, "gaanim_typst" } },
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
  preview = {
    args = {}, stop_on_exit = true,
    editor = true,                 -- GAANIM_EDITOR back to this Neovim
    listen = true,                 -- drive the preview with --listen stdio
    marker = true,                 -- sign on the line the preview rests at
    follow_delay = 120,            -- ms the cursor settles before following
  },
  present = { duration = nil, monitor = nil },
  check = { on_save = true, strict = false, debounce = 400, quickfix = "errors" },
  export = { open = false, presets = { ... } }, -- see :h gaanim-export
  script = { path = nil, wpm = 150, follow = true, timing = true, width = 60 },
  outline = { patterns = {}, ignore = { ".venv", "exports", ... } },
  picker = "auto",                 -- "snacks" or "select"
  icons = "nerd",                  -- "unicode" without a Nerd Font, or a table
  lsp = true,                      -- point pyright/basedpyright at .venv
}
```

`outline.patterns` teaches the outline a project's own way of naming slides.
A deck that keeps one slide per module with `NAME = "Cover"` can use:

```lua
outline = { patterns = { { kind = "segment", pattern = '\nNAME%s*=%s*"([^"]+)"' } } }
```

`:Gaanim timeline` needs none of this: it lists what the scene really made.

## Develop

```
nvim --headless --clean -l tests/run.lua
```

The tests need nothing but Neovim. `docs/research.md` records the research
behind the design, what Gaanim gained for editors, and the roadmap.
