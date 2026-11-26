-- Gearshift's set builder: 'Enhances "Dual Wield" effect' (no amount) counts, so such an earring is worn in a TP set;
-- a slot where no held piece gives the set anything takes the generally strongest piece instead of none.

local EAR, BACK, THF, ALL = (1 << 11) | (1 << 12), 1 << 15, 1 << 6, 0x1fe
local ITEMS = {
  [7001] = { name = "Swift Earring", slots = EAR, jobs = THF, races = ALL, level = 72,
    description = "AGI+2\nEnhances \"Dual Wield\" effect\nSword skill +5" },
  [7002] = { name = "Plain Earring", slots = EAR, jobs = THF, races = ALL, level = 1, description = "\"Store TP\"+1" },
  [7003] = { name = "Dodge Mantle", slots = BACK, jobs = THF, races = ALL, level = 99,
    description = "DEF:15 AGI+7\nEvasion+12 Magic Evasion+12" },
  [7004] = { name = "Thin Mantle", slots = BACK, jobs = THF, races = ALL, level = 1, description = "DEF:1" },
  [7005] = { name = "Set Earring", slots = EAR, jobs = THF, races = ALL, level = 1,
    description = "Set: Enhances \"Triple Attack\" effect" },
}
game = {
  player = function() return { name = "Tester", id = 100, index = 1, main_job = 6, main_level = 99, sub_job = 0,
    status = 0, pos = { x = 0, y = 0, z = 0 } } end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return {} end,
  items = function(bag)
    if bag ~= 0 then return {} end
    local out = {}
    for i, id in ipairs({ 7001, 7002, 7003, 7004, 7005 }) do
      out[i] = { bag = 0, slot = i, id = id, count = 1, locked = 0 }
    end
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
require("src.build.bis").lookup = function() return nil end

local stats = require("src.build.stats")
assert(stats.parse(ITEMS[7001].description).stats.dw, "an unnumbered Enhances \"Dual Wield\" line is not read")
assert(not stats.parse(ITEMS[7005].description).stats.ta, "a Set: Enhances line counted as a plain stat")

local run = require("src.build.run")
run.RANGES = { { 7001, 7006 } }
run.refresh()
for _ = 1, 200 do run.frame() end
local s = run.state.built.TP.slots
local function name(o) return o and ITEMS[o.id] and ITEMS[o.id].name or "nothing" end
local ears = name(s[11].pick) .. " / " .. name(s[12].pick)
assert(ears:find("Swift Earring", 1, true) and ears:find("Plain Earring", 1, true), "ears: " .. ears)
assert(name(s[15].pick) == "Dodge Mantle", "the back slot was left empty or weak: " .. name(s[15].pick))
