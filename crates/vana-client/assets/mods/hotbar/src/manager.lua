-- The macro manager window.
--
--   Library  a main job's macros: new, edit, copy, delete, and the palette, from which they are dragged onto the bars
--            (or a slot's menu, From the library).
--   Builder  one macro: an action of a type (spell, job ability, weapon skill, pet command, item, equipment, system
--            command) and its target build the first line; lines typed under it run after it. A "Macro" is typed only.
--            Opened from a slot's menu (Edit the macro), it saves into the library and puts the macro on that slot.
--   Config   the hotkey modifier of each bar, the key row, and a slot's own key (changes apply at once).

local data = require("src.data")
local jobs = require("src.jobs")
local keys = require("src.keys")
local actions = require("src.actions")
local builder = require("src.builder")

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

local function refresh_library(select_id)
  ui.update(WIN, "job", { text = S.mj or "" })
  if not S.mj then
    lib_ids = {}
    ui.update(WIN, "lctx", { text = "Jobs are not loaded yet." })
    ui.update(WIN, "lib", { rows = {} })
    return
  end
  local at = ui.get(WIN, "lib").at or 1
  local rows = {}
  lib_ids = {}
  for i, it in ipairs(data.library(S.mj)) do
    lib_ids[i] = it.id
    if select_id and it.id == tostring(select_id) then at = i end
    rows[i] = {
      it.entry.name or "",
      does_text(it.entry),
      tostring(data.uses(S.mj, it.id)),
      icon = row_icon({ lines = data.entry_lines(it.entry) }),
    }
  end
  ui.update(WIN, "lctx", {
    text = #rows == 0 and ("%s has no macros yet: press New."):format(S.mj)
      or ("%s macros. Open the Palette and drag one onto a slot of the bars."):format(S.mj),
  })
  ui.update(WIN, "lib", { rows = rows, at = math.max(1, math.min(at, #rows)) })
end

local function selected_entry()
  local at = ui.get(WIN, "lib").at
  return at and lib_ids[at] or nil
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
local function open_builder(id, slot, macro)
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
    help = "Drag a macro from the palette onto a slot, or right-click a slot: From the library.",
    elements = {
      { type = "tabs", id = "tabs", items = { "Library", "Builder", "Config" }, at = 1 },

      -- Library
      { type = "input", id = "job", label = "Job", text = "", max = 3, page = TAB_LIB,
        tip = "The main job whose macros to show, e.g. RDM." },
      { type = "text", id = "lctx", text = "", page = TAB_LIB },
      { type = "list", id = "lib", rows = {}, height = 12, page = TAB_LIB,
        columns = { { title = "Macro", width = 150 }, { title = "Runs" }, { title = "Slots", width = 44, align = "right" } },
        tip = "Enter or click a macro to edit it." },
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
    if e.kind == "set" then
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
      if e.id == "lib" then
        open_builder(lib_ids[e.index])
      elseif e.id == "found" then
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

-- Opens the builder on a slot of the current jobs (its menu's Edit the macro): on its library entry, or on its own
-- macro (or a blank one) that Save puts into the library and on the slot. `from` is "sub" when the slot shows the
-- sub job's set (so that is the set it goes into).
function M.edit_slot(bar, slot, from)
  ensure()
  local main, sub = jobs.current()
  if not main then
    say("jobs are not loaded yet.")
    return
  end
  S.mj = main
  refresh_all()
  local macro = data.resolve(main, sub, bar, slot)
  local at = { bar = bar, slot = slot, main = main, sub = from == "sub" and sub or nil }
  if macro and macro.ref then
    open_builder(macro.ref, at)
  else
    open_builder(nil, at, macro)
  end
  ui.open(WIN)
end

-- Redraws the window's lists after the data changed from outside (//hb reload, a palette drop).
function M.refresh()
  if defined then
    refresh_all()
  end
end

return M
