-- Gearshift's set builder: a Rare piece is named for one slot of a pair only (best in slot and worth getting), and
-- GM-only gear (item flag 0x2) is never a reference or worth getting.

local EAR1, EAR2, BACK, THF, ALL = 1 << 11, 1 << 12, 1 << 15, 1 << 6, 0x1fe
local RARE, GM = 0x8000, 0x0002
local ITEMS = {
  [4001] = { name = "Rare Earring", slots = EAR1 | EAR2, jobs = THF, races = ALL, level = 99, flags = RARE,
    description = "\"Store TP\"+10" },
  [4002] = { name = "Other Earring", slots = EAR1 | EAR2, jobs = THF, races = ALL, level = 99, flags = RARE,
    description = "\"Store TP\"+6" },
  [4003] = { name = "Judge Cape", slots = BACK, jobs = THF, races = ALL, level = 1, flags = GM,
    description = "\"Store TP\"+50" },
  [4004] = { name = "Real Cape", slots = BACK, jobs = THF, races = ALL, level = 99, flags = 0,
    description = "\"Store TP\"+3" },
  -- The automatic best earring: it takes the left ear there, leaving the right to the curated Rare one.
  [4005] = { name = "Big Earring", slots = EAR1 | EAR2, jobs = THF, races = ALL, level = 99, flags = RARE,
    description = "\"Store TP\"+20" },
}
game = {
  player = function() return { name = "Tester", id = 100, index = 1, main_job = 6, main_level = 99, sub_job = 0,
    status = 0, pos = { x = 0, y = 0, z = 0 } } end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return {} end,
  items = function() return {} end,
  time = function() return { weekday = 0 } end, weather = function() return 0 end, buffs = function() return {} end,
}
res = setmetatable({
  item = function(id) return ITEMS[id] end,
  job = function(id) return ({ "WAR", "MNK", "WHM", "BLM", "RDM", "THF" })[id] end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function(k) if k == "cap" then return "Auto" end return true end }
packets.inject_out = function() end
require("src.build.bis").lookup = function(_, _, set) return set == "TP" and { left_ear = "Rare Earring" } or nil end

local run = require("src.build.run")
run.RANGES = { { 4001, 4006 } }
run.refresh()
for _ = 1, 200 do run.frame() end
local built = run.state.built.TP
assert(built, "no TP set built for THF")
local function id(o) return o and o.id end
local s = built.slots
assert(id(s[11].ref) == 4001, "the curated left ear is not the reference: " .. tostring(id(s[11].ref)))
assert(id(s[12].ref) == 4005, "the Rare earring named for both ears: " .. tostring(id(s[12].ref)))
assert(id(s[11].worth) == 4005 and id(s[12].worth) == 4001,
  "worth getting names one Rare earring twice: " .. tostring(id(s[11].worth)) .. ", " .. tostring(id(s[12].worth)))
assert(id(s[15].ref) == 4004, "GM-only gear is the back reference: " .. tostring(id(s[15].ref)))
assert(id(s[15].worth) == 4004, "GM-only gear is worth getting: " .. tostring(id(s[15].worth)))
