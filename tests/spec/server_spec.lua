-- The Gaanim language server, live mode and nudges, without running gaanim:
-- the timeline comes from the recorded `gaanim inspect` of the fixture.

local inspect = require("gaanim.inspect")

local root = vim.fs.normalize(vim.fs.joinpath(FIXTURES, "talk"))
local main = vim.fs.joinpath(root, "main.py")

local function timeline()
  local text = table.concat(vim.fn.readfile(vim.fs.joinpath(FIXTURES, "talk.inspect.json")), "\n")
  return vim.json.decode((text:gsub("{root}", root)), { luanil = { object = true, array = true } })
end

--- Opens the fixture with the server attached and a known timeline.
---@return integer buf
local function open()
  vim.cmd("silent! %bwipeout!")
  inspect.cache[root] = { data = timeline(), stale = false }
  vim.cmd.edit(vim.fn.fnameescape(main))
  local buf = vim.api.nvim_get_current_buf()
  vim.wait(2000, function()
    return #vim.lsp.get_clients({ bufnr = buf, name = "gaanim" }) > 0
  end, 20)
  return buf
end

local function request(buf, method, params)
  params = vim.tbl_extend("force", { textDocument = { uri = vim.uri_from_bufnr(buf) } }, params or {})
  local responses = vim.lsp.buf_request_sync(buf, method, params, 3000) or {}
  for id, response in pairs(responses) do
    local client = vim.lsp.get_client_by_id(id)
    if client and client.name == "gaanim" then
      return response.result
    end
  end
end

local function close()
  vim.cmd("silent! bwipeout!")
  inspect.cache[root] = nil
end

describe("language server", function()
  it("attaches to the Python files of a project", function()
    local buf = open()
    eq(1, #vim.lsp.get_clients({ bufnr = buf, name = "gaanim" }))
    close()
  end)

  it("shows the time of each line as an inlay hint", function()
    local buf = open()
    local hints = request(buf, "textDocument/inlayHint", {
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 40, character = 0 } },
    })
    local by_line = {}
    for _, hint in ipairs(hints or {}) do
      by_line[hint.position.line + 1] = hint.label
    end
    local icons = require("gaanim.icons").get()
    eq(icons.segment .. " 0:00.0–0:00.8 · 0.8s", by_line[10])
    eq(icons.playing .. " 0:00.0–0:00.8", by_line[13])
    eq(icons.stop .. " 0:01.3", by_line[23])
    eq(icons.marker .. " 0:01.3", by_line[24])
    eq(icons.voiceover .. " 0:01.8–0:02.6", by_line[28])
    eq(nil, by_line[5])
    close()
  end)

  it("speaks in byte offsets, so hints after accents stay on their line", function()
    local buf = open()
    local client = vim.lsp.get_clients({ bufnr = buf, name = "gaanim" })[1]
    eq("utf-8", client.offset_encoding)
    -- Line 13 holds a play; give it accents and save, as an author would.
    local row = 13
    local text = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] .. "  # ¿qué pasó?"
    vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { text })
    vim.bo[buf].modified = false
    local hints = request(buf, "textDocument/inlayHint", {
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 40, character = 0 } },
    })
    for _, hint in ipairs(hints or {}) do
      if hint.position.line == row - 1 then
        eq(#text, hint.position.character)
      end
    end
    close()
  end)

  it("hears each edit, so the client asks for hints again", function()
    local buf = open()
    local client = vim.lsp.get_clients({ bufnr = buf, name = "gaanim" })[1]
    eq(2, client.server_capabilities.textDocumentSync.change)
    local notified = false
    vim.api.nvim_create_autocmd("LspNotify", {
      buffer = buf,
      callback = function(args)
        if args.data.client_id == client.id and args.data.method == "textDocument/didChange" then
          notified = true
        end
      end,
    })
    vim.api.nvim_buf_set_text(buf, 12, 0, 12, 20, { "" })
    vim.wait(2000, function()
      return notified
    end, 20)
    eq(true, notified, "an edit reaches the server, and hints wait for the save")
    close()
  end)

  it("keeps another server's hints within a line it has not seen shortened", function()
    -- Neovim 0.13 draws each client's hints only at their own version, and
    -- asks for them only when it draws, which a headless test never does.
    if vim.fn.has("nvim-0.13") == 1 then
      return
    end
    local buf = open()
    -- A server like basedpyright: it answers once, then is slow after edits.
    local answered = false
    vim.lsp.start({
      name = "other",
      cmd = function()
        return {
          request = function(method, _, callback)
            if method == "initialize" then
              vim.schedule(function()
                callback(nil, { capabilities = { inlayHintProvider = true, textDocumentSync = 2 } })
              end)
            elseif method == "textDocument/inlayHint" and not answered then
              answered = true
              local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
              vim.schedule(function()
                callback(nil, { { position = { line = 0, character = #line }, label = "x" } })
              end)
            end
            return true, 1
          end,
          notify = function()
            return true
          end,
          is_closing = function()
            return false
          end,
          terminate = function() end,
        }
      end,
    }, { bufnr = buf })
    local function other_hint()
      for _, item in ipairs(vim.lsp.inlay_hint.get({ bufnr = buf })) do
        if vim.lsp.get_client_by_id(item.client_id).name == "other" then
          return item.inlay_hint
        end
      end
    end
    vim.wait(2000, function()
      return other_hint() ~= nil
    end, 20)
    -- gaanim answers the edit at once; the other server never does.
    vim.api.nvim_buf_set_text(buf, 0, 0, 0, 5, { "" })
    vim.wait(300)
    local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    eq(true, other_hint().position.character <= #line, "the hint is drawn within its line")
    vim.lsp.get_clients({ bufnr = buf, name = "other" })[1]:stop(true)
    close()
  end)

  it("hides hints while the buffer has unsaved changes", function()
    local buf = open()
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "# changed" })
    local hints = request(buf, "textDocument/inlayHint", {
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 40, character = 0 } },
    })
    eq(nil, hints)
    close()
  end)

  it("puts lenses over slides and voiceovers", function()
    local buf = open()
    local lenses = request(buf, "textDocument/codeLens") or {}
    local titles = {}
    for _, lens in ipairs(lenses) do
      local line = lens.range.start.line + 1
      titles[line] = titles[line] or {}
      table.insert(titles[line], lens.command.title)
    end
    local icons = require("gaanim.icons").get()
    eq({
      icons.playing .. " Preview",
      icons.loop .. " Loop",
      icons.still .. " Still",
      icons.voiceover .. " ≈0:04 / 0:30",
      icons.time .. " 0:00.0–0:00.8",
    }, titles[10])
    eq(icons.voiceover .. " no take yet", titles[28][1])
    eq("gaanim.preview", lenses[1].command.command)
    close()
  end)

  it("offers to end the loop on the slide being looped", function()
    local buf = open()
    local preview = require("gaanim.preview")
    preview.status[root] = {
      state = "ready",
      key = "preview:" .. root,
      listen = true,
      queue = {},
      playhead = { time = 1, segment = "Problem", playing = true, loop = { 0.8, 1.8 } },
    }
    local icons = require("gaanim.icons").get()
    local by_line = {}
    for _, lens in ipairs(request(buf, "textDocument/codeLens") or {}) do
      local line = lens.range.start.line + 1
      by_line[line] = by_line[line] or {}
      table.insert(by_line[line], lens.command.title)
    end
    assert(vim.tbl_contains(by_line[17], icons.unloop .. " Unloop"), vim.inspect(by_line[17]))
    assert(vim.tbl_contains(by_line[10], icons.loop .. " Loop"))
    preview.status[root] = nil
    close()
  end)

  it("describes a line's timeline on hover", function()
    local buf = open()
    local result = request(buf, "textDocument/hover", { position = { line = 22, character = 20 } })
    assert(result and result.contents.value:find("stop `question` · 0:01.3 · 1 of 2 in **Problem**", 1, true))
    eq(nil, request(buf, "textDocument/hover", { position = { line = 4, character = 2 } }))
    close()
  end)

  it("lists slides and what they hold as document symbols", function()
    local buf = open()
    local symbols = request(buf, "textDocument/documentSymbol") or {}
    local names = vim.tbl_map(function(symbol)
      return symbol.name .. ":" .. #symbol.children
    end, symbols)
    eq({ "Cover:1", "Problem:3", "Closing:2" }, names)
    close()
  end)

  it("completes Typst math and asset names", function()
    local buf = open()
    vim.api.nvim_buf_set_lines(
      buf,
      -1,
      -1,
      false,
      { 'eq = scene.text.equation("x + al', 'img = scene.media.image("lo' }
    )
    local count = vim.api.nvim_buf_line_count(buf)
    local math = request(buf, "textDocument/completion", { position = { line = count - 2, character = 31 } })
    local found = false
    for _, item in ipairs(math and math.items or {}) do
      found = found or (item.label == "alpha" and item.kind_icon == "α")
    end
    eq(true, found)
    local files = request(buf, "textDocument/completion", { position = { line = count - 1, character = 27 } })
    eq("logo.png", files.items[1].label)
    eq(
      { start = { line = count - 1, character = 25 }, ["end"] = { line = count - 1, character = 27 } },
      files.items[1].textEdit.range,
      "the edit replaces what was typed in the string"
    )
    close()
  end)

  it("warns about asset names that resolve to no file", function()
    local buf = open()
    vim.api.nvim_buf_set_lines(
      buf,
      -1,
      -1,
      false,
      { 'a = scene.media.image("logo.png")', 'b = scene.media.svg("missing.svg")' }
    )
    local diagnostics = require("gaanim.server.assets").diagnostics(require("gaanim.project").load(root), buf)
    eq(1, #diagnostics)
    assert(diagnostics[1].message:find("missing.svg", 1, true))
    close()
  end)

  it("offers actions for the line", function()
    local buf = open()
    local function titles(line)
      local actions = request(buf, "textDocument/codeAction", {
        range = { start = { line = line - 1, character = 0 }, ["end"] = { line = line - 1, character = 0 } },
        context = { diagnostics = {} },
      }) or {}
      return vim.tbl_map(function(action)
        return action.title
      end, actions)
    end
    assert(vim.tbl_contains(titles(25), "Name this stop"))
    assert(vim.tbl_contains(titles(28), "Write the text of “outro”"))
    assert(vim.tbl_contains(titles(17), "Open the script of “Problem”"))
    assert(vim.tbl_contains(titles(5), "Export the frame of this line"))
    close()
  end)

  it("names a stop and adds a marker through its commands", function()
    local buf = open()
    local input = vim.ui.input
    vim.ui.input = function(_, on_confirm)
      on_confirm("last")
    end
    local commands = require("gaanim.server.commands").commands
    commands["gaanim.nameStop"]({ vim.uri_from_bufnr(buf), 25 })
    eq('scene.wait(0.5); scene.stop("last")', vim.api.nvim_buf_get_lines(buf, 24, 25, false)[1])
    commands["gaanim.addMarker"]({ vim.uri_from_bufnr(buf), 29 })
    eq('    scene.marker("last")', vim.api.nvim_buf_get_lines(buf, 29, 30, false)[1])
    vim.ui.input = input
    close()
  end)
end)

describe("nudge", function()
  local nudge = require("gaanim.nudge")

  it("finds the number at or after the cursor, not inside names", function()
    eq({ 16, 18, "0.8" }, { nudge.find("t.duration(x2, 0.8)", 0) })
    eq({ 11, 11, "1" }, { nudge.find("value = x-1", 0) })
    eq({ 7, 10, "-0.5" }, { nudge.find("shift(-0.5)", 3) })
  end)

  it("steps by the number's own precision", function()
    eq("0.9", nudge.step("0.8", 1))
    eq("0.24", nudge.step("0.25", -1))
    eq("5", nudge.step("3", 2))
    eq("0.0", nudge.step("0.1", -1))
    eq("-0.1", nudge.step("0.0", -1))
  end)
end)

describe("live mode", function()
  it("writes a changed file once the changes settle, without autocommands", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    for _, name in ipairs({ "gaanim.toml", "main.py" }) do
      vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(root, name)), vim.fs.joinpath(dir, name))
    end
    local config = require("gaanim.config")
    config.setup({ live = { delay = 20 } })
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(dir, "main.py")))
    local buf = vim.api.nvim_get_current_buf()
    local live = require("gaanim.live")
    live.enabled[vim.fs.normalize(dir)] = true
    local wrote_hook = false
    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = buf,
      once = true,
      callback = function()
        wrote_hook = true
      end,
    })
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "# live" })
    live.on_change(buf, false)
    vim.wait(1000, function()
      return not vim.bo[buf].modified
    end, 10)
    eq(false, vim.bo[buf].modified)
    eq("# live", vim.fn.readfile(vim.fs.joinpath(dir, "main.py"))[1])
    eq(false, wrote_hook, "formatters and other write hooks do not run")
    live.enabled[vim.fs.normalize(dir)] = nil
    config.setup()
    vim.cmd("silent! bwipeout!")
  end)
end)
