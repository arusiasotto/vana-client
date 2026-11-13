-- Hotbars (from PR #88 by Arusia): bars of multi-line macros that load by main job, then sub job; each slot shows its
-- action's icon and recast, in a frame whose + / - show more or fewer bars. A slot's right-click menu puts a spell,
-- an ability, an existing macro or one of the job's library macros in it. The manager's Builder makes library macros
-- (spells, abilities, weapon skills, pet commands, items, equipment, system commands or typed lines); the palette
-- shows them as tiles to drag onto the bars. See src/data.lua for macros.json. //hb opens the manager.
--
-- Two ways to play, one at a time (the Mode setting; //hb mode switches for the session): the keyboard's hotbars
-- above, or the gamepad's crossbars (src/pad.lua): hold LT, RT or both and the d-pad, face buttons, L1 / R1 and L3 / R3
-- fire that side's slots, which take the same library macros, dragged from the palette.

local data = require("src.data")
local bar = require("src.bar")
local manager = require("src.manager")
local stock = require("src.stock")
local menu = require("src.menu")
local palette = require("src.palette")
local jobs = require("src.jobs")
local chooser = require("src.chooser")
local mode = require("src.mode")
local pad = require("src.pad")

local ok, err = data.init({
  read = fs.read,
  write = fs.write,
  decode = json.decode,
  encode = function(value) return json.encode(value, { pretty = true }) end,
  log = log.warn,
})
if not ok then
  chat.add("Hotbars: macros.json could not be read (" .. tostring(err) .. "); a copy was kept as macros.json.bad.")
end

-- After a macro or the library changed: the bars, the manager's lists and the palette's tiles.
local function changed()
  bar.rebuild()
  pad.invalidate()
  manager.refresh()
  palette.set_job(jobs.current())
end

bar.hooks.open_manager = manager.open
bar.hooks.slot_menu = menu.open
bar.hooks.changed = function()
  manager.refresh()
  palette.set_job(jobs.current())
end
menu.hooks.open_manager = manager.open
menu.hooks.changed = changed
manager.hooks.changed = function()
  bar.rebuild()
  pad.invalidate()
  palette.set_job(jobs.current())
end
-- A crossbar slot changed: the lists and the palette follow; the bars, which show none of it, stay.
pad.hooks.changed = bar.hooks.changed
-- The library is being edited: the crossbars stay shown to drop macros on.
pad.hooks.editing = function() return palette.is_open() or manager.is_open() end
pad.hooks.open_manager = manager.open
pad.hooks.palette = function()
  palette.set_job(jobs.current())
  palette.toggle()
end
-- A group's member picked from its list: the slot shows that one now.
local picked = chooser.hooks.picked
chooser.hooks.picked = function()
  if picked then picked() end
  pad.invalidate()
end
manager.hooks.rebind = bar.rebind
manager.hooks.palette = palette.toggle
palette.hooks.edit = manager.edit_entry
palette.hooks.drag_ended = function()
  bar.tile_drag_ended()
  pad.tile_drag_ended()
end

-- The game's macro palette hides (its drawing only) while the bars show: not in gamepad mode, which has none.
local function apply_stock_palette()
  ui.native.hide("palette", settings.get("on") and settings.get("hide_stock") and not mode.is_pad())
end

local function refresh()
  apply_stock_palette()
  bar.rebind()
  changed()
end

refresh()
-- The jobs can arrive after the mod loads, and a job change swaps the macros.
events.on("job_change", changed)
events.on("settings_changed", function(key)
  -- The Mode setting changed: it decides again over what //hb mode set.
  if key == "mode" then mode.use_setting() end
  refresh()
end)
timer.every(1, bar.tick)
timer.every(0.25, bar.recasts)
timer.every(0.25, pad.recasts)
timer.every(1, pad.tick)

-- Switches between the keyboard's hotbars and the gamepad's crossbars (`to` nil: the other one).
local function set_mode(to)
  if to then mode.set(to) else mode.toggle() end
  refresh()
  if mode.is_pad() then
    chat.add("Hotbars: gamepad crossbars"
      .. (input.pad().connected and "." or " (no controller is connected: they answer one once it is)."))
  else
    chat.add("Hotbars: keyboard hotbars.")
  end
end

-- The forms of //hb as mod.toml declares them: what the chat line's hint and //mods show.
local function usage()
  chat.add("Hotbars:")
  for _, line in ipairs(commands.usage("hb")) do chat.add("  " .. line) end
end

commands.register("hb", function(cmd, a, b)
  cmd = (cmd or ""):lower()
  if cmd == "" then
    manager.toggle()
  elseif cmd == "show" then
    bar.set_hidden(false)
  elseif cmd == "hide" then
    bar.set_hidden(true)
  elseif cmd == "more" then
    bar.grow(1)
  elseif cmd == "fewer" then
    bar.grow(-1)
  elseif cmd == "palette" then
    palette.set_job(jobs.current())
    palette.toggle()
  elseif cmd == "mode" then
    if (a or "") == "" then
      set_mode(nil)
    elseif mode.parse(a) then
      set_mode(mode.parse(a))
    else
      usage()
    end
  elseif cmd == "run" then
    local bn, sn = tonumber(a), tonumber(b)
    if bn and sn then bar.fire(bn, sn) else usage() end
  elseif cmd == "wipestock" then
    stock.start_wipe()
  elseif cmd == "restorestock" then
    stock.restore()
  elseif cmd == "reload" then
    local loaded, why = data.load()
    if not loaded then chat.add("Hotbars: macros.json could not be read (" .. tostring(why) .. ").") end
    changed()
  else
    usage()
  end
end)
