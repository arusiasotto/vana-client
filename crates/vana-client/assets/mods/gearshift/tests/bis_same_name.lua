-- Gearshift's set builder: a held item that only shares the best in slot's name (an early stage of a relic) is the
-- pick only when it is no worse than the share's pick; held alone, the final stage is still worth getting.

local MAIN, BLM, ALL = 1, 1 << 4, 0x1fe
local ITEMS = {
  [3001] = { name = "Ref Staff", slots = MAIN, jobs = BLM, races = ALL, level = 1, description = "INT+2" },
  [3002] = { name = "Ref Staff", slots = MAIN, jobs = BLM, races = ALL, level = 1, description = "INT+20" },
  [3003] = { name = "Big Staff", slots = MAIN, jobs = BLM, races = ALL, level = 1, description = "INT+15" },
}
local held = { 3001, 3003 }
game = {
  player = function() return { name = "Tester", id = 100, index = 1, main_job = 4, main_level = 75, sub_job = 0,
    status = 0, pos = { x = 0, y = 0, z = 0 } } end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return {} end,
  items = function(bag)
    if bag ~= 12 then return {} end
    local out = {}
    for i, id in ipairs(held) do out[i] = { bag = 12, slot = i, id = id, count = 1, locked = 0 } end
    return out
  end,
  time = function() return { weekday = 0 } end, weather = function() return 0 end, buffs = function() return {} end,
}
res = setmetatable({
  item = function(id) return ITEMS[id] end,
  job = function(id) return ({ "WAR", "MNK", "WHM", "BLM" })[id] end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function(k) if k == "cap" then return "Auto" end return true end }
packets.inject_out = function() end
require("src.build.bis").lookup = function(_, _, set) return set == "Nuke" and { main = "Ref Staff" } or nil end

local run = require("src.build.run")
run.RANGES = { { 3001, 3004 } }
run.refresh()
for _ = 1, 80 do run.frame() end
local main = run.state.built.Nuke and run.state.built.Nuke.slots[0]
assert(main and main.ref and main.ref.id == 3002, "the reference is not the final stage")
assert(main.pick and main.pick.id == 3003, "an early stage taken over a better staff: " ..
  tostring(main.pick and main.pick.id))

-- Only the early stage held: it is the pick, and the final stage is worth getting.
held = { 3001 }
run.refresh()
for _ = 1, 80 do run.frame() end
main = run.state.built.Nuke.slots[0]
assert(main.pick and main.pick.id == 3001, "the early stage not picked: " .. tostring(main.pick and main.pick.id))
assert(main.worth and main.worth.id == 3002, "the final stage not worth getting: " ..
  tostring(main.worth and main.worth.id))
