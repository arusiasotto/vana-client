-- vanagear's toggles in the builder: /vg idle (regen and refresh sets, auto by HP and MP with a margin), /vg kite and
-- /vg th (their gear laid over the status set), /vg lock, /vg weapon, /vg why, /vg upgrades, /vg set.

local sent = {}
local HEAD, FEET, HANDS, RING = 1 << 4, 1 << 8, 1 << 6, (1 << 13) | (1 << 14)
local WHM, ALL = 1 << 3, 0x1fe
local ITEMS = {
  [1101] = { name = "Regen Hat", slots = HEAD, jobs = WHM, races = ALL, level = 1, description = "DEF:5 Regen+3" },
  [1102] = { name = "Swift Boots", slots = FEET, jobs = WHM, races = ALL, level = 1, description = "DEF:3 Movement Speed+12%" },
  [1103] = { name = "Pilferer Gloves", slots = HANDS, jobs = WHM, races = ALL, level = 1, description = "DEF:3 Treasure Hunter+1" },
  [1104] = { name = "Plain Hat", slots = HEAD, jobs = WHM, races = ALL, level = 1, description = "DEF:10" },
  [1105] = { name = "Better Hat", slots = HEAD, jobs = WHM, races = ALL, level = 1, description = "DEF:6 Regen+5" },
  [1106] = { name = "Mind Ring", slots = RING, jobs = WHM, races = ALL, level = 1, description = "MND+4" },
}
local BAG = { { slot = 1, id = 1101 }, { slot = 2, id = 1102 }, { slot = 3, id = 1103 }, { slot = 4, id = 1104 },
  { slot = 5, id = 1106 } }
local STORAGE = { { slot = 1, id = 1105 } }
local P = { name = "Tester", id = 100, index = 1, main_job = 3, main_level = 75, sub_job = 0, status = 0, hpp = 100,
  mpp = 100, mp_max = 500, pos = { x = 0, y = 0, z = 0 } }
game = {
  player = function() return P end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return {} end,
  items = function(bag)
    local t = {}
    for _, b in ipairs(bag == 0 and BAG or (bag == 2 and STORAGE or {})) do
      t[#t + 1] = { bag = bag, slot = b.slot, id = b.id, count = 1, locked = 0 }
    end
    return t
  end,
  time = function() return { weekday = 1 } end, weather = function() return 0 end, buffs = function() return {} end,
}
res = setmetatable({
  item = function(id) return ITEMS[id] end,
  spell = function() end,
  job = function(id) return ({ "WAR", "MNK", "WHM" })[id] end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function(k) if k == "cap" then return "Auto" end return true end }
packets.inject_out = function(d) sent[#sent + 1] = d end

local run = require("src.build.run")
local core = require("src.core")
run.RANGES = { { 1101, 1110 } }
local function settle()
  run.refresh()
  for _ = 1, 120 do run.frame() end
end
settle()
local modes = run.modes()

-- Idle by HP and MP: regen below 60% HP, held until 80%; refresh below 70% MP.
assert(run.default_set() == "Idle")
P.hpp = 50
assert(run.default_set() == "Idle_Regen", run.default_set())
P.hpp = 70
assert(run.default_set() == "Idle_Regen", "regen let go at 70%")
P.hpp = 90
assert(run.default_set() == "Idle")
P.mpp = 40
assert(run.default_set() == "Idle_Refresh", run.default_set())
P.mpp, P.hpp = 100, 100
modes.idle = "regen"
assert(run.default_set() == "Idle_Regen")
modes.idle = "refresh"
assert(run.default_set() == "Idle_Refresh")
modes.idle = nil
assert(run.state.built.Idle_Regen and run.state.built.Idle_Regen.slots[4].pick.id == 1101,
  "the Idle regen set takes the regen hat")

-- Treasure Hunter is built when asked for (Movement is in a mage's sets already); their pieces go over the status set.
assert(not run.state.built.TH, "TH built before it was asked for")
modes.kite, modes.th = true, true
run.rebuild()
settle()
assert(run.state.built.Movement and run.state.built.TH, "the toggles bring their sets in")
assert(run.state.built.Movement.slots[8].pick.id == 1102 and run.state.built.TH.slots[6].pick.id == 1103)

-- Locked slots are left alone; others are worn.
local function worn_slots()
  local s = {}
  for _, d in ipairs(sent) do
    if (string.unpack("<I2", d) & 0x1ff) == 0x050 then s[string.unpack("B", d, 6)] = string.unpack("B", d, 5) end
  end
  return s
end
run.set_active(true)
modes.idle = "regen"
sent, core.sent, core.mine = {}, {}, {}
run.tick()
local first = worn_slots()
assert(first[4] == 1, "the regen hat worn from inventory slot 1")
assert(first[8] == 2 and first[6] == 3, "kite and TH gear over the idle set: boots and gloves")
run.lock(4, true)
sent, core.sent, core.mine = {}, {}, {}
run.tick()
assert(worn_slots()[4] == nil, "a locked slot was changed")
modes.idle = nil
run.lock("all", false)
assert(next(run.locks()) == nil)

-- A weapon of the player's in every set; one that is not carried is refused.
local ok = run.set_weapon("main", "Mind Ring")
assert(ok and run.pieces("Idle")[0] and run.pieces("Idle")[0].name == "Mind Ring")
assert(run.set_weapon("main", "Nonexistent Sword") == false)
assert(run.set_weapon("main", "none") and run.pieces("Idle")[0] == nil)

-- Why a piece won, and what is behind it.
local why = run.why("Idle_Regen", 4)
assert(why.won == "Regen Hat", tostring(why.won))
assert(why.list[1].name == "Regen Hat" and why.list[#why.list].name == "Plain Hat")

-- Upgrades: the Better Hat in storage would win the head slot.
local up = run.upgrades()
assert(#up > 0 and up[1].name == "Better Hat" and up[1].bag == "storage", up[1] and up[1].name)

-- A slot of a built set by hand, and a set found by its name or label.
assert(run.find_set("idle_regen") == "Idle_Regen" and run.find_set("Idle - regen") == "Idle_Regen")
assert(run.set_slot("Idle_Regen", "head", "Plain Hat"))
assert(run.pieces("Idle_Regen")[4].name == "Plain Hat")
assert(run.set_slot("Idle_Regen", "head", "auto") and run.pieces("Idle_Regen")[4].name == "Regen Hat")
assert(run.slot_index("ear1") == 11 and run.slot_index("ring2") == 14 and run.slot_index("head") == 4)
