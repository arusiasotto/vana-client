-- Your own sets built by vanagear's engine over the server's real item tables: every set the engine has a mode for,
-- no weapons or ammo from scoring, a locked slot left out, /vg why ranked by the engine's weights.

local server = require("src.build.server")
local items = require("data.items")

-- A WHM's bag: every item the server knows that a WHM can wear at 75 (the game's record is made from the server's).
local WHM = 3
local RECORDS, BAG = {}, {}
for id in pairs(items) do
  local s = server.item(id)
  if s and s.level <= 75 and (s.jobs & (1 << WHM)) ~= 0 and s.slots ~= 0 then
    RECORDS[id] = { name = "#" .. id, slots = s.slots, jobs = s.jobs, races = 0x1fe, level = s.level, description = "" }
    BAG[#BAG + 1] = { slot = #BAG + 1, id = id }
  end
end
table.sort(BAG, function(a, b) return a.id < b.id end)
for i, b in ipairs(BAG) do b.slot = i end
assert(#BAG > 100, "bag: " .. #BAG)

local P = { name = "Tester", id = 100, index = 1, main_job = WHM, main_level = 75, sub_job = 0, status = 0, hpp = 100,
  mpp = 100, mp_max = 500, pos = { x = 0, y = 0, z = 0 } }
game = {
  player = function() return P end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return {} end,
  items = function(bag)
    local t = {}
    if bag == 0 then
      for _, b in ipairs(BAG) do t[#t + 1] = { bag = 0, slot = b.slot, id = b.id, count = 1, locked = 0 } end
    end
    return t
  end,
  time = function() return { weekday = 1 } end, weather = function() return 0 end, buffs = function() return {} end,
}
res = setmetatable({
  item = function(id) return RECORDS[id] end,
  spell = function() end,
  job = function(id) return ({ "WAR", "MNK", "WHM" })[id] end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function(k) if k == "cap" then return "Auto" end return true end }

local run = require("src.build.run")
run.RANGES = { { 1, 2 } }
local function settle()
  run.refresh()
  for _ = 1, 400 do run.frame() end
end
settle()

-- Sets with a mode are the engine's.
local cure = assert(run.state.built.Cure, "Cure is built")
assert(cure.engine, "Cure is the engine's")
assert(run.state.built.Idle and run.state.built.Idle.engine, "Idle is the engine's")
local worn = 0
for slot, o in pairs(cure.slots) do
  if o.pick then
    worn = worn + 1
    assert(slot >= 4, "no weapons or ammo from scoring: slot " .. slot)
    assert(o.pick.rec.name == o.pick.rec.name and RECORDS[o.pick.id], "a piece we hold")
  end
end
assert(worn >= 8, "a Cure set of " .. worn .. " pieces")

-- The Cure set leans on cure potency: its pieces give more than the Idle set's do.
local function stat_total(r, key)
  local t = 0
  for _, o in pairs(r.slots) do if o.pick then t = t + (o.pick.s.stats[key] or 0) end end
  return t
end
assert(stat_total(cure, "cure") > stat_total(run.state.built.Idle, "cure"), "Cure carries the cure potency")

-- A locked slot is left out of the sets built after the lock.
local head = cure.slots[4].pick
assert(head, "a Cure head")
run.lock(4, true)
settle()
assert(run.state.built.Cure.slots[4].pick == nil, "the locked head is not in the set")
run.lock(4, false)
settle()
assert(run.state.built.Cure.slots[4].pick.id == head.id, "unlocked, the head is back")

-- /vg why: the winner leads the list by the engine's weights.
local why = run.why("Cure", 4)
assert(why and why.won and #why.list > 3, "why")
assert(why.list[1].score >= why.list[2].score, "ranked")
assert(why.won == run.state.built.Cure.slots[4].pick.rec.name)
local top = why.list[1]
assert(top.score >= why.list[#why.list].score)

-- plan.For lists the job's sets; Ws_Default is there for a fighter, and a weaponskill by name when a weapon is worn.
local engine = require("src.vg.player")
local list = engine.names({ job = "WHM", job_id = 3, level = 75, sub_id = 0, owned = {}, locked = {}, player = {} })
local have = {}
for _, n in ipairs(list) do have[n] = true end
assert(have.Idle and have.Cure and have.Precast, "WHM plan sets")
assert(not have.Tp_Default, "WHM support job has no Tp_Default")
