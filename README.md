# gaanim.nvim

Write [Gaanim](https://paololupo.github.io/gaanim/) videos and slides from
Neovim. The plugin drives the `gaanim` command: it creates projects, keeps the
live preview on the line you are editing, turns problems into diagnostics,
exports, presents, and keeps the narration script beside the code.

```
:Gaanim new slides talk      create ~/dev/gaanim/talk and open main.py
:Gaanim live                 every change reaches the preview as you make it
:Gaanim follow               the preview follows the cursor through the code
:Gaanim script               the slide's script in a side window
:Gaanim still                a PNG of the instant the cursor's line stands for
:Gaanim export draft here    a quick MP4 of the slide under the cursor
:Gaanim present here 20m     present from this line with a 20-minute clock
```

## What it does

- **A Gaanim language server inside Neovim.** It attaches to the Python files
  of every project next to basedpyright and shows what only Gaanim knows:
  - the time of each `play`, `stop`, segment, marker and voiceover as an
    inlay hint at the end of its line (`󰐊 0:00.8–0:01.3`, `󰏤 0:01.3`);
  - code lenses over each slide (`󰐊 Preview  󰑖 Loop  󰋩 Still  󰍬 ≈0:42 / 1:00
    󰔛 0:12.0–0:30.0`) and voiceover (`take recorded`);
  - hover on a line: what it makes on the timeline; on an asset name: the
    file's size, pixels or length;
  - code actions: write a slide's missing script, name an unnamed stop, add
    a marker, preview the line, export its frame or its slide;
  - slides, stops, markers and voiceovers as document symbols (outline,
    breadcrumbs, symbol pickers);
  - completion of asset names inside `media.image("…")`, `svg`, `audio`,
    `video`… and of Typst math, in any completion plugin;
  - a warning on asset names that resolve to no file.
- **Live mode.** `:Gaanim live` writes a changed file a moment after you stop
  changing it, without running write hooks such as formatters, so the preview
  shows each change within a fraction of a second. While the preview plays,
  the lines whose `play` is animating are highlighted.
- **Nudging numbers.** `<Plug>(gaanim-nudge-up)` and `-down` work like CTRL-A
  and CTRL-X but step decimals by their own precision (`0.8` → `0.9`,
  `0.25` → `0.26`); with live mode, each nudge shows in the preview.
- **Projects.** `:Gaanim new [slides|video] [name]` runs `gaanim init` (Python
  environment included) in `projects_dir` and opens the entry script;
  `:Gaanim projects` lists the projects there.
- **Workspaces.** Several projects in one repository that share Python code,
  assets and one `.venv`, listed by a `[workspace]` table in the root
  `gaanim.toml`. The plugin asks `gaanim project --json` (`gaanim update`
  brings it), in the background, what each file belongs to:
  - pyright and basedpyright get the workspace's shared interpreter and the
    folders on its `sys.path` (`analysis.extraPaths`), so `from common
    import …` (the shared `src/common/`) and the member's own modules
    complete;
  - a shared module (in `[workspace.shared] python`) runs as the *active
    member*, the one whose files you entered last: `:Gaanim preview`,
    `check`, `live`, `follow` and the times in the code work from it, and
    saving it re-times every member. With no member entered yet, a command
    asks which one and runs with it;
  - asset names resolve, complete and are checked in the shared assets too;
  - `:Gaanim workspace` lists the members by group (invalid ones in red, with
    their error), with *New video*, *New presentation*, *Check all* and
    *Export all*; `:Gaanim workspace check [members]` checks them in one
    `gaanim check`, each member's problems as its diagnostics and all of
    them in one quickfix list; `:Gaanim workspace export [preset] [members]`
    exports each to `exports/{member}.mp4` under the workspace;
    `:Gaanim workspace use [member]` picks the member shared modules run as,
    `new [video|slides] [name]` adds one beside the others, and `info` shows
    what the file belongs to, its interpreter and `sys.path`;
  - `:Gaanim new workspace [name]` runs `gaanim init workspace`, and inside a
    workspace `:Gaanim new video ep2` adds the member `videos/ep2`;
    `:Gaanim projects` lists a workspace as one entry that opens its members.
- **Live preview, driven from the code.** `:Gaanim preview` opens the preview,
  which reloads on every save. `:Gaanim preview here` moves it to the instant
  the line under the cursor stands for (the `play` that ends there, the stop,
  the segment) without restarting it, and `:Gaanim follow` keeps it there as
  you move. `:Gaanim loop` plays the slide under the cursor over and over
  (through its stops, across reloads), which pairs well with live mode;
  `:Gaanim loop off` ends it. While it loops, the statusline and the signs
  in the code show `󰑖` instead of play, and the slide's lens turns into
  `󰑗 Unloop`. `:Gaanim seek {seconds|segment|stop}`,
  `:Gaanim play` and `:Gaanim pause` drive it too, and so does
  `:Gaanim panel`: a floating panel with play, pause and loop, a scrubber
  that seeks where you click, and the slides as blocks as long as they last,
  each a click away (drawn with [volt](https://github.com/PaoloLupo/volt)). Where the preview rests is marked in the code
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
  and the `$...$` of other text, the language server offers Typst's math
  symbols with the character each one draws as its icon (`α alpha`,
  `⇒ arrow.r.double`; type `.` for a symbol's variants), its math functions
  (`frac`, `sqrt`, `mat`, `cases`, `bold`…) as snippets, accents, text
  operators and spaces. The names are the ones Gaanim's Typst compiles
  (codex 0.3.0; `scripts/gen_typst_symbols.py` regenerates the table).
- **Python completion.** When basedpyright or pyright attaches to a project
  file, it is pointed at the project's `.venv` (the workspace's, in a
  workspace), where `gaanim init` installed the authoring package and its
  type stubs.
- **Snippets** for scenes and scripts in `snippets/` (VS Code format).
- `:checkhealth gaanim` checks `gaanim` and what it supports, FFmpeg, uv, a
  Python language server, the project's environment and `sys.path`, its
  workspace and members, its bundled docs and script.

### Newer and older Gaanim

The plugin reads `gaanim --help` once and uses what the installed version
offers. Driving the preview (`here` without a restart, `follow`, `seek`,
`play`, the playhead) needs `--listen`; exact diagnostic lines and export
percent need `--message-format json`; `timeline`, the cursor's instant and
stills at the cursor need `inspect`; stills and ranges by slide name need
`export` to take names; workspaces need `gaanim project`. While a preview is open, Gaanim sends the scene's
timeline with each reload (`ready`), so the times in the code update after a
save without running the scene a second time; `inspect` covers the rest.
Without these, `preview here` restarts the preview from the cursor's segment
and the rest reads the CLI's text output.

## Install

Needs Neovim 0.10+ (0.12 for native progress messages), a
[Nerd Font](https://www.nerdfonts.com) for the default icons, and `gaanim` on
`PATH`. [snacks.nvim](https://github.com/folke/snacks.nvim) is optional and
gives the pickers a preview; [volt](https://github.com/PaoloLupo/volt) (a fork
of nvzone/volt) is optional and draws `:Gaanim panel`.

With lazy.nvim, loading on the command, the keys, or a Python or Markdown
file:

```lua
{
  "PaoloLupo/gaanim.nvim",
  dependencies = { { "PaoloLupo/volt", lazy = true } },
  cmd = "Gaanim",
  ft = { "python", "markdown" },
  opts = {
    projects_dir = "~/dev/gaanim",
  },
  keys = {
    { "<leader>mn", "<Plug>(gaanim-new)", desc = "New project" },
    { "<leader>mo", "<Plug>(gaanim-projects)", desc = "Open project" },
    { "<leader>mw", "<Plug>(gaanim-workspace)", desc = "Workspace members" },
    { "<leader>mp", "<Plug>(gaanim-preview)", desc = "Preview" },
    { "<leader>mh", "<Plug>(gaanim-preview-here)", desc = "Preview at cursor" },
    { "<leader>mf", "<Plug>(gaanim-follow)", desc = "Preview follows cursor" },
    { "<leader>mL", "<Plug>(gaanim-live)", desc = "Live mode" },
    { "<leader>mr", "<Plug>(gaanim-loop)", desc = "Loop slide (toggle)" },
    { "<leader>mb", "<Plug>(gaanim-panel)", desc = "Playback panel" },
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
    { "<C-a>", "<Plug>(gaanim-nudge-up)", ft = "python", desc = "Increase number" },
    { "<C-x>", "<Plug>(gaanim-nudge-down)", ft = "python", desc = "Decrease number" },
  },
}
```

The nudges fall back to CTRL-A and CTRL-X outside Gaanim projects. Code
lenses run with `grx` (Neovim 0.12) or LazyVim's `<leader>cc`; inlay hints
toggle with `vim.lsp.inlay_hint.enable()` or LazyVim's `<leader>uh`.

The plugin needs no `setup()`: the command and `<Plug>` mappings exist as
soon as it is on the runtimepath, and options can also go in `vim.g.gaanim`.

Statusline (lualine), shown once the plugin has loaded so it never loads it:

```lua
{
  function() return require("gaanim").status() end,
  cond = function() return vim.g.loaded_gaanim == true end,
}
```

Typst math and asset names come from the language server, so any completion
plugin with an LSP source shows them (blink.cmp keeps each symbol's character
as its icon). With `server.enabled = false`, the blink source
`gaanim.typst.blink` still offers Typst math.

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
    animating = true,              -- highlight the lines animating while playing
    follow_delay = 120,            -- ms the cursor settles before following
  },
  present = { duration = nil, monitor = nil },
  check = { on_save = true, strict = false, debounce = 400, quickfix = "errors" },
  export = { open = false, presets = { ... } }, -- see :h gaanim-export
  script = { path = nil, wpm = 150, follow = true, timing = true, width = 60 },
  outline = { patterns = {}, ignore = { ".venv", "exports", ... } },
  picker = "auto",                 -- "snacks" or "select"
  icons = "nerd",                  -- "unicode" without a Nerd Font, or a table
  server = { enabled = true, hints = true, lens = true, assets = true, typst = true },
  live = { delay = 300, while_typing = false, typing_delay = 900, quiet = true },
  lsp = true,                      -- point pyright/basedpyright at .venv
  workspace = { output = "exports/{member}" }, -- :Gaanim workspace export, from its root
}
```

`outline.patterns` teaches the outline a project's own way of naming slides.
A deck that keeps one slide per module with `NAME = "Cover"` can use:

```lua
outline = { patterns = { { kind = "segment", pattern = '\nNAME%s*=%s*"([^"]+)"' } } }
```

`:Gaanim timeline` needs none of this: it lists what the scene really made.

## Colorscheme

The plugin brings a colorscheme in Gaanim's colors: violet keywords, gold
types and titles, mist borders, on warm paper or on graphite. The light
variant is made for long sessions: no pure white, soft accents, and every
text color at 4.5:1 (WCAG AA) or more on the background, the cursor line,
floats and the selection (`tests/spec/theme_spec.lua` checks it).

```
:colorscheme gaanim          follows 'background'
:colorscheme gaanim-light
:colorscheme gaanim-dark
```

It covers the editor, Treesitter, LSP semantic tokens, diagnostics, inlay
hints and code lenses, and LazyVim's plugins (blink.cmp, snacks, which-key,
noice, trouble, gitsigns, flash, mini.icons, todo-comments, lazy, mason,
grug-far, render-markdown). lualine's `auto` theme picks its own `gaanim`
theme. With LazyVim, set `opts = { colorscheme = "gaanim-light" }` on
`LazyVim/LazyVim`. Options, before the colorscheme loads:

```lua
require("gaanim.theme").setup({
  transparent = false,             -- leave the backgrounds to the terminal
  italic = true,                   -- comments, builtins, parameters
  on_colors = function(colors, variant) end,
  on_highlights = function(groups, colors, variant) end,
})
```

`nvim --headless --clean -l scripts/theme_preview.lua [out.html]` renders
both variants side by side: a scene with inlay hints, lenses and
diagnostics, and the UI groups.

## Develop

```
nvim --headless --clean -l tests/run.lua
```

The tests need nothing but Neovim. `docs/research.md` records the research
behind the design, what Gaanim gained for editors, and the roadmap.
