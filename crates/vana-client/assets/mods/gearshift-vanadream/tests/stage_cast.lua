-- /vg stage: spell routes carry Interim when staging is on; toggling off clears it.

local run = require("src.build.run")

game = {
  player = function() return { main_job = 3, main_level = 75, sub_job = 0 } end,
  entity = function() return { race = 1 } end,
  items = function() return {} end,
}
res = setmetatable({
  spell = function(id)
    if id == 1 then return { name = "Cure", skill = 33, element = 6, cast_time = 3.5 } end
  end,
  job = function(id) return ({ "WAR", "MNK", "WHM" })[id] end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function(k) if k == "engine" then return true end return true end }

run.state.job, run.state.level, run.state.ready = "WHM", 75, true
run.state.built = {}
run.H.engine = function() return true end
run.H.job = function(id) return res.job(id) end
run.H.player = game.player
run.H.me = function() return { race = 1 } end
run.H.spell = res.spell

-- Stub plan names: Precast, Interim, Cure exist for this job.
local engine = require("src.vg.player")
local saved_names = engine.names
engine.names = function()
  return { "Precast", "Interim", "Cure", "Idle" }
end
function run.job_sets(_) return engine.names() end

local act = { category = 3, param = 1 }
local modes = run.modes()
modes.stage = true
local r = run.route(act)
assert(r[1] == "Precast" and r[2] == "Cure" and r.interim == "Interim" and r.cast == 3.5,
  ("route: %s %s interim=%s"):format(tostring(r[1]), tostring(r[2]), tostring(r.interim)))

modes.stage = false
r = run.route(act)
assert(r.interim == nil, "stage off: no interim")

engine.names = saved_names