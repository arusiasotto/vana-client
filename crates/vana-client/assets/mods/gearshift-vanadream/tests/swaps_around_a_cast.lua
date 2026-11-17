-- Gearshift with a fake game: a GearSwap file and a LuAshitacast profile each wear their precast gear before a
-- Cure's action packet and their midcast gear after it, in one batch; the client's packet is dropped.

local sent, said = {}, {}
local ITEMS = {
  [1001] = { name = "Fast Hat", log_name = "Fast Hat", slots = 1 << 4, jobs = 1 << 3, level = 1 },
  [1002] = { name = "Cast Coat", log_name = "Cast Coat", slots = 1 << 5, jobs = 1 << 3, level = 1 },
  [1003] = { name = "Heal Gloves", log_name = "Healing Gloves", slots = 1 << 6, jobs = 1 << 3, level = 1 },
  [1004] = { name = "Idle Hat", log_name = "Idle Hat", slots = 1 << 4, jobs = 1 << 3, level = 1 },
}
local FILES = {}
game = {
  player = function() return { name = "Tester", id = 100, index = 1, main_job = 3, main_level = 75, sub_job = 4,
    sub_level = 37, hp = 900, mp = 500, tp = 0, hpp = 100, mpp = 100, hp_max = 900, mp_max = 500, status = 0, zone = 230 } end,
  equipment = function() return {} end,
  items = function(bag) if bag ~= 0 then return {} end
    return { { bag = 0, slot = 1, id = 1001, count = 1, locked = 0 }, { bag = 0, slot = 2, id = 1002, count = 1, locked = 0 },
      { bag = 0, slot = 3, id = 1003, count = 1, locked = 0 }, { bag = 0, slot = 4, id = 1004, count = 1, locked = 0 } } end,
  buffs = function() return {} end,
  target = function() return nil end,
  entity = function(id) return { id = id, index = 5, name = "Tester", kind = "player", me = true, hpp = 100, distance = 0, status = 0 } end,
  entity_by_tag = function() return nil end,
  time = function() return { weekday = 0, moon_phase = 0, moon = 50, hour = 12, minute = 0, day = 1 } end,
  weather = function() return 0 end,
  info = function() return { mog_house = false, zone = 230 } end,
  party = function() return {} end,
  find_items = function() return {} end,
  entities = function() return {} end,
}
res = setmetatable({
  item = function(id) return ITEMS[id] end,
  spell = function(id) if id == 1 then return { name = "Cure", kind = 1, skill = 33, element = 6, mp = 8, cast_time = 2, recast = 5, targets = 63 } end end,
  ability = function() return nil end,
  job = function(id) return ({ "WAR", "MNK", "WHM", "BLM" })[id] end,
  status = function() return nil end,
  zone = function() return "Somewhere" end,
  day = function() return "Firesday" end, moon = function() return "Full Moon" end, weather = function() return "Clear" end,
}, { __index = function() return function() return nil end end })
packets.inject_out = function(d) sent[#sent + 1] = d end
fs = { list = function(dir) local t = {} for k in pairs(FILES) do local n = k:match("^" .. dir:gsub("%p", "%%%0") .. "([^/]+)$") if n then t[#t + 1] = n end end return t end,
  read = function(p) return FILES[p] end, exists = function(p) return FILES[p] ~= nil end }
chat = { add = function(t) said[#said + 1] = t end }
local function cast_packet()
  return packets.build(0x01A, string.pack("<I4I2I2I4fff", 100, 1, 3, 1, 0, 0, 0))
end
local function ids()
  local t = {}
  for _, d in ipairs(sent) do t[#t + 1] = string.format("%03X", string.unpack("<I2", d) & 0x1ff) end
  return table.concat(t, " ")
end
local core = require("src.core")

FILES["gearswap/Tester_WHM.lua"] = [[
  function get_sets()
    sets.precast = { FC = { head = "Fast Hat", body = "Cast Coat" } }
    sets.midcast = { Cure = { hands = "Healing Gloves" } }
  end
  function precast(spell) if spell.action_type == "Magic" then equip(sets.precast.FC) end end
  function midcast(spell) if spell.english == "Cure" then equip(sets.midcast.Cure) end end
]]
local gs = require("src.gs")
assert(gs.find() == "gearswap/Tester_WHM.lua", tostring(gs.find()))
assert(gs.load(gs.find()), table.concat(said, " | "))
gs.typed('/ma "Cure" <me>')
local act = core.parse_action({ id = 0x01A, data = cast_packet() })
assert(gs.action(act) == false)
local gs_order = ids()
assert(sent[#sent]:sub(5, 8) == string.pack("BBBB", 3, 6, 0, 0), "the gloves after the action")
gs.unload()

sent = {}
core.sent = {}
FILES["ashitacast/Tester_100/WHM.lua"] = [[
  local profile = {}
  profile.Sets = { Precast = { Head = "Fast Hat", Body = "Cast Coat" }, Cure = { Hands = "Heal Gloves" } }
  profile.HandlePrecast = function() gFunc.EquipSet("precast") end
  profile.HandleMidcast = function() if gData.GetAction().Name == "Cure" then gFunc.EquipSet(profile.Sets.Cure) end end
  return profile
]]
local lac = require("src.lac")
assert(lac.find() == "ashitacast/Tester_100/WHM.lua", tostring(lac.find()))
assert(lac.load(lac.find()), table.concat(said, " | "))
act = core.parse_action({ id = 0x01A, data = cast_packet() })
assert(lac.action(act) == false)
local lac_order = ids()
lac.unload()

-- GearSwap: two pieces as single equips, then the action, then the midcast piece.
assert(gs_order == "050 050 01A 050", gs_order)
-- LuAshitacast: its precast one equipset, its midcast single equips.
assert(lac_order == "051 01A 050", lac_order)
