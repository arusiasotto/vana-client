-- A slot's right-click menu (a pop-up at the pointer) and the pickers it opens: one of our spells, one of our
-- abilities (job abilities, weapon skills, pet commands) or an existing macro (the game's macro palette or another
-- hotbar slot) put into the slot as a ready macro. The manager's editor stays for writing one by hand.

local data = require("src.data")
local jobs = require("src.jobs")
local keys = require("src.keys")
local actions = require("src.actions")

local M = {}

-- Set by init.lua: edit_slot(bar, slot, from), open_manager(), changed(), rebind()
M.hooks = {}

local MENU, PICK, KEY = "slotmenu", "slotpick", "slotkey"
local GOLD = { 232, 210, 156 }
local DIM = { 160, 162, 172 }

local at = nil        -- {bar, slot, from} the menu and the pickers work on
local all = {}        -- the picker's whole list: {label, info, icon, macro}
local rows = {}       -- what it shows after the filter

-- The set a slot's new macro goes into: the sub job's when the slot shows the sub set's. The picker's button text,
-- when given, labels the slot in place of the name (a library macro keeps its own: it is put on the slot by reference).
local function store(macro)
  local label = data.trim(ui.is_open(PICK) and ui.get(PICK, "btn").text or "")
  if label ~= "" and macro.ref == nil then
    macro = { name = macro.name, label = label, lines = macro.lines }
  end
  local main, sub = jobs.current()
  if not (main and at) then return end
  data.set_macro(main, at.from == "sub" and sub or nil, at.bar, at.slot, macro)
  if M.hooks.changed then M.hooks.changed() end
  chat.add(("Hotbars: %s is on bar %d, slot %d (%s)."):format(macro.name, at.bar, at.slot, keys.hint_or(at.bar, at.slot)))
end

local function quote(name)
  return name:find(" ") and ('"' .. name .. '"') or name
end

-- <me> for an action that can only aim at ourselves (target bits: 1 = self), else <t>.
local function aim(targets)
  return (tonumber(targets) or 0) == 1 and "<me>" or "<t>"
end

-- ---------------------------------------------------------------------------
-- The pickers
-- ---------------------------------------------------------------------------

-- Dim when it cannot be used now (its job level or MP, TP for a weapon skill, a pet, its recast).
local function ready(a, me, rc)
  return actions.usable(a, me) and actions.recast(a, rc) <= 0
end

local function spells()
  local out = {}
  local me, rc = game.player(), game.recasts()
  for _, id in ipairs(game.spells()) do
    local s = res.spell(id)
    if s and s.name and s.name ~= "" then
      local info = s.kind == 8 and "Trust" or (s.mp and s.mp > 0 and ("%d MP"):format(s.mp) or "")
      out[#out + 1] = { label = s.name, info = info, icon = { kind = "spell", id = id },
        dim = not ready({ kind = "spell", id = id }, me, rc),
        macro = { name = s.name, lines = { ("/ma %s %s"):format(quote(s.name), aim(s.targets)) } } }
    end
  end
  return out
end

local function abilities()
  local out = {}
  local me, rc = game.player(), game.recasts()
  for _, id in ipairs(game.abilities()) do
    local a = res.ability(id)
    if a and a.name and a.name ~= "" then
      local cmd, info = "/ja", "Ability"
      if id < 0x200 then
        cmd, info = "/ws", "Weapon skill"
      elseif id >= 0x400 then
        cmd, info = "/pet", "Pet command"
      end
      out[#out + 1] = { label = a.name, info = info, icon = { kind = "ability", id = id },
        dim = not ready({ kind = "ability", id = id, recast_id = a.recast_id, ws = id < 0x200 }, me, rc),
        macro = { name = a.name, lines = { ("%s %s %s"):format(cmd, quote(a.name), aim(a.targets)) } } }
    end
  end
  return out
end

local function lines_of(m)
  local out = {}
  for _, l in ipairs(m.lines or {}) do
    if data.trim(l) ~= "" then out[#out + 1] = l end
  end
  return out
end

local function macros()
  local out = {}
  local p = game.macros()
  if p then
    for _, row in ipairs({ { "ctrl", "Ctrl" }, { "alt", "Alt" } }) do
      for i, m in ipairs(p[row[1]] or {}) do
        local ls = lines_of(m)
        if #ls > 0 then
          local name = data.trim(m.title or "") ~= "" and data.trim(m.title) or ls[1]:sub(1, 24)
          local act = actions.of({ lines = ls })
          out[#out + 1] = { label = name, info = ("%s+%d, %s"):format(row[2], i % 10, p.book_title or "palette"),
            icon = act and { kind = act.kind, id = act.id } or nil, macro = { name = name, lines = ls } }
        end
      end
    end
  end
  local main, sub = jobs.current()
  if main then
    local eff = data.effective(main, sub)
    for b, slots in pairs(eff) do
      for s, cell in pairs(slots) do
        if cell.macro and not (at and b == at.bar and s == at.slot) then
          local m = cell.macro
          local act = actions.of(m)
          out[#out + 1] = { label = data.trim(m.name) ~= "" and m.name or (m.lines[1] or "?"),
            info = ("Bar %d, slot %d"):format(b, s), icon = act and { kind = act.kind, id = act.id } or nil,
            macro = { name = m.name, label = m.label, lines = m.lines, ref = m.ref } }
        end
      end
    end
  end
  return out
end

-- The main job's library: each entry goes onto the slot by reference.
local function library()
  local out = {}
  local main = jobs.current()
  for _, it in ipairs(main and data.library(main) or {}) do
    local lines = data.entry_lines(it.entry)
    local act = actions.of({ lines = lines })
    out[#out + 1] = { label = data.trim(it.entry.name) ~= "" and it.entry.name or (lines[1] or "?"),
      info = lines[1] or "", icon = act and { kind = act.kind, id = act.id } or nil,
      macro = { name = it.entry.name, lines = lines, ref = it.id } }
  end
  return out
end

local function show(filter)
  local f = data.trim(filter or ""):lower()
  rows = {}
  local list = {}
  for _, e in ipairs(all) do
    if f == "" or e.label:lower():find(f, 1, true) or (e.info or ""):lower():find(f, 1, true) then
      rows[#rows + 1] = e
      list[#list + 1] = { e.label, e.info or "", icon = e.icon, colour = e.dim and DIM or nil }
    end
  end
  ui.update(PICK, "list", { rows = list, at = 1 })
  ui.update(PICK, "count", { text = #rows == 0 and "Nothing matches." or ("%d to choose from"):format(#rows) })
end

local TITLES = { spell = "Cast a Spell", ability = "Use an Ability", macro = "Assign a Macro",
  library = "From the Library" }

local function pick(kind)
  all = kind == "spell" and spells() or kind == "ability" and abilities() or kind == "library" and library()
    or macros()
  table.sort(all, function(a, b)
    if kind == "macro" and a.info ~= b.info then return a.info < b.info end
    return a.label < b.label
  end)
  ui.window(PICK, {
    title = TITLES[kind],
    width = 400,
    modal = true,
    help = "Type to filter, then pick one: it goes into the slot as a macro you can still edit in the manager.",
    elements = {
      { type = "text", id = "where", text = ("Bar %d, slot %d (%s)"):format(at.bar, at.slot, keys.hint_or(at.bar, at.slot)),
        colour = GOLD },
      { type = "input", id = "filter", label = "Filter (type to narrow the list)", text = "", max = 32, filter = true,
        tip = "Typing goes here: part of a name narrows the list." },
      { type = "list", id = "list", rows = {}, height = 12,
        columns = { { title = (kind == "macro" or kind == "library") and "Macro" or "Name" },
          { title = kind == "macro" and "From" or kind == "library" and "Runs first" or "",
            width = (kind == "macro" or kind == "library") and 150 or 110, align = "right" } } },
      { type = "text", id = "count", text = "", dim = true },
      kind ~= "library" and { type = "input", id = "btn", label = "Button text (blank: the name)", text = "", max = 14,
        tip = "What the slot shows; Enter to type it." } or { type = "text", id = "btn", dim = true,
        text = "A library macro keeps its own name and button text (edit them in the manager)." },
      { type = "buttons", id = "go", items = { "Assign", "Cancel" } },
    },
  })
  ui.on(PICK, function(_, e)
    if e.kind == "edit" and e.id == "filter" then
      show(e.text)
    elseif e.kind == "select" and e.id == "list" then
      local r = rows[e.index]
      if r then
        store(r.macro)
        ui.close(PICK)
      end
    elseif e.kind == "press" and e.id == "go" then
      if e.index == 1 then
        local r = rows[ui.get(PICK, "list").at or 1]
        if r then store(r.macro) end
      end
      ui.close(PICK)
    end
  end)
  show("")
  ui.open(PICK)
end

-- ---------------------------------------------------------------------------
-- A slot's key
-- ---------------------------------------------------------------------------

local function key_note(bar, slot)
  local own = keys.get_slot(bar, slot)
  local note = own and "Its own key." or ("The bar's key (%s)."):format(keys.hint_or(bar, slot))
  local combo = keys.combo(bar, slot)
  for _, c in ipairs(keys.conflicts()) do
    if combo ~= "" and c:sub(1, #combo + 1) == combo .. ":" then
      return note .. " Clash: " .. c:sub(#combo + 3) .. ".", { 240, 120, 100 }
    end
  end
  return note, DIM
end

local function key_changed(bar, slot)
  if M.hooks.rebind then M.hooks.rebind() end
  if M.hooks.changed then M.hooks.changed() end
  local text, colour = key_note(bar, slot)
  ui.update(KEY, "note", { text = text, colour = colour })
  ui.update(KEY, "key", { text = keys.combo(bar, slot) })
end

local function set_key(bar, slot)
  ui.window(KEY, {
    title = "Slot Key",
    width = 340,
    modal = true,
    help = "Press the key, with Ctrl, Alt or Shift if you like. Backspace: no key. Escape: stop.",
    elements = {
      { type = "text", id = "where", text = ("Bar %d, slot %d"):format(bar, slot), colour = GOLD },
      { type = "key", id = "key", label = "Key", text = keys.combo(bar, slot),
        tip = "Enter or click, then press the key. Backspace: no key." },
      { type = "text", id = "note", text = "", dim = true },
      { type = "buttons", id = "go", items = { "Bar's Key", "Done" } },
    },
  })
  ui.on(KEY, function(_, e)
    if e.kind == "change" and e.id == "key" then
      keys.set_slot(bar, slot, e.text)
      key_changed(bar, slot)
    elseif e.kind == "press" and e.id == "go" then
      if e.index == 1 then
        keys.set_slot(bar, slot, nil)
        key_changed(bar, slot)
      else
        ui.close(KEY)
      end
    end
  end)
  local text, colour = key_note(bar, slot)
  ui.update(KEY, "note", { text = text, colour = colour })
  ui.open(KEY)
  ui.update(KEY, "key", { listen = true })
end

-- ---------------------------------------------------------------------------
-- The menu
-- ---------------------------------------------------------------------------

local ITEMS = {
  { "Cast a spell...", "spell" },
  { "Use an ability...", "ability" },
  { "Assign a macro...", "macro" },
  { "From the library...", "library" },
  { "Edit the macro", "edit" },
  { "Clear the slot", "clear" },
  { "Set the key...", "key" },
  { "Open the manager", "manager" },
}

function M.open(bar, slot, from)
  at = { bar = bar, slot = slot, from = from }
  local main, sub = jobs.current()
  local macro = main and data.resolve(main, sub, bar, slot)
  local act = macro and actions.of(macro)
  local list = {}
  local icons = { spell = { kind = "spell", id = 1 }, ability = { kind = "ability", id = 0x200 + 35 } }
  for _, it in ipairs(ITEMS) do
    if it[2] ~= "clear" or macro then
      list[#list + 1] = { it[1], icon = icons[it[2]] }
    end
  end
  ui.window(MENU, {
    title = ("Bar %d, Slot %d"):format(bar, slot),
    width = 250,
    popup = true,
    elements = {
      { type = "list", id = "head", height = 1, rows = { {
        macro and (data.trim(macro.name) ~= "" and macro.name or (macro.lines[1] or "")) or "Empty slot",
        keys.hint(bar, slot), icon = act and { kind = act.kind, id = act.id } or nil,
        colour = macro and GOLD or DIM } }, columns = { {}, { width = 60, align = "right" } } },
      { type = "separator" },
      { type = "list", id = "acts", rows = list, height = #list },
    },
  })
  ui.on(MENU, function(_, e)
    if e.kind ~= "select" or e.id ~= "acts" then return end
    local want = list[e.index] and list[e.index][1]
    local what
    for _, it in ipairs(ITEMS) do
      if it[1] == want then what = it[2] end
    end
    ui.close(MENU)
    if what == "spell" or what == "ability" or what == "macro" or what == "library" then
      pick(what)
    elseif what == "edit" then
      M.hooks.edit_slot(bar, slot, from)
    elseif what == "clear" and main then
      data.clear(main, from == "sub" and sub or nil, bar, slot)
      if M.hooks.changed then M.hooks.changed() end
    elseif what == "key" then
      set_key(bar, slot)
    elseif what == "manager" then
      M.hooks.open_manager()
    end
  end)
  ui.open(MENU)
end

return M
