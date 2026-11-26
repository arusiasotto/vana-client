-- Gearshift's set builder: held gear with a superior level is picked up to ours (Su3 here), never above it.

local HEAD, BODY, DRK, ALL = 1 << 4, 1 << 5, 1 << 8, 0x1fe
local ITEMS = {
  [2001] = { name = "Plain Helm", slots = HEAD, jobs = DRK, races = ALL, level = 99, description = "DEF:50 STR+10" },
  [2002] = { name = "Su3 Helm", slots = HEAD, jobs = DRK, races = ALL, level = 99, superior_level = 3,
    description = "DEF:120 STR+30" },
  [2003] = { name = "Plain Mail", slots = BODY, jobs = DRK, races = ALL, level = 99, description = "DEF:60 STR+12" },
  [2004] = { name = "Su5 Mail", slots = BODY, jobs = DRK, races = ALL, level = 99, superior_level = 5,
    description = "DEF:150 STR+40" },
}
game = {
  player = function() return { name = "Tester", id = 100, index = 1, main_job = 8, main_level = 99, sub_job = 0,
    status = 0, pos = { x = 0, y = 0, z = 0 } } end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return {} end,
  stats = function() return { superior_level = 3 } end,
  items = function(bag)
    if bag ~= 0 then return {} end
    local out = {}
    for i, id in ipairs({ 2001, 2002, 2003, 2004 }) do
      out[i] = { bag = 0, slot = i, id = id, count = 1, locked = 0 }
    end
    return out
  end,
  time = function() return { weekday = 0 } end, weather = function() return 0 end, buffs = function() return {} end,
}
res = setmetatable({
  item = function(id) return ITEMS[id] end,
  job = function(id) return ({ "WAR", "MNK", "WHM", "BLM", "RDM", "THF", "PLD", "DRK" })[id] end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function(k) if k == "cap" then return "Auto" end return true end }
packets.inject_out = function() end
require("src.build.bis").lookup = function() return nil end

local run = require("src.build.run")
run.RANGES = { { 2001, 2005 } }
run.refresh()
for _ = 1, 200 do run.frame() end
local name = run.job_sets("DRK")[1]
local built = name and run.state.built[name]
assert(built, "no set built for DRK")
local function picked(slot)
  local o = built.slots[slot]
  return o and o.pick and ITEMS[o.pick.id].name
end
assert(picked(4) == "Su3 Helm", "Su3 helm passed over at Su3: " .. tostring(picked(4)))
assert(picked(5) == "Plain Mail", "Su5 mail picked at Su3: " .. tostring(picked(5)))
-- The level-cap reference is the true best, whatever our superior level.
assert(ITEMS[built.slots[5].ref.id].name == "Su5 Mail", "the reference left out Su5 gear")
