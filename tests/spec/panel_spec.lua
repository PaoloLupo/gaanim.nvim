-- The playback panel, without a preview: commands go to a stub, and the
-- timeline is the recorded `gaanim inspect` of the fixture.

local inspect = require("gaanim.inspect")
local panel = require("gaanim.panel")
local preview = require("gaanim.preview")

local root = vim.fs.normalize(vim.fs.joinpath(FIXTURES, "talk"))

local function timeline()
  local text = table.concat(vim.fn.readfile(vim.fs.joinpath(FIXTURES, "talk.inspect.json")), "\n")
  return vim.json.decode((text:gsub("{root}", root)), { luanil = { object = true, array = true } })
end

--- The fixture project with a preview resting at `playhead`; returns the
--- project and the commands the panel sends.
local function setup(playhead)
  inspect.cache[root] = { data = timeline(), stale = false }
  local project = assert(require("gaanim.project").load(root))
  preview.status[root] = { state = "ready", key = "preview:" .. root, listen = true, queue = {}, playhead = playhead }
  local sent = {}
  local send = preview.send
  preview.send = function(_, command)
    table.insert(sent, command)
    return true
  end
  return project,
    sent,
    function()
      preview.send = send
      preview.status[root] = nil
      inspect.cache[root] = nil
    end
end

describe("playback panel", function()
  it("lays the slides out as long as they last", function()
    local blocks = panel.blocks(timeline().segments, 2.8, 30)
    local widths, total = {}, 0
    for _, block in ipairs(blocks) do
      table.insert(widths, block.width)
      total = total + block.width
    end
    eq({ 8, 10, 10 }, widths)
    eq(30, total + #blocks - 1, "the blocks and the cells between them fill the width")
    eq(3, #panel.blocks(timeline().segments, 2.8, 4), "every slide keeps a cell")
  end)

  it("runs the time on while the preview plays, around a loop", function()
    local project, _, done = setup({ time = 1.0, playing = true })
    eq(1.5, panel.time({ project = project, heard = { time = 1.0, at = 10 } }, 10.5))
    preview.status[root].playhead.loop = { 0.8, 1.8 }
    local wrapped = panel.time({ project = project, heard = { time = 1.6, at = 10 } }, 10.4)
    eq(true, math.abs(wrapped - 1.0) < 1e-9, "back to the loop's start")
    preview.status[root].playhead = { time = 1.0, playing = false }
    eq(1.0, panel.time({ project = project, heard = { time = 1.0, at = 10 } }, 99), "paused, it stays")
    done()
  end)

  it("plays, pauses, moves between slides and loops the one it rests on", function()
    local project, sent, done = setup({ time = 1.5, segment = "Problem", playing = false })
    local p = { project = project }
    panel.act(p, "toggle")
    panel.act(p, "next")
    panel.act(p, "prev")
    panel.act(p, "loop")
    panel.act(p, "back")
    eq({
      { cmd = "play" },
      { cmd = "seek", segment = "Closing" },
      { cmd = "seek", segment = "Problem" },
      { cmd = "loop", segment = "Problem" },
      { cmd = "seek", time = 0.5 },
    }, sent)
    preview.status[root].playhead = { time = 0.9, segment = "Problem", playing = true, loop = { 0.8, 1.8 } }
    sent = {}
    preview.send = function(_, command)
      table.insert(sent, command)
      return true
    end
    panel.act(p, "toggle")
    panel.act(p, "prev")
    panel.act(p, "loop")
    eq({ { cmd = "pause" }, { cmd = "seek", segment = "Cover" }, { cmd = "unloop" } }, sent)
    done()
  end)

  it("seeks where the scrubber and the slides are clicked", function()
    if not panel.available() then
      io.stdout:write("skip: volt (PaoloLupo/volt) is not on the runtimepath\n")
      return
    end
    local project, sent, done = setup({ time = 0, segment = "Cover", playing = false })
    vim.o.columns = 104
    panel.open(project)
    eq(true, panel.is_open())
    local buf = vim.api.nvim_get_current_buf()
    local events = require("volt.events")
    -- 96 columns wide, 92 inside: the scrubber is row 2, the slides row 3.
    events.click(buf, 2, 2 + 46)
    eq({ cmd = "seek", time = 1.4 }, sent[1])
    local blocks = panel.blocks(timeline().segments, 2.8, 92)
    events.click(buf, 3, 2 + blocks[1].width + 1)
    eq({ cmd = "seek", segment = "Problem" }, sent[2], "the first cell of a slide is that slide's")
    local slides = vim.api.nvim_buf_get_extmarks(buf, -1, { 2, 0 }, { 2, -1 }, { details = true })[1][4].virt_text
    eq(
      { "Cover", "GaanimPanelSegmentOn" },
      { vim.trim(slides[1][1]), slides[1][2] },
      "the slide it rests on stands out"
    )
    panel.close()
    eq(false, panel.is_open())
    eq({}, events.bufs, "volt stops hearing the mouse")
    done()
  end)
end)
