-- Hotbars (from PR #88 by Arusia): bars of multi-line macros that load by main job, then sub job; each slot shows its
-- action's icon and recast, in a frame whose + / - show more or fewer bars. A slot's right-click menu puts a spell,
-- an ability, an existing macro or one of the job's library macros in it. The manager's Builder makes library macros
-- (spells, abilities, weapon skills, pet commands, items, equipment, system commands or typed lines); the palette
-- shows them as tiles to drag onto the bars. See src/data.lua for macros.json. //hb opens the manager.

local data = require("src.data")
local bar = require("src.bar")
local manager = require("src.manager")
local stock = require("src.stock")
local menu = require("src.menu")
local palette = require("src.palette")
local jobs = require("src.jobs")

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
  manager.refresh()
  palette.set_job(jobs.current())
end

bar.hooks.open_manager = manager.open
bar.hooks.slot_menu = menu.open
bar.hooks.changed = function()
  manager.refresh()
  palette.set_job(jobs.current())
end
menu.hooks.edit_slot = manager.edit_slot
menu.hooks.open_manager = manager.open
menu.hooks.rebind = bar.rebind
menu.hooks.changed = changed
manager.hooks.changed = function()
  bar.rebuild()
  palette.set_job(jobs.current())
end
manager.hooks.rebind = bar.rebind
manager.hooks.palette = palette.toggle
palette.hooks.edit = manager.edit_entry
palette.hooks.drag_ended = bar.tile_drag_ended

-- The game's macro palette hides (its drawing only) while the bars show.
local function apply_stock_palette()
  ui.native.hide("palette", settings.get("on") and settings.get("hide_stock"))
end

local function refresh()
  apply_stock_palette()
  bar.rebind()
  changed()
end

refresh()
-- The jobs can arrive after the mod loads, and a job change swaps the macros.
events.on("job_change", changed)
events.on("settings_changed", refresh)
timer.every(1, bar.tick)
timer.every(0.25, bar.recasts)

local USAGE = "//hb [show | hide | more | fewer | palette | run <bar> <slot> | reload | wipestock | restorestock]"
  .. "  (no argument opens the manager)"

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
  elseif cmd == "run" then
    local bn, sn = tonumber(a), tonumber(b)
    if bn and sn then bar.fire(bn, sn) else chat.add("Hotbars: " .. USAGE) end
  elseif cmd == "wipestock" then
    stock.start_wipe()
  elseif cmd == "restorestock" then
    stock.restore()
  elseif cmd == "reload" then
    local loaded, why = data.load()
    if not loaded then chat.add("Hotbars: macros.json could not be read (" .. tostring(why) .. ").") end
    changed()
  else
    chat.add("Hotbars: " .. USAGE)
  end
end)
