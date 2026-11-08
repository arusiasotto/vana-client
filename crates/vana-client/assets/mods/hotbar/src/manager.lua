-- The macro manager window.
--
--   Library  a main job's macros as tiles, dragged onto the bars: new, edit, copy, delete, and the palette.
--   Builder  one macro: an action of a type (spell, job ability, weapon skill, pet command, item, equipment, system
--            command) and its target build the first line; lines typed under it run after it. A "Macro" is typed only.
--   Config   the hotkey modifier of each bar, the key row, and a slot's own key (changes apply at once).

local data = require("src.data")
local jobs = require("src.jobs")
local keys = require("src.keys")
local actions = require("src.actions")
local builder = require("src.builder")
local palette = require("src.palette")
local ghost = require("src.ghost")

local M = {}

-- Set by init.lua: changed() redraws the bars, rebind() rebinds the hotkeys, palette() shows or hides the palette.
M.hooks = {}

local WIN = "manager"
local TAB_LIB, TAB_BUILD, TAB_CONFIG = 1, 2, 3

local S = { mj = nil }
local defined = false

-- The library rows as shown (ids, in order) and the builder's state: the entry edited (nil: a new one), the action
-- kind (nil: a macro of typed lines), the action picked ({name}), its target, the search results, and the slot it was
-- opened from ({bar, slot, main, sub}: the saved macro goes on it), if any.
local lib_ids = {}
local open_builder
local E = { id = nil, kind = "ma", pick = nil, target = "t", results = {}, auto_name = nil, slot = nil }
-- The Config tab's slot whose own key is set there.
local K = { bar = 1, slot = 1 }

local function say(msg)
  chat.add("Hotbars: " .. msg)
end

-- The icon a list row shows for a macro, from its first action.
local function row_icon(macro)
  local a = macro and actions.of(macro)
  if not a then return nil end
  return { kind = a.kind, id = a.id }
end

-- ---------------------------------------------------------------------------
-- Library
-- ---------------------------------------------------------------------------

local function does_text(entry)
  local first = data.command(entry.action)
  local n = #(entry.lines or {})
  if first then
    return n > 0 and ("%s  +%d"):format(first, n) or first
  end
  return n == 1 and entry.lines[1] or ("%d lines"):format(n)
end

-- ---------------------------------------------------------------------------
-- Library: the job's macros as tiles
-- ---------------------------------------------------------------------------

local CW, T, TG = 480, 52, 6                      -- the canvas's width, a tile's size, the gap between tiles
local COLS = math.floor((CW + TG) / (T + TG))
local TILE = { 10, 17, 24, 255 }
local TILE_HOVER = { 20, 33, 44, 255 }
local TILE_EDGE = { 184, 139, 73, 205 }
local TILE_SEL = { 255, 214, 120, 255 }
local TILE_TEXT = { 236, 230, 214, 255 }
local GHOST_BG = { 20, 24, 38, 160 }
local GHOST_INK = { 255, 255, 255, 170 }

-- The tiles shown: {id, entry, act, label, lines}; the chosen one's id; the tile under the pointer; a tile's drag
-- ({n, x, y}: where in the canvas, nil x while it is over another window).
local tiles = {}
local L = { sel = nil, hover = nil, drag = nil }

local function tile_xy(n)
  return ((n - 1) % COLS) * (T + TG), ((n - 1) // COLS) * (T + TG)
end

local function tile_at(x, y)
  for n = 1, #tiles do
    local tx, ty = tile_xy(n)
    if x >= tx and x < tx + T and y >= ty and y < ty + T then return n end
  end
end

local function short(text)
  local n = math.max(1, math.floor((T - 6) / (6.5 * 0.72)))
  if utf8.len(text) and utf8.len(text) > n then
    return text:sub(1, utf8.offset(text, n) - 1) .. "…"
  end
  return text
end

local function draw_tiles()
  local d = {}
  local function add(c) d[#d + 1] = c end
  for n, t in ipairs(tiles) do
    local x, y = tile_xy(n)
    add({ type = "rect", x = x, y = y, w = T, h = T, round = 7, colour = L.hover == n and TILE_HOVER or TILE })
    local sel = L.sel == t.id
    add({ type = "rect", x = x, y = y, w = T, h = T, round = 7, line = sel and 2.5 or 1.5,
      colour = sel and TILE_SEL or TILE_EDGE })
    if t.act then
      local isz = math.floor(T * 0.58)
      add({ type = "icon", x = x + (T - isz) / 2, y = y + 4, size = isz, kind = t.act.kind, id = t.act.id })
      add({ type = "text", x = x + T / 2, y = y + T - 14, text = short(t.label:match("^[^\n]*")), size = 0.72,
        align = "center", colour = TILE_TEXT })
    else
      local ls = {}
      for l in t.label:gmatch("[^\n]+") do ls[#ls + 1] = l end
      local top = y + (T - #ls * 12) / 2
      for k, l in ipairs(ls) do
        add({ type = "text", x = x + T / 2, y = top + (k - 1) * 12, text = short(l), size = 0.72, align = "center",
          colour = TILE_TEXT })
      end
    end
    if L.drag and L.drag.n == n then
      add({ type = "rect", x = x, y = y, w = T, h = T, round = 7, colour = { 0, 0, 0, 120 } })
    end
    local uses = data.uses(S.mj, t.id)
    add({ type = "tip", x = x, y = y, w = T, h = T, title = t.entry.name or "",
      text = table.concat(t.lines, "\n") .. ("\n\nOn %d slot%s. Drag onto a slot of the bars; click to choose, "
        .. "right-click to edit."):format(uses, uses == 1 and "" or "s") })
  end
  -- The dragged tile under the pointer, while it is over this window.
  local g = L.drag and L.drag.x and tiles[L.drag.n]
  if g then
    local gx, gy = L.drag.x - T / 2, L.drag.y - T / 2
    add({ type = "rect", x = gx, y = gy, w = T, h = T, round = 7, colour = GHOST_BG })
    if g.act then
      local isz = math.floor(T * 0.58)
      add({ type = "icon", x = gx + (T - isz) / 2, y = gy + 4, size = isz, kind = g.act.kind, id = g.act.id,
        colour = GHOST_INK })
    else
      add({ type = "text", x = gx + T / 2, y = gy + T / 2 - 6, text = short(g.label:match("^[^\n]*")), size = 0.72,
        align = "center", colour = GHOST_INK })
    end
  end
  local rows = math.max(1, math.ceil(#tiles / COLS))
  ui.update(WIN, "tiles", { h = rows * (T + TG) - TG, draw = d })
end

local function show_selected()
  local t
  for _, x in ipairs(tiles) do
    if x.id == L.sel then t = x end
  end
  ui.update(WIN, "lsel", { text = t and ('%s: %s; on %d slot%s.'):format(t.entry.name or "?", does_text(t.entry),
    data.uses(S.mj, t.id), data.uses(S.mj, t.id) == 1 and "" or "s") or "Click a macro to choose it." })
end

local function refresh_library(select_id)
  ui.update(WIN, "job", { text = S.mj or "" })
  tiles, lib_ids = {}, {}
  if not S.mj then
    ui.update(WIN, "lctx", { text = "Jobs are not loaded yet." })
    draw_tiles()
    return
  end
  if select_id then L.sel = tostring(select_id) end
  local still = false
  for i, it in ipairs(data.library(S.mj)) do
    lib_ids[i] = it.id
    local lines = data.entry_lines(it.entry)
    tiles[i] = { id = it.id, entry = it.entry, lines = lines, act = actions.of({ lines = lines }),
      label = data.display_label(it.entry) }
    if it.id == L.sel then still = true end
  end
  if not still then L.sel = tiles[1] and tiles[1].id or nil end
  ui.update(WIN, "lctx", {
    text = #tiles == 0 and ("%s has no macros yet: press New."):format(S.mj)
      or ("%s macros: drag one onto a slot of the bars."):format(S.mj),
  })
  draw_tiles()
  show_selected()
end

local function selected_entry()
  return L.sel
end

-- The tiles' events: hover, click to choose, right-click to edit, drag onto the bars.
local function on_tiles(e)
  if e.kind == "hover" or e.kind == "leave" then
    local n = e.kind == "hover" and tile_at(e.x, e.y) or nil
    if n ~= L.hover then
      L.hover = n
      draw_tiles()
    end
  elseif e.kind == "click" then
    local n = tile_at(e.x, e.y)
    if not n then return end
    L.sel = tiles[n].id
    draw_tiles()
    show_selected()
    if e.button == "right" then open_builder(tiles[n].id) end
  elseif e.kind == "drag_start" then
    local n = tile_at(e.x, e.y)
    if not n then return end
    local t = tiles[n]
    L.drag = { n = n, x = e.x, y = e.y }
    -- Only the current main job's macros go on the bars.
    if S.mj == jobs.current() then
      palette.start_drag(t.id, t.act, t.label)
    else
      palette.last = nil
      say(("these are %s's macros; the bars show %s's."):format(S.mj, jobs.current() or "?"))
    end
    if e.sx then ghost.start(e.sx, e.sy, math.floor(settings.get("size") * hud.screen().ui_scale), t.act, t.label) end
    draw_tiles()
  elseif e.kind == "drag" and L.drag then
    -- Over this window it draws the tile itself; over another of ours that one does; between them the HUD's ghost.
    local inside = e.x >= 0 and e.y >= 0 and e.x < CW and e.y < math.max(1, math.ceil(#tiles / COLS)) * (T + TG)
    L.drag.x, L.drag.y = inside and e.x or nil, e.y
    if e.sx then
      if inside or e.window then ghost.move(-10000, -10000) else ghost.move(e.sx, e.sy) end
    end
    draw_tiles()
  elseif e.kind == "drag_end" and L.drag then
    L.drag = nil
    ghost.stop()
    palette.end_drag()
    draw_tiles()
  end
end

local function copy_selected()
  local id = selected_entry()
  local entry = id and data.get_entry(S.mj, id)
  if not entry then return end
  local copy = {}
  for k, v in pairs(entry) do copy[k] = v end
  copy.name = (entry.name or "") .. " (copy)"
  refresh_library(data.save_entry(S.mj, nil, copy))
  M.hooks.changed()
end

local function delete_selected()
  local id = selected_entry()
  local entry = id and data.get_entry(S.mj, id)
  if not entry then return end
  local mj = S.mj
  local n = data.uses(mj, id)
  local text = n > 0 and ('Delete "%s"? It is on %d slot%s, which will be emptied.'):format(entry.name, n,
    n == 1 and "" or "s") or ('Delete "%s"?'):format(entry.name)
  ui.prompt(text, { "Delete", "Cancel" }, function(i)
    if i == 1 then
      data.delete_entry(mj, id)
      M.hooks.changed()
      refresh_library()
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Builder
-- ---------------------------------------------------------------------------

local function type_def()
  return builder.TYPES[builder.type_index(E.kind)]
end

local function builder_entry()
  local action = nil
  if E.kind and E.pick then
    action = { kind = E.kind, name = E.pick.name, target = E.target }
  end
  return {
    name = ui.get(WIN, "name").text,
    label = ui.get(WIN, "label").text,
    action = action,
    lines = data.split_lines(ui.get(WIN, "extra").text),
  }
end

local function refresh_preview()
  local lines = data.entry_lines(builder_entry())
  ui.update(WIN, "preview", {
    text = #lines == 0 and "Runs: (nothing yet)" or ("Runs: " .. table.concat(lines, "  |  ")),
    dim = #lines == 0,
  })
end

local function refresh_choice()
  local t = type_def()
  local text
  if not E.kind then
    text = "Macro: type every line below."
  elseif E.pick then
    text = ("%s: %s"):format(t.label, E.pick.name)
  else
    text = ("%s: none yet. Search, then pick one from the list."):format(t.label)
  end
  ui.update(WIN, "picked", { text = text, dim = not E.kind or not E.pick })
  ui.update(WIN, "btype", { items = { t.label } })
  ui.update(WIN, "target", {
    label = E.kind == "equip" and "Equipment slot" or "Target",
    items = { E.kind and builder.target_label(E.kind, E.target, E.pick and E.pick.name) or "(not used)" },
  })
  ui.update(WIN, "extra", { label = E.kind and "Lines after it (| between lines, optional)" or "Lines (| between lines)" })
end

local function refresh_results(query)
  local t = type_def()
  ui.update(WIN, "q", { label = t.search })
  ui.update(WIN, "found", { columns = builder.columns(E.kind) })
  if not E.kind then
    E.results = {}
    ui.update(WIN, "found", { rows = {} })
    ui.update(WIN, "fcount", { text = "" })
    return
  end
  local found, more = builder.find(E.kind, query)
  E.results = found
  local rows = {}
  for i, e in ipairs(found) do
    rows[i] = { e.name, e.cells[1] or "", e.cells[2] or "", icon = e.icon }
  end
  ui.update(WIN, "found", { rows = rows, at = 1 })
  ui.update(WIN, "fcount", {
    text = #found == 0 and "Nothing matches." or (more and ("First %d matches."):format(#found)
      or ("%d found."):format(#found)),
  })
end

local function builder_where()
  local text = E.id and ('Editing "%s" of %s.'):format((data.get_entry(S.mj, E.id) or {}).name or "?", S.mj or "?")
    or ("New macro for %s."):format(S.mj or "?")
  if E.slot then
    text = text .. (" Save puts it on bar %d, slot %d."):format(E.slot.bar, E.slot.slot)
  end
  return text
end

local function set_kind(kind)
  if kind == E.kind then return end
  E.kind, E.pick = kind, nil
  E.target = kind == "equip" and "main" or kind == "cmd" and "" or "t"
  refresh_results(ui.get(WIN, "q").text)
  refresh_choice()
  refresh_preview()
end

-- Opens the builder on a library entry (`id`), or on a new macro: blank, or `macro` (a slot's own macro) as typed
-- lines. `slot` ({bar, slot, main, sub}) is where Save puts it.
function open_builder(id, slot, macro)
  if not S.mj then
    say("jobs are not loaded yet.")
    return
  end
  local entry = id and data.get_entry(S.mj, id) or nil
  E.id = entry and tostring(id) or nil
  E.slot = slot
  E.kind, E.pick, E.target, E.auto_name = "ma", nil, "t", nil
  local name, label, extra = "", "", ""
  if macro then
    entry = { name = macro.name, label = macro.label, lines = macro.lines }
  end
  if entry then
    name, label = entry.name or "", entry.label or ""
    extra = data.join_lines(entry.lines)
    if entry.action then
      E.kind = entry.action.kind
      E.pick = { name = entry.action.name }
      E.target = entry.action.target
    else
      E.kind = nil
    end
  end
  ui.update(WIN, "name", { text = name })
  ui.update(WIN, "label", { text = label })
  ui.update(WIN, "extra", { text = extra })
  ui.update(WIN, "q", { text = "" })
  ui.update(WIN, "bwhere", { text = builder_where() })
  refresh_results("")
  refresh_choice()
  refresh_preview()
  ui.update(WIN, "tabs", { at = TAB_BUILD })
end

local function pick(index)
  local e = E.results[index]
  if not e then return end
  local name = data.trim(ui.get(WIN, "name").text)
  -- The name follows the pick until the player types their own.
  if name == "" or name == E.auto_name then
    ui.update(WIN, "name", { text = e.title or e.name })
    E.auto_name = e.title or e.name
  end
  -- A new pick starts on its usual target; picking the same again keeps the one chosen.
  if not E.pick or E.pick.name ~= e.name then
    E.target = e.target
  end
  E.pick = { name = e.name }
  refresh_choice()
  refresh_preview()
end

local function choose_type()
  ui.menu(builder.TYPE_LABELS, function(i)
    if i then set_kind(builder.TYPES[i].kind) end
  end)
end

local function choose_target()
  if not E.kind then
    say("a macro's lines name their own targets.")
    return
  end
  local choices = builder.targets_for(E.kind, E.pick and E.pick.name)
  if choices[1][1] == "" and #choices == 1 then
    say("that command takes no target.")
    return
  end
  local labels = {}
  for i, t in ipairs(choices) do labels[i] = t[2] end
  ui.menu(labels, function(i)
    if not i then return end
    E.target = choices[i][1]
    refresh_choice()
    refresh_preview()
  end)
end

local function save_builder()
  if not S.mj then
    return
  end
  local entry = builder_entry()
  if E.kind and not entry.action then
    say("pick one from the list first.")
    return
  end
  if not entry.action and #entry.lines == 0 then
    say("add at least one line to the macro.")
    return
  end
  if data.trim(entry.name) == "" then
    local c = entry.action and entry.action.kind == "cmd" and builder.command(entry.action.name)
    entry.name = c and c.title or entry.action and entry.action.name or entry.lines[1]:sub(1, 24)
  end
  E.id = data.save_entry(S.mj, E.id, entry)
  local s = E.slot
  if s and s.main == S.mj then
    data.assign(s.main, s.sub, s.bar, s.slot, E.id)
    say(('"%s" is on bar %d, slot %d.'):format(entry.name, s.bar, s.slot))
  end
  E.slot = nil
  M.hooks.changed()
  refresh_library(E.id)
  ui.update(WIN, "tabs", { at = TAB_LIB })
end

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------

local function refresh_keys()
  for b = 1, data.MAX_BARS do
    ui.update(WIN, "mod" .. b, { at = keys.index_of(keys.MOD_LABELS, keys.get_mod(b)) })
  end
  ui.update(WIN, "row", { at = keys.index_of(keys.ROW_LABELS, keys.get_row()) })
  local c = keys.conflicts()
  ui.update(WIN, "clash", {
    text = #c == 0 and "No key clashes." or ("Clash: " .. table.concat(c, "; ")),
    colour = #c == 0 and { 160, 200, 160 } or { 240, 120, 100 },
  })
  -- The chosen bar's slots: each one's key, its own or its bar's.
  local bars = math.min(settings.get("bars"), data.MAX_BARS)
  local slots = math.min(settings.get("slots"), data.MAX_SLOTS)
  K.bar = math.min(K.bar, bars)
  K.slot = math.min(K.slot, slots)
  local names = {}
  for b = 1, bars do names[b] = tostring(b) end
  ui.update(WIN, "kbar", { items = names, at = K.bar })
  local rows = {}
  for i = 1, slots do
    local own = keys.get_slot(K.bar, i)
    rows[i] = { tostring(i), keys.hint_or(K.bar, i), own and "Its own" or "The bar's",
      colour = own and { 232, 210, 156 } or nil }
  end
  ui.update(WIN, "kslots", { rows = rows, at = K.slot })
  ui.update(WIN, "skey", { label = ("Bar %d, slot %d's key"):format(K.bar, K.slot), text = keys.combo(K.bar, K.slot) })
end

local function keys_changed()
  M.hooks.rebind()
  M.hooks.changed()
  refresh_keys()
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function define()
  ui.window(WIN, {
    title = "Hotbars",
    width = 520,
    help = "Drag a macro onto a slot of the bars. Right-click a slot to clear it.",
    elements = {
      { type = "tabs", id = "tabs", items = { "Library", "Builder", "Config" }, at = 1 },

      -- Library
      { type = "input", id = "job", label = "Job", text = "", max = 3, page = TAB_LIB,
        tip = "The main job whose macros to show, e.g. RDM." },
      { type = "text", id = "lctx", text = "", page = TAB_LIB },
      { type = "canvas", id = "tiles", w = CW, h = T, page = TAB_LIB },
      { type = "text", id = "lsel", text = "", dim = true, page = TAB_LIB },
      { type = "buttons", id = "lbtn", items = { "New", "Edit", "Copy", "Delete", "Palette" }, page = TAB_LIB },

      -- Builder
      { type = "text", id = "bwhere", text = "", page = TAB_BUILD },
      { type = "buttons", id = "btype", label = "Type", items = { "Spell" }, page = TAB_BUILD,
        tip = "Choose what the macro does." },
      { type = "input", id = "q", label = "Search", text = "", max = 32, page = TAB_BUILD,
        tip = "Part of a name, e.g. cure." },
      { type = "list", id = "found", rows = {}, height = 7, page = TAB_BUILD, columns = builder.columns("ma"),
        tip = "Enter or click one to build the macro on it." },
      { type = "text", id = "fcount", text = "", dim = true, page = TAB_BUILD },
      { type = "text", id = "picked", text = "", page = TAB_BUILD },
      { type = "buttons", id = "target", label = "Target", items = { "<t> Current target" }, page = TAB_BUILD },
      { type = "input", id = "name", label = "Name", text = "", max = 32, page = TAB_BUILD },
      { type = "input", id = "label", label = "Button text (blank = from the name)", text = "", max = 14,
        page = TAB_BUILD },
      { type = "input", id = "extra", label = "Lines after it (| between lines, optional)", text = "", max = 1024,
        page = TAB_BUILD, tip = 'Example: /p Casting <t> | /wait 2 | /echo done' },
      { type = "text", id = "preview", text = "", page = TAB_BUILD },
      { type = "text", id = "tip", text = "Waits: /wait 2 on its own line, or <wait 2> at the end of one.",
        dim = true, page = TAB_BUILD },
      { type = "buttons", id = "bbtn", items = { "Save", "Cancel" }, page = TAB_BUILD },

      -- Config
      { type = "text", id = "ktext", text = "Hotkey modifier for each bar:", page = TAB_CONFIG },
      { type = "choice", id = "mod1", label = "Bar 1", items = keys.MOD_LABELS, at = 1, page = TAB_CONFIG },
      { type = "choice", id = "mod2", label = "Bar 2", items = keys.MOD_LABELS, at = 1, page = TAB_CONFIG },
      { type = "choice", id = "mod3", label = "Bar 3", items = keys.MOD_LABELS, at = 1, page = TAB_CONFIG },
      { type = "choice", id = "row", label = "Keys", items = keys.ROW_LABELS, at = 1, page = TAB_CONFIG },
      { type = "text", id = "clash", text = "", page = TAB_CONFIG },
      { type = "buttons", id = "kbtn", items = { "Reset to defaults" }, page = TAB_CONFIG },
      { type = "separator", page = TAB_CONFIG },
      { type = "text", id = "kslottext", text = "A slot's own key (any key, with Ctrl, Alt or Shift) takes the place of "
        .. "its bar's:", page = TAB_CONFIG },
      { type = "choice", id = "kbar", label = "Bar", items = { "1" }, at = 1, page = TAB_CONFIG },
      { type = "list", id = "kslots", rows = {}, height = 6, page = TAB_CONFIG,
        columns = { { title = "Slot", width = 44 }, { title = "Key" }, { title = "From", width = 80 } },
        tip = "Enter or click a slot, then press its key." },
      { type = "key", id = "skey", label = "Key", text = "", page = TAB_CONFIG,
        tip = "Enter or click, then press the slot's key. Backspace: no key." },
      { type = "buttons", id = "skeyb", items = { "Bar's Key" }, page = TAB_CONFIG,
        tip = "The slot takes its bar's key again." },
    },
  })

  ui.on(WIN, function(_, e)
    if e.id == "tiles" then
      on_tiles(e)
    elseif e.kind == "set" then
      if e.id:match("^mod%d$") then
        keys.set_mod(tonumber(e.id:sub(4)), keys.MOD_LABELS[e.index])
        keys_changed()
      elseif e.id == "row" then
        keys.set_row(keys.ROW_LABELS[e.index])
        keys_changed()
      elseif e.id == "kbar" then
        K.bar = e.index
        refresh_keys()
      end
    elseif (e.kind == "change" and e.id == "skey") or (e.kind == "press" and e.id == "skeyb") then
      keys.set_slot(K.bar, K.slot, e.id == "skey" and e.text or nil)
      keys_changed()
    elseif e.kind == "edit" then
      if e.id == "q" then
        refresh_results(e.text)
      elseif e.id == "extra" or e.id == "name" then
        refresh_preview()
      end
    elseif e.kind == "change" and e.id == "job" then
      local job = jobs.parse(e.text)
      if job then
        S.mj = job
      else
        say(('"%s" is not a job (use the three-letter name, e.g. RDM).'):format(data.trim(e.text)))
      end
      refresh_library()
    elseif e.kind == "select" then
      if e.id == "found" then
        pick(e.index)
      elseif e.id == "kslots" then
        K.slot = e.index
        refresh_keys()
        ui.update(WIN, "skey", { listen = true })
      end
    elseif e.kind == "press" then
      if e.id == "lbtn" then
        if e.index == 1 then
          open_builder(nil)
        elseif e.index == 2 then
          local id = selected_entry()
          if id then open_builder(id) end
        elseif e.index == 3 then
          copy_selected()
        elseif e.index == 4 then
          delete_selected()
        elseif M.hooks.palette then
          M.hooks.palette()
        end
      elseif e.id == "btype" then
        choose_type()
      elseif e.id == "target" then
        choose_target()
      elseif e.id == "bbtn" then
        if e.index == 1 then
          save_builder()
        else
          ui.update(WIN, "tabs", { at = TAB_LIB })
        end
      elseif e.id == "kbtn" then
        keys.reset()
        keys_changed()
      end
    end
  end)
  defined = true
end

local function ensure()
  if not defined then
    define()
  end
end

local function refresh_all(select_id)
  refresh_library(select_id)
  refresh_keys()
end

-- Opens the manager on the current main job's library, with `select_id` chosen when given.
function M.open(select_id)
  ensure()
  S.mj = jobs.current() or S.mj
  refresh_all(select_id)
  ui.update(WIN, "tabs", { at = TAB_LIB })
  ui.open(WIN)
end

function M.toggle()
  ensure()
  if ui.is_open(WIN) then
    ui.close(WIN)
  else
    M.open()
  end
end

-- Opens the builder on a library entry of the current main job (a palette tile clicked).
function M.edit_entry(id)
  ensure()
  S.mj = jobs.current() or S.mj
  refresh_all(id)
  open_builder(id)
  ui.open(WIN)
end

-- Redraws the window's lists after the data changed from outside (//hb reload, a palette drop).
function M.refresh()
  if defined then
    refresh_all()
  end
end

return M
