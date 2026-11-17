-- LuAshitacast profile per job if present; otherwise the set builder wears sets around outgoing actions.

local core = require("src.core")
local lac = require("src.lac")
local builder = require("src.build.run")
local builder_window = require("src.build.window")
local trusts = require("src.trusts")
local trust_window = require("src.trust_window")
builder_window.install()
trusts.window = trust_window.toggle
builder.extra = trusts.step
trusts.install()
timer.after(0, function() builder.worker() end)

local function file_loaded()
  return lac.loaded()
end

local job_now

local function load_for_job()
  lac.unload()
  if not settings.get("on") then return end
  local f = lac.find()
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

local function on_out(p)
  if p.injected then return end
  local act = core.parse_action(p)
  if not act then return end
  core.note_action(act)
  if lac.loaded() then return lac.action(act) end
  return builder.action(act)
end
packets.on_out(0x01A, on_out)
packets.on_out(0x037, on_out)

events.on("action", function(a)
  lac.on_action(a)
  if not file_loaded() then builder.on_action(a) end
end)
events.on("job_change", function(main)
  if main ~= job_now and main ~= 0 then
    started, job_now = true, main
    load_for_job()
  end
end)
events.on("settings_changed", start)
events.on("frame", function()
  core.decode_augments()
  if not started and main_job() and main_job() ~= 0 then start() end
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
events.on("settings_changed", function(key)
  if key == "grid_scale" then builder_window.redraw() end
end)

mods.provide("gear_names", function()
  if lac.loaded() then return { file = lac.file, names = lac.gear_names() } end
  return nil
end)

commands.register("lac", function(...) lac.command({ ... }) end)
local vg = require("src.vg")
local vg_ctx = {
  window = function() builder_window.toggle() end,
  reload = function() start() end,
  file = function() return lac.file end,
}
commands.register("vg", function(...) vg.command({ ... }, vg_ctx) end)
commands.register("gs", function(...) vg.gs({ ... }, vg_ctx) end)
