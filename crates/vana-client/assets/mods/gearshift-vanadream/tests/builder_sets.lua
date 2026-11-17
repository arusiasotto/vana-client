-- Gearshift's set builder: items read from their descriptions, each set picked from our bags for our level, the
-- Fast Cast piece before a cast and the Cure piece after it; below an item's level the next best is taken, and
-- "worth getting" offers a piece wearable at our level that we do not hold.

local sent = {}
local HEAD, RING = 1 << 4, (1 << 13) | (1 << 14)
local WHM, ALL = 1 << 3, 0x1fe
local ITEMS = {
  [1001] = { name = "Fast Hat", slots = HEAD, jobs = WHM, races = ALL, level = 1, description = 'DEF:5 "Fast Cast"+5%' },
  [1002] = { name = "Healer Hat", slots = HEAD, jobs = WHM, races = ALL, level = 40, description = 'DEF:6 MND+3\n"Cure" potency +10%' },
  [1003] = { name = "Plain Hat", slots = HEAD, jobs = WHM, races = ALL, level = 1, description = "DEF:10" },
  [1004] = { name = "Mender Hat", slots = HEAD, jobs = WHM, races = ALL, level = 10, description = 'DEF:4 MND+2\n"Cure" potency +5%' },
  [1005] = { name = "Shop Hat", slots = HEAD, jobs = WHM, races = ALL, level = 20, description = 'DEF:4 MND+3\n"Cure" potency +8%' },
  [1006] = { name = "Mind Ring", slots = RING, jobs = WHM, races = ALL, level = 1, description = "MND+4" },
  [1007] = { name = "Korin Obi", slots = 1 << 10, jobs = WHM, races = ALL, level = 71, description = "DEF:7" },
  [1008] = { name = "Warp Ring", slots = RING, jobs = WHM, races = ALL, level = 1, description = "", max_charges = 1 },
}
local BAG = { { slot = 1, id = 1001 }, { slot = 2, id = 1002 }, { slot = 3, id = 1003 }, { slot = 4, id = 1004 },
  { slot = 5, id = 1006 }, { slot = 6, id = 1007 }, { slot = 7, id = 1008 } }
local EQUIP = {}
local level = 75
game = {
  player = function() return { name = "Tester", id = 100, index = 1, main_job = 3, main_level = level, sub_job = 0,
    status = 0, pos = { x = 0, y = 0, z = 0 } } end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return EQUIP end,
  items = function(bag)
    if bag ~= 0 then return {} end
    local t = {}
    for _, b in ipairs(BAG) do t[#t + 1] = { bag = 0, slot = b.slot, id = b.id, count = 1, locked = 0 } end
    return t
  end,
  time = function() return { weekday = WEEKDAY } end, weather = function() return 0 end, buffs = function() return {} end,
}
res = setmetatable({
  item = function(id) return ITEMS[id] end,
  spell = function(id) if id == 1 then return { name = "Cure", kind = 1, skill = 33, element = 6 } end end,
  job = function(id) return ({ "WAR", "MNK", "WHM" })[id] end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
WEEKDAY = 6
settings = { get = function(k) if k == "cap" then return "Auto" end return true end }
packets.inject_out = function(d) sent[#sent + 1] = d end

local run = require("src.build.run")
local core = require("src.core")
run.RANGES = { { 1001, 1010 } }
local function settle()
  run.refresh()
  for _ = 1, 80 do run.frame() end
end
settle()
local nuke = run.state.built.Cure
assert(nuke, "the Cure set is built")
-- A bag change rebuilds every set; the one built stays in use until built again, and the one an action asks for
-- goes first.
run.rebuild()
assert(run.state.built.Cure == nuke, "the Cure set dropped by a rebuild")
run.pieces("Cure")
assert(run.state.queue[1] == "Cure", "the asked-for set not first")
for _ = 1, 80 do run.frame() end
assert(run.state.built.Cure ~= nuke and run.state.fresh.Cure, "the Cure set not built again")

local function cast()
  return core.parse_action({ id = 0x01A, data = packets.build(0x01A, string.pack("<I4I2I2I4fff", 100, 1, 3, 1, 0, 0, 0)) })
end
-- The window's switch off: nothing is worn.
assert(run.action(cast()) == nil and #sent == 0, "worn with the switch off")
run.set_active(true)
-- The cast on Lightsday: Fast Hat (bag index 1) before it, Healer Hat (index 2) after it, and the light obi
-- (index 6) for Cure on the light day.
assert(run.action(cast()) == false)
local order = {}
for _, d in ipairs(sent) do
  local id = string.unpack("<I2", d) & 0x1ff
  order[#order + 1] = string.format("%03X", id) .. (id == 0x050 and (":" .. string.unpack("B", d, 5)) or "")
end

-- Earthsday: no obi for Cure (the day is earth, not light).
WEEKDAY = 1
local before = #sent
core.sent = {}
run.action(cast())
local obi = false
for i = before + 1, #sent do
  if (string.unpack("<I2", sent[i]) & 0x1ff) == 0x050 and string.unpack("B", sent[i], 5) == 6 then obi = true end
end
assert(not obi, "the light obi worn on Earthsday")

-- A weapon skill: one chat line naming its set (or saying there is none).
local said, add = {}, chat.add
chat.add = function(t) said[#said + 1] = t end
run.action(core.parse_action({ id = 0x01A, data = packets.build(0x01A, string.pack("<I4I2I2I4fff", 100, 1, 7, 1, 0, 0, 0)) }))
chat.add = add
assert(#said == 1 and said[1]:find("^Gearshift: "), tostring(said[1]))

-- A weapon skill's set goes out before the weapon skill (it lands at once): a hand-picked hat ahead of the 0x01A.
local function ws_act()
  return core.parse_action({ id = 0x01A, data = packets.build(0x01A, string.pack("<I4I2I2I4fff", 100, 1, 7, 1, 0, 0, 0)) })
end
local ws_set = run.route(ws_act())[2]
assert(ws_set, "no weapon skill set for the test job")
run.hand("WHM", ws_set).head = { name = "Plain Hat" }
sent, core.sent = {}, {}
chat.add = function() end
assert(run.action(ws_act()) == false)
chat.add = add
local seq = {}
for _, d in ipairs(sent) do seq[#seq + 1] = string.format("%03X", string.unpack("<I2", d) & 0x1ff) end
assert(table.concat(seq, " ") == "050 01A", table.concat(seq, " "))
run.hand("WHM", ws_set).head = nil

-- A charged ring the player put on keeps its slot through a set change; one we put on does not.
local function ring_slot()
  for slot, p in pairs(run.pieces("Cure")) do if p.name == "Mind Ring" then return slot end end
end
local rs = assert(ring_slot(), "no ring in the Cure set")
local function ring_sent()
  for _, d in ipairs(sent) do
    if (string.unpack("<I2", d) & 0x1ff) == 0x050 and string.unpack("B", d, 6) == rs then return true end
  end
  return false
end
EQUIP[rs] = { bag = 0, slot = 7, id = 1008 }
sent, core.sent, core.mine = {}, {}, {}
run.action(cast())
assert(not ring_sent(), "the player's Warp Ring taken off")
sent, core.sent, core.mine = {}, {}, { [rs] = { bag = 0, index = 7, id = 1008 } }
run.action(cast())
assert(ring_sent(), "a charged ring we put on held its slot")
-- A potion changes nothing; using the ring lets it go.
core.mine = {}
run.on_action({ actor = 100, category = 5, param = 4112 })
sent, core.sent = {}, {}
run.action(cast())
assert(not ring_sent(), "a potion let the ring go")
run.on_action({ actor = 100, category = 5, param = 1008 })
sent, core.sent = {}, {}
run.action(cast())
assert(ring_sent(), "the used ring kept its slot")
EQUIP[rs] = nil

-- At level 30 the Healer Hat (40) is out: the Mender Hat, the most of the reference we hold; the Shop Hat
-- (20, not held) is worth getting.
level = 30
core.sent = {}
settle()
local cure = run.state.built.Cure.slots[4]
local low = ITEMS[cure.pick.id].name .. " " .. cure.how .. " / " .. (cure.worth and ITEMS[cure.worth.id].name or "none")
-- The midcast in slot order: the Cure hat, the light obi on Lightsday (waist), the MND ring.
local seq = table.concat(order, " ")
assert(seq == "050:1 01A 050:2 050:6 050:5", seq)
assert(low == "Mender Hat bis / Shop Hat", low)
