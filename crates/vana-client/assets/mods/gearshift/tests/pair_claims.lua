-- Gearshift's set builder: each slot claims its held best in slot before any slot picks by score, so the left ring
-- (whose reference is not held) cannot take the right ring's reference.

local RING, THF, ALL = (1 << 13) | (1 << 14), 1 << 6, 0x1fe
local ITEMS = {
  [6101] = { name = "Left Guide Ring", slots = RING, jobs = THF, races = ALL, level = 99, flags = 0x8000,
    description = "Accuracy+10 \"Store TP\"+6" },
  [6102] = { name = "Right Guide Ring", slots = RING, jobs = THF, races = ALL, level = 99, flags = 0x8000,
    description = "\"Store TP\"+5 \"Subtle Blow\"+5" },
  [6103] = { name = "Weak Ring", slots = RING, jobs = THF, races = ALL, level = 1, description = "STR+1 MND+1" },
}
local held = { 6102, 6103 }
game = {
  player = function() return { name = "Tester", id = 100, index = 1, main_job = 6, main_level = 99, sub_job = 0,
    status = 0, pos = { x = 0, y = 0, z = 0 } } end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return {} end,
  items = function(bag)
    if bag ~= 16 then return {} end
    local out = {}
    for i, id in ipairs(held) do out[i] = { bag = 16, slot = i, id = id, count = 1, locked = 0 } end
    return out
  end,
  time = function() return { weekday = 0 } end, weather = function() return 0 end, buffs = function() return {} end,
}
res = setmetatable({
  item = function(id) return ITEMS[id] end,
  job = function(id) return ({ "WAR", "MNK", "WHM", "BLM", "RDM", "THF" })[id] end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function(k) if k == "cap" then return "Auto" end return true end }
packets.inject_out = function() end
require("src.build.bis").lookup = function(_, _, set)
  return set == "TP" and { left_ring = "Left Guide Ring", right_ring = "Right Guide Ring" } or nil
end

local run = require("src.build.run")
run.RANGES = { { 6101, 6104 } }
run.refresh()
for _ = 1, 200 do run.frame() end
local s = run.state.built.TP.slots
local function name(o) return o and ITEMS[o.id] and ITEMS[o.id].name or "nothing" end
local rings = name(s[13].pick) .. " / " .. name(s[14].pick)
assert(rings == "Weak Ring / Right Guide Ring", "the left ring took the right ring's best in slot: " .. rings)
assert(s[14].how == "bis", "the right ring is not worn as its best in slot: " .. tostring(s[14].how))
