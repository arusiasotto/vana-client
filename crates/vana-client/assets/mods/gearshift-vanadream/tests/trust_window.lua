-- The trust window: a trust's sets with a piece in every slot (one picked from a menu), what it uses (a click switches
-- one off), and the buttons.

local HEAD, RING = 1 << 4, (1 << 13) | (1 << 14)
local WHM, ALL = 1 << 3, 0x1fe
local ITEMS = {
  [1001] = { name = "Fast Hat", slots = HEAD, jobs = WHM, races = ALL, level = 1, description = 'DEF:5 "Fast Cast"+5%' },
  [1002] = { name = "Healer Hat", slots = HEAD, jobs = WHM, races = ALL, level = 40, description = 'DEF:6 MND+3\n"Cure" potency +10%' },
  [1004] = { name = "Mender Hat", slots = HEAD, jobs = WHM, races = ALL, level = 10, description = 'DEF:4 MND+2\n"Cure" potency +5%' },
  [1006] = { name = "Mind Ring", slots = RING, jobs = WHM, races = ALL, level = 1, description = "MND+4" },
}
-- What the server's tables say of them (see trusts.lua's test).
require("src.build.server").H.items = function()
  return {
    [1001] = "1|4|16||||1=5,170=5||", [1002] = "40|4|16||||1=6,13=3,374=10||", [1004] = "10|4|16||||1=4,13=2,374=5||",
    [1006] = "1|4|24576||||13=4||",
  }
end
local BAG = { { slot = 1, id = 1001 }, { slot = 2, id = 1002 }, { slot = 4, id = 1004 }, { slot = 5, id = 1006 } }
local TRUST = 0x01000001
local PARTY = {
  { party = 0, id = 100, index = 1, name = "Tester", main_job = 3, main_level = 75, sub_job = 0, sub_level = 0 },
  { party = 0, id = TRUST, index = 2, name = "Kupofried", main_job = 3, main_level = 75, sub_job = 0, sub_level = 0 },
}
game = {
  player = function() return { name = "Tester", id = 100, index = 1, main_job = 3, main_level = 75, sub_job = 0,
    status = 0, pos = { x = 0, y = 0, z = 0 } } end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return {} end,
  items = function(bag)
    if bag ~= 0 then return {} end
    local t = {}
    for _, b in ipairs(BAG) do t[#t + 1] = { bag = 0, slot = b.slot, id = b.id, count = 1, locked = 0 } end
    return t
  end,
  time = function() return { weekday = 1 } end, weather = function() return 0 end, buffs = function() return {} end,
  party = function() return PARTY end,
}
res = setmetatable({
  item = function(id) return ITEMS[id] end,
  spell = function() end,
  job = function(id) return ({ "WAR", "MNK", "WHM" })[id] end,
  ability = function() return nil end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function() return true end }

-- The ui, recorded.
local windows, handlers, menus, opened = {}, {}, {}, {}
ui = {
  window = function(id, spec) windows[id] = spec end,
  on = function(id, fn) handlers[id] = fn end,
  is_open = function(id) return opened[id] == true end,
  open = function(id) opened[id] = true end,
  close = function(id) opened[id] = nil end,
  menu = function(items, fn) menus[#menus + 1] = { items = items, fn = fn } end,
}
local function element(id)
  for _, e in ipairs(windows.gstrusts.elements) do
    if e.id == id then return e end
  end
end

local run = require("src.build.run")
local trusts = require("src.trusts")
local win = require("src.trust_window")
run.RANGES = { { 1001, 1010 } }
run.refresh()
for _ = 1, 80 do run.frame() end
local lines, now = {}, 10
trusts.H.say = function(line) lines[#lines + 1] = line end
trusts.H.now = function() return now end
win.install()

-- No answer yet: the window says so; nothing to pick.
trusts.tick()
win.toggle()
assert(opened.gstrusts and element("info").text:find("has not answered"), element("info").text)
assert(element("trust").items[1] == "Kupofried (WHM75)", element("trust").items[1])

-- The answers: its sets, its slots, its uses.
trusts.filter("[VG trust] 16777217|Kupofried|3|0|75")
trusts.filter("[VG uses] 16777217|cure_iv:cure,savage_blade:weaponskill")
local guard = 0
while trusts.step() and guard < 20 do guard = guard + 1 end
win.draw()
assert(element("info").text:find("Kupofried: WHM75"), element("info").text)
assert(element("set").items[1] == "Engaged" and element("set").items[3] == "Cure", table.concat(element("set").items, ","))
assert(#element("slots").rows == 16 and element("slots").rows[5][1] == "Head")
local uses = element("uses").rows
assert(#uses == 2 and uses[1][1] == "Cure IV" and uses[1][3] == "On", uses[1][1])

-- The Cure set's head, picked from the menu: the pieces we carry that fit, the set's best first.
handlers.gstrusts(nil, { kind = "set", id = "set", index = 3 })
assert(element("when").text:find("cure spells"))
handlers.gstrusts(nil, { kind = "select", id = "slots", index = 5 })   -- Head (row 5 = slot 4)
local menu = menus[#menus]
assert(menu.items[1] == "Automatic" and menu.items[2] == "Empty" and #menu.items == 5, table.concat(menu.items, ","))
local fast
for i, name in ipairs(menu.items) do if name == "Fast Hat" then fast = i end end
menu.fn(fast)
assert(trusts.own_pick(trusts.called()[1], "Cure", "head") == "Fast Hat")
guard = 0
while trusts.step() and guard < 20 do guard = guard + 1 end
win.redraw()
assert(element("slots").rows[5][2] == "Fast Hat" and element("slots").rows[5][3] == "yours", element("slots").rows[5][2])
-- Empty, then automatic again.
menus[#menus].fn = nil
handlers.gstrusts(nil, { kind = "select", id = "slots", index = 5 })
menus[#menus].fn(2)
assert(trusts.own_pick(trusts.called()[1], "Cure", "head") == "remove")
handlers.gstrusts(nil, { kind = "select", id = "slots", index = 5 })
menus[#menus].fn(1)
assert(trusts.own_pick(trusts.called()[1], "Cure", "head") == nil)

-- A click on a use switches it off, and the server hears it.
handlers.gstrusts(nil, { kind = "select", id = "uses", index = 1 })
assert(element("uses").rows[1][3] == "Off", element("uses").rows[1][3])
local sent
for _ = 1, 10 do
  now = now + 1.3
  trusts.tick()
end
for _, l in ipairs(lines) do if l == "/say !trustuse 16777217 off cure_iv" then sent = true end end
assert(sent, table.concat(lines, "\n"))

-- Buttons: send everything again, and close.
lines = {}
handlers.gstrusts(nil, { kind = "press", id = "actions", index = 1 })
assert(trusts.queued() > 0)
handlers.gstrusts(nil, { kind = "press", id = "actions", index = 4 })
assert(not opened.gstrusts)

-- The trust leaves: the window says so.
PARTY[2] = nil
win.draw()
assert(windows.gstrusts.elements[1].text:find("No trusts"))
