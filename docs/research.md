# Research: a Neovim plugin for making videos and slides with Gaanim

October 2026 · Neovim 0.12, LazyVim, Windows 11, Gaanim 0.12 and later

## Conclusion

Gaanim already does the hard parts: it reloads the preview on save, checks a
scene with `gaanim check`, opens script lines in whatever editor
`GAANIM_EDITOR` names, and reads the talk's script from Markdown. What the
editor adds is **where the cursor is**. With it the plugin moves the preview to
the line being edited, keeps the slide's script in view, estimates how long it
takes to say, and puts every error on its line.

To make the editor and the preview work as one, Gaanim gained three opt-in
pieces while this plugin was built: a control channel for the preview
(`--listen`), the timeline with the script line of every part
(`gaanim inspect --json`), and machine-readable messages
(`--message-format json`). Without any of them, Gaanim behaves as before, and
nothing in `gaanim init` is specific to an editor.

## What Gaanim offers editors

| Piece | How the plugin uses it |
|---|---|
| The preview reloads on save (it watches the project, 200 ms debounce) | Saving in Neovim is enough; the plugin never asks for a reload |
| `--listen stdio`: commands in (`seek`, `follow`, `play`, `pause`) and events out (`ready`, `reload`, `failed`, `playhead`, `error`) as JSON lines | `preview here` and `follow` move the preview to the cursor's line without a restart; the playhead is marked in the code and the statusline; the script window follows the slide shown |
| `gaanim inspect --json`: segments, stops, markers, voiceovers and plays with times and their script line | `:Gaanim timeline`, the instant of the cursor's line, stills and ranges at the cursor, the playhead's line |
| `--message-format json` for `check`, `export` and the preview | Diagnostics on the line Gaanim names, export progress in percent, reload events |
| `export --frame/--from/--to` take segment, Section and stop names | `:Gaanim still` and `export ... here` for the slide under the cursor |
| `GAANIM_EDITOR` with `{file}` and `{line}`, used by the inspector, the console, the animation timeline, the error panel and *Open and complete* | Previews started from Neovim get a command that calls this Neovim through its RPC server (`--remote-expr`) |
| The script in `narration/script.md`: `## name` sections, `[stop]` marks, `###` notes and HTML comments not read, headings matched ignoring case | Side window that follows the cursor or the preview, code ↔ section jumps, new sections with their marks, spoken-time estimates |
| `scene.voiceover(key)` with takes in `narration/<key>.wav` and a JSON sidecar of words | Shows whether each voiceover's take is recorded |
| The docs' Typst sources inside the wheel (`gaanim/_docs`), with `#api-entry(name: ...)` | `:Gaanim docs` and `:Gaanim api` search the installed version |
| Complete `.pyi` stubs in the project's `.venv` | The plugin points basedpyright or pyright at that `.venv` when it attaches |
| Typst math via codex symbol names | A completion source with codex 0.3.0's names, each symbol showing its character |

The plugin reads `gaanim --help` once and uses only what the installed version
has, so it keeps working with a Gaanim that predates these additions.

## Recommended workflows

### Slides: write what you will say first

1. `:Gaanim new slides talk`. Set the length with `scene.slides.target()` and a
   `target=` per segment.
2. Sketch the structure: one `scene.segment(...)` per slide (snippet `gseg`)
   with its `scene.stop("name")` calls, before animating anything.
3. `:Gaanim script goto` on each segment creates its section with a mark per
   stop. Write the script there: the virtual text says whether each slide fits
   its time (green, amber, red) and the title whether the talk does.
4. Animate with `:Gaanim follow` on: the preview shows the line you are on, a
   save reloads it, errors land on their line.
5. Rehearse and record the real timings in the app (*Record the talk*), then
   `:Gaanim present 20m`; the script window follows the slide on screen.

This is the two-column script that explainer-video production uses (audio
first, picture after), with the per-word estimate the industry plans with
(130–150 words per minute; the plugin and Gaanim use 150).

### Video with narration

1. `:Gaanim new video explainer`. One `## key` per narration block in
   `script.md`; in the code, `with scene.voiceover("key") as vo:`.
2. Without recorded takes Gaanim estimates each block's length from its text,
   so the whole video can be animated before recording. The plugin shows
   `○ no take`.
3. Record the takes in the app; `vo.wait_until("word")` syncs to the spoken
   word (tapped marks, then the whisper transcript, then the proportional
   position).
4. `:Gaanim export draft here` to review one part, `:Gaanim export production`
   at the end; `--from`/`--to` with markers or slide names for a range.

### Large decks

One module per slide works: `:Gaanim timeline` runs the scene and lists what it
really made, names built at run time included. The quick `:Gaanim outline`
reads the Python instead; `outline.patterns` teaches it the project's
convention, such as `NAME = "Cover"` in each module.

## Ideas taken from other tools

- **Preview tied to the cursor.** typst-preview.nvim talks to its server over a
  websocket: the editor sends `panelScrollTo` as the cursor moves and the
  preview sends `editorScrollTo` on a click. Gaanim's `--listen` follows that
  model with `follow` and `playhead`.
- **Timeline driven by audio events.** Motion Canvas names instants
  (`waitUntil('event')`) that can be dragged in its editor to line up with the
  voice. Gaanim's `vo.wait_until("word")` is the equivalent.
- **Open in the editor from everywhere.** Remotion opens compositions,
  sequences and error frames in the editor, and scopes renders with in and out
  marks; `export ... here` and `--from`/`--to` by name cover that.
- **Notes that advance by themselves.** Slidev highlights the part of the notes
  for each click (`[click]`); Gaanim does it with `[stop]` and its prompter.
- **Presenting from the terminal.** presenterm.nvim offers slide motions, a
  picker, a statusline component and time estimates.
- **Captions.** Remotion normalizes transcriptions into one caption type. SRT
  puts a comma before the milliseconds and numbers its cues; WebVTT has a
  `WEBVTT` header and a dot.

## Roadmap

Done since the first version: driving the preview (`here`, `follow`, `seek`,
`play`, `pause`), the playhead in the code and the statusline, the script
following the slide on screen, `:Gaanim timeline`, the cursor's instant,
stills and ranges at the cursor, JSON messages, Typst math completion, Python
completion from the `.venv`, Nerd Font icons and lazy loading.

Next, in the plugin alone:

1. **Outline with Tree-sitter.** A query of its own
   (`queries/python/gaanim_outline.scm`) instead of text patterns for the quick
   outline: names in calls over several lines, `live_take`, no false matches in
   docstrings.
2. **From script to code.** Create the `segment` / `voiceover` / `stop` calls
   that `script.md`'s `##` sections and `[stop]` marks ask for: the reverse of
   `script goto`.
3. **Take inspector.** Read `narration/<key>.json` (words and times), warn when
   a `wait_until("…")` is not in the transcript (it would fall back to the
   proportional position), and play from a word.
4. **Real take lengths** next to the estimate and the `target=`, from
   `inspect`'s voiceover times.
5. **Typst highlighting** inside math strings, through Tree-sitter injections
   (`; extends`), once the Typst parser is installed.
6. **Stills in the terminal.** snacks.image speaks only the kitty graphics
   protocol (kitty, Ghostty, WezTerm with limits); Windows Terminal has sixel
   since 1.22 but not that protocol, so stills open in the system viewer.
7. **Presenting helpers:** pick a monitor, ask for the duration, a notes PDF in
   one step.
8. **Releases:** `vX.Y.Z` tags (lazy.nvim and `vim.pack` pin them) and luarocks
   through luarocks-tag-release if it is distributed further.

Still to ask of Gaanim:

- **Captions and chapters from the CLI** (#430, #427) and word times from
  Python (#429).
- **Narration from the CLI:** `gaanim narration record|transcribe <key>`, to
  reuse the app's recorder, whisper and sidecar format.
- **Load failures with their line in JSON.** With `--message-format json`, a
  `check` that cannot load the script reports `file` and `line` as null; the
  traceback inside the message names them, and the plugin reads them from
  there.

## Known limits

- With a Gaanim older than `--listen`, `preview here` restarts the preview.
- `--remote-expr` does not bring the terminal to the front: the jump reaches
  Neovim and says so, but switching windows is up to you.
- On Windows, Neovim's child processes end with it (libuv puts them in a job
  object with `KILL_ON_JOB_CLOSE`), so `preview.stop_on_exit` is the natural
  setting.
- `:Gaanim timeline` and the cursor's instant run the scene through
  `inspect` (about a second for a short talk); they refresh after a save.

## Sources

- Plugin practices: https://github.com/lumen-oss/nvim-best-practices
- Neovim 0.12: `:h news-0.12`, `:h progress-message`, `:h vim.pack`, `:h remote.txt`
- Windows Terminal progress (OSC 9;4): https://learn.microsoft.com/en-us/windows/terminal/tutorials/progress-bar-sequences
- typst-preview.nvim: https://github.com/chomosuke/typst-preview.nvim
- presenterm.nvim: https://github.com/Piotr1215/presenterm.nvim
- overseer.nvim: https://github.com/stevearc/overseer.nvim/blob/master/doc/guides.md
- snacks.nvim (picker, image): https://github.com/folke/snacks.nvim/tree/main/docs
- Windows Terminal and sixel: https://devblogs.microsoft.com/commandline/windows-terminal-preview-1-22-release
- Motion Canvas time events: https://motioncanvas.io/docs/time-events
- Remotion captions and open in editor: https://www.remotion.dev/docs/captions/api, https://remotion.dev/docs/studio/open-in-editor
- Slidev click markers: https://sli.dev/features/click-marker
- WebVTT: https://www.w3.org/TR/webvtt1/
- Two-column scripts: https://www.studiobinder.com/templates/av-scripts/two-column-script-template/
- Pyright configuration: https://github.com/microsoft/pyright/blob/main/docs/configuration.md
