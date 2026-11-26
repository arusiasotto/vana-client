-- Gearshift's set builder: a slot takes the held piece worth the most to the set, not the one whose stats are most
-- like the best in slot's (a STR+1 ring over a "Store TP"+5 one); a held best in slot is worn even when the set's
-- weights give it nothing (a cape for Sneak Attack in the TP set); worth getting goes by score too.

local RING, BACK, THF, ALL = (1 << 13) | (1 << 14), 1 << 15, 1 << 6, 0x1fe
local ITEMS = {
  [6001] = { name = "Guide Ring", slots = RING, jobs = THF, races = ALL, level = 99, flags = 0x8000,
    description = "STR+10 Attack+16 \"Triple Attack\"+5%" },
  [6002] = { name = "Weak Ring", slots = RING, jobs = THF, races = ALL, level = 1, description = "STR+1 MND+1" },
  [6003] = { name = "Strong Ring", slots = RING, jobs = THF, races = ALL, level = 30,
    description = "\"Store TP\"+5 \"Subtle Blow\"+5" },
  [6004] = { name = "Guide Cape", slots = BACK, jobs = THF, races = ALL, level = 99, description = "\"Sneak Attack\"+10" },
  [6005] = { name = "Dodge Cape", slots = BACK, jobs = THF, races = ALL, level = 99, description = "AGI+7 Evasion+12" },
  [6006] = { name = "Alike Ring", slots = RING, jobs = THF, races = ALL, level = 99, description = "STR+2 Attack+2" },
  [6007] = { name = "Better Ring", slots = RING, jobs = THF, races = ALL, level = 99, description = "\"Store TP\"+9" },
}
local held = { 6002, 6003, 6004, 6005 }
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
  return set == "TP" and { left_ring = "Guide Ring", back = "Guide Cape" } or nil
end

local run = require("src.build.run")
run.RANGES = { { 6001, 6008 } }
run.refresh()
for _ = 1, 200 do run.frame() end
local s = run.state.built.TP.slots
local function name(o) return o and ITEMS[o.id] and ITEMS[o.id].name or "nothing" end
assert(name(s[13].ref) == "Guide Ring", "left ring reference: " .. name(s[13].ref))
local rings = name(s[13].pick) .. " / " .. name(s[14].pick)
assert(rings == "Strong Ring / Weak Ring", "the left ring took the ring most like the reference: " .. rings)
assert(name(s[15].pick) == "Guide Cape", "the held best in slot cape was left off: " .. name(s[15].pick))
-- Worth getting is the best by score, not the piece most like the reference.
assert(name(s[13].worth) == "Better Ring" or name(s[14].worth) == "Better Ring",
  "worth getting: " .. name(s[13].worth) .. " / " .. name(s[14].worth))
