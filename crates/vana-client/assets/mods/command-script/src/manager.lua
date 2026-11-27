-- Script library and editor (Hotbars-style tiles and tabs).

local data = require("src.data")
local jobs = require("src.jobs")
local runner = require("src.runner")

local M = {}

M.hooks = { changed = function() end, run = function(word) runner.run(word) end }

local WIN = "cs_mgr"
local TAB_LIB, TAB_HELP = 1, 2

local S = { job = nil }
local defined = false
local building = false

local E = { word = "", scope = "job", lines = "", editing = nil }

local CW, T, TG = 480, 52, 6
local COLS = math.floor((CW + TG) / (T + TG))
local TILE = { 10, 17, 24, 255 }
local TILE_HOVER = { 20, 33, 44, 255 }
local TILE_EDGE = { 184, 139, 73, 205 }
local TILE_SEL = { 255, 214, 120, 255 }
local TILE_TEXT = { 236, 230, 214, 255 }
local INK = { 200, 195, 185, 255 }
local HEAD = { 255, 214, 120, 255 }

local tiles = {}
local L = { sel = nil, hover = nil }

local function say(msg)
  chat.add("Command Script: " .. msg)
end

local function short(text, n)
  n = n or math.max(1, math.floor((T - 6) / (6.5 * 0.72)))
  text = tostring(text or "")
  if utf8.len(text) and utf8.len(text) > n then
    return text:sub(1, utf8.offset(text, n) - 1) .. "..."
  end
  return text
end

local function tile_xy(n)
  return ((n - 1) % COLS) * (T + TG), ((n - 1) // COLS) * (T + TG)
end

local function tile_at(x, y)
  for n = 1, #tiles do
    local tx, ty = tile_xy(n)
    if x >= tx and x < tx + T and y >= ty and y < ty + T then return n end
  end
end

local function preview(entry)
  local lines = entry.lines or {}
  local n = #lines
  if n == 0 then return "empty" end
  if n == 1 then return lines[1] end
  return ("%d lines"):format(n)
end

local function refresh_tiles()
  tiles = {}
  for _, row in ipairs(data.sorted(S.job)) do
    tiles[#tiles + 1] = {
      word = row.word,
      scope = row.entry.scope,
      label = row.word,
      tip = table.concat(row.entry.lines or {}, "\n"),
    }
  end
  local d = {}
  local function add(c) d[#d + 1] = c end
  for n, t in ipairs(tiles) do
    local x, y = tile_xy(n)
    add({ type = "rect", x = x, y = y, w = T, h = T, round = 7, colour = L.hover == n and TILE_HOVER or TILE })
    local sel = L.sel == t.word
    add({ type = "rect", x = x, y = y, w = T, h = T, round = 7, line = sel and 2.5 or 1.5,
      colour = sel and TILE_SEL or TILE_EDGE })
    add({ type = "text", x = x + T / 2, y = y + 10, text = short(t.label, 8), size = 0.78, align = "center",
      colour = TILE_TEXT })
    add({ type = "text", x = x + T / 2, y = y + T - 16, text = short(preview(data.get(t.word, S.job)), 10),
      size = 0.65, align = "center", colour = { 160, 170, 190, 255 } })
    add({ type = "tip", x = x, y = y, w = T, h = T, title = "//cs " .. t.word,
      text = (t.scope == "ALL" and "Every job.\n\n" or (t.scope .. " only.\n\n")) .. t.tip })
  end
  local rows = math.max(1, math.ceil(#tiles / COLS))
  ui.update(WIN, "tiles", { h = rows * (T + TG) - TG, draw = d })
  local sel = L.sel and data.get(L.sel, S.job)
  ui.update(WIN, "lsel", { text = sel and ('//cs %s (%s): %s'):format(L.sel, sel.scope, preview(sel))
    or "Pick a script, then Run or Edit." })
end

local function refresh_ctx()
  ui.update(WIN, "lctx", { text = ("Scripts for %s (%d). Click a tile to select; double-click Run."):format(
    S.job or "?", #tiles) })
  ui.update(WIN, "job", { text = S.job or "" })
end

local HELP_LINES = 12
local HELP = {
  { "Command Script" },
  "//cs <word> runs a saved script. //cs opens this window.",
  "Scripts are stored per main job; ALL applies to every job.",
  { "Lines" },
  "Each line is a game command. wait 2 pauses two seconds.",
  "then /ja \"X\" <t> runs after the previous ws/ja/ma/pet finishes, plus the link gap.",
  "burst <command> is the same with no link gap.",
  "//cs stop stops a running script.",
  { "Editor" },
  "New / Edit: a word and lines separated by | (or ;).",
  "Example: /ja \"Provoke\" <t> | then /ws \"Fast Blade\" <t>",
  "Run fires the selected script without leaving the window.",
}

local function refresh_help()
  for i = 1, HELP_LINES do
    local l = HELP[i]
    local head = type(l) == "table"
    ui.update(WIN, "help" .. i, { text = (head and l[1] or l) or "", colour = head and HEAD or INK })
  end
end

local function open_builder(word)
  building = true
  E.editing = word
  if word then
    local e = data.get(word, S.job)
    E.word = word
    E.lines = data.join_lines(e and e.lines or {})
    E.scope = (e and e.scope == "ALL") and "ALL" or "job"
  else
    E.word = ""
    E.lines = ""
    E.scope = "job"
  end
  layout(true)
  ui.update(WIN, "bword", { text = E.word })
  ui.update(WIN, "bscope", { at = E.scope == "ALL" and 2 or 1 })
  ui.update(WIN, "blines", { text = E.lines })
  ui.update(WIN, "bwhere", { text = word and ("Editing //cs " .. word) or "New script" })
end

local function leave_builder()
  building = false
  layout(false)
  refresh_tiles()
end

local function save_builder()
  local word = data.sanitize_word(E.word ~= "" and E.word or "")
  if not word then
    say("Give the script a word (letters, digits, _ or -).")
    return
  end
  local lines = data.split_lines(E.lines)
  if #lines == 0 then
    say("Add at least one command line.")
    return
  end
  local scope = E.scope == "ALL" and "ALL" or (S.job or select(1, jobs.current()) or "ALL")
  if E.editing and E.editing ~= word then
    local old = data.get(E.editing, S.job)
    if old then data.remove(E.editing, old.scope) end
  end
  local ok, err = data.set(word, lines, scope)
  if not ok then
    say("Could not save: " .. tostring(err))
    return
  end
  say(('Saved //cs %s (%s).'):format(word, scope))
  M.hooks.changed()
  L.sel = word
  leave_builder()
end

local function delete_selected()
  if not L.sel then return end
  local e = data.get(L.sel, S.job)
  if not e then return end
  if data.remove(L.sel, e.scope) then
    say("Removed //cs " .. L.sel .. ".")
    L.sel = nil
    M.hooks.changed()
    refresh_tiles()
    refresh_ctx()
  end
end

local function on_tiles(e)
  if e.kind == "click" then
    local n = tile_at(e.x, e.y)
    if not n then return end
  local t = tiles[n]
    if e.button == "right" then
      L.sel = t.word
      open_builder(t.word)
    else
      L.sel = t.word
      refresh_tiles()
    end
  elseif e.kind == "hover" or e.kind == "leave" then
    local n = e.kind == "hover" and tile_at(e.x, e.y) or nil
    if n ~= L.hover then
      L.hover = n
      refresh_tiles()
    end
  end
end

local SCOPE_ITEMS = { "This job", "Every job (ALL)" }

local function spec(build)
  if build then
    return {
      title = "Command Script",
      width = 560,
      help = "Save keeps the script; Cancel returns to the library.",
      elements = {
        { type = "buttons", id = "bbar", items = { "Save", "Cancel" } },
        { type = "text", id = "bwhere", text = "" },
        { type = "input", id = "bword", label = "Word (//cs <word>)", text = "", max = 24,
          tip = "Letters, digits, underscore and hyphen only." },
        { type = "choice", id = "bscope", label = "Scope", items = SCOPE_ITEMS, at = 1,
          tip = "This job: only when your main job matches. ALL: every job." },
        { type = "input", id = "blines", label = "Lines (| between lines)", text = "", max = 2048,
          tip = 'Example: /ja "Provoke" <t> | then /ws "Fast Blade" <t> | wait 1 | /echo done' },
      },
    }
  end
  local elements = {
    { type = "tabs", id = "tabs", items = { "Scripts", "Help" }, at = TAB_LIB },
    { type = "input", id = "job", label = "Job", text = "", max = 3, page = TAB_LIB,
      tip = "Main job whose scripts to show (ALL entries always show too), e.g. RDM." },
    { type = "text", id = "lctx", text = "", page = TAB_LIB },
    { type = "canvas", id = "tiles", w = CW, h = T, page = TAB_LIB },
    { type = "text", id = "lsel", text = "", dim = true, page = TAB_LIB },
    { type = "buttons", id = "lbtn", items = { "New", "Edit", "Delete", "Run" }, page = TAB_LIB },
  }
  for i = 1, HELP_LINES do
    elements[#elements + 1] = { type = "text", id = "help" .. i, text = "", page = TAB_HELP }
  end
  return {
    title = "Command Script",
    width = 520,
    help = "Named scripts you run with //cs <word>.",
    elements = elements,
  }
end

function layout(build)
  building = build
  ui.window(WIN, spec(build))
end

local function refresh_all()
  refresh_ctx()
  refresh_tiles()
  refresh_help()
end

local function define()
  ui.window(WIN, spec(false))
  building = false
  ui.on(WIN, function(_, e)
    if e.id == "tiles" then
      on_tiles(e)
    elseif e.kind == "edit" or (e.kind == "change" and (e.id == "bword" or e.id == "blines")) then
      if e.id == "bword" then E.word = e.text
      elseif e.id == "blines" then E.lines = e.text end
    elseif e.kind == "set" and e.id == "bscope" then
      E.scope = e.index == 2 and "ALL" or "job"
    elseif e.kind == "change" and e.id == "job" then
      local job = jobs.parse(e.text)
      if job == "ALL" then
        S.job = "ALL"
      elseif job then
        S.job = job
      else
        say(('"%s" is not a job (three letters, e.g. RDM).'):format(data.trim(e.text)))
      end
      refresh_all()
    elseif e.kind == "press" then
      if e.id == "lbtn" then
        if e.index == 1 then
          open_builder(nil)
        elseif e.index == 2 then
          if L.sel then open_builder(L.sel) end
        elseif e.index == 3 then
          delete_selected()
        elseif e.index == 4 and L.sel then
          M.hooks.run(L.sel)
        end
      elseif e.id == "bbar" then
        if e.index == 1 then save_builder()
        else leave_builder() end
      end
    end
  end)
  defined = true
end

local function ensure()
  if not defined then define() end
end

function M.refresh()
  if defined and not building then refresh_all() end
end

function M.open()
  ensure()
  S.job = jobs.current() or S.job or "ALL"
  layout(false)
  refresh_all()
  ui.open(WIN)
end

function M.toggle()
  ensure()
  if ui.is_open(WIN) then ui.close(WIN) else M.open() end
end

return M