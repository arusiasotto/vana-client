-- Gear swapping from players' files: a GearSwap job file (gearswap/ in this mod's data folder, named as GearSwap
-- names them) or a LuAshitacast profile (ashitacast/<Name>_<Id>/<JOB>.lua or ashitacast/<Name>_<JOB>.lua), loaded for
-- the main job and run around the action packets we send: the gear before an action, the action, the gear after it,
-- in one batch.

local core = require("src.core")
local gs = require("src.gs")
local lac = require("src.lac")
local builder = require("src.build.run")
local builder_window = require("src.build.window")
local trusts = require("src.trusts")
local trust_window = require("src.trust_window")
builder_window.install()
trust_window.install()
trusts.window = trust_window.toggle
-- Trust gear (the Vanadreams server's !trustgear): built in the builder's worker, sent from the timer.
builder.extra = trusts.step
trusts.install()
-- The set builder's background work, one coroutine for the session.
timer.after(0, function() builder.worker() end)

-- A file the player wrote runs instead of the set builder.
local function file_loaded()
  return gs.loaded() or lac.loaded()
end

local job_now

local function load_for_job()
  gs.unload()
  lac.unload()
  if not settings.get("on") then return end
  local f = gs.find()
  if f then gs.load(f) return end
  f = lac.find()
  if f then lac.load(f) end
end

local function main_job()
  local p = game.player()
  return p and p.main_job
end

local started = false
local function start()
  started = true
  job_now = main_job()
  load_for_job()
end

-- The action packets we send: held, and sent again by the front end with the gear around them.
local function on_out(p)
  if p.injected then return end
  local act = core.parse_action(p)
  if not act then return end
  core.note_action(act)
  if gs.loaded() then return gs.action(act) end
  if lac.loaded() then return lac.action(act) end
  return builder.action(act)
end
packets.on_out(0x01A, on_out)
packets.on_out(0x037, on_out)

filters.typed(function(line) gs.typed(line) end)

events.on("action", function(a)
  gs.on_action(a)
  lac.on_action(a)
  if not file_loaded() then builder.on_action(a) end
end)
events.on("battle_message", function(actor, target, message) gs.battle_message(actor, target, message) end)
events.on("status_change", function(new, old)
  gs.status_change(new, old)
  gs.user_event("status change", new, old)
end)
events.on("buff_gain", function(id)
  gs.buff_change(id, true)
  gs.user_event("gain buff", id)
end)
events.on("buff_lose", function(id)
  gs.buff_change(id, false)
  gs.user_event("lose buff", id)
end)
events.on("job_change", function(main, _, sub)
  local sub_changed = gs.sub ~= nil and gs.sub ~= sub
  if main ~= job_now and main ~= 0 then
    started, job_now = true, main
    load_for_job()
  end
  if gs.loaded() and sub_changed then gs.sub_job_change(sub, gs.sub) end
  gs.sub = sub
end)
events.on("zone_change", function(zone, previous) gs.user_event("zone change", zone, previous) end)
events.on("target_change", function(id) gs.user_event("target change", id) end)
events.on("settings_changed", start)
-- The first frame our main job is known loads its file (the mod can start before the server has said).
local texts = require("src.texts")
events.on("frame", function()
  core.decode_augments()
  texts.frame()
  if not started and main_job() and main_job() ~= 0 then
    gs.sub = game.player().sub_job
    start()
  end
end)
timer.every(0.4, function()
  core.retry()
  lac.tick()
  trusts.tick()
  if not file_loaded() then builder.tick() end
end)
timer.every(3.0, function() builder.refresh() end)
timer.every(0.5, function()
  builder_window.redraw()
  trust_window.redraw()
end)
events.on("item_change", function() builder.refresh() end)

-- For other mods (Bag Manager): the item names the loaded file's sets hold, and which file.
mods.provide("gear_names", function()
  if gs.loaded() then return { file = gs.file, names = gs.gear_names() } end
  if lac.loaded() then return { file = lac.file, names = lac.gear_names() } end
  return nil
end)

commands.register("gs", function(...) gs.command({ ... }) end)
commands.register("lac", function(...) lac.command({ ... }) end)
-- vanagear's commands (src/vg.lua): the window, /vg build, dt, tp, nuke, burst and /vg trusts.
local vg = require("src.vg")
commands.register("vg", function(...)
  vg.command({ ... }, {
    window = function() builder_window.toggle() end,
    reload = function() start() end,
    file = function() return gs.file or lac.file end,
  })
end)
