-- The trust page of the //vg window: equipment grid, uses, and buttons.

local HEAD, RING = 1 << 4, (1 << 13) | (1 << 14)
local WHM, ALL = 1 << 3, 0x1fe
local ITEMS = {
  [1001] = { name = "Fast Hat", slots = HEAD, jobs = WHM, races = ALL, level = 1, description = 'DEF:5 "Fast Cast"+5%' },
  [1002] = { name = "Healer Hat", slots = HEAD, jobs = WHM, races = ALL, level = 40, description = 'DEF:6 MND+3\n"Cure" potency +10%' },
  [1004] = { name = "Mender Hat", slots = HEAD, jobs = WHM, races = ALL, level = 10, description = 'DEF:4 MND+2\n"Cure" potency +5%' },
  [1006] = { name = "Mind Ring", slots = RING, jobs = WHM, races = ALL, level = 1, description = "MND+4" },
}
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
settings = { get = function(key)
  if key == "grid_scale" then return 150 end
  return true
end }

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
  for _, e in ipairs(windows.gsvg.elements) do
    if e.id == id then return e end
  end
end

local function draw_has_icon(item_id)
  for _, d in ipairs(element("t_gear").draw or {}) do
    if d.type == "icon" and d.id == item_id then return true end
  end
end

local grid = require("src.equip_grid")
local run = require("src.build.run")
local trusts = require("src.trusts")
local win = require("src.build.window")
local trust_win = require("src.trust_window")
run.RANGES = { { 1001, 1010 } }
run.refresh()
for _ = 1, 80 do run.frame() end
local lines, now = {}, 10
trusts.H.say = function(line) lines[#lines + 1] = line end
trusts.H.now = function() return now end
win.install()

trusts.tick()
trust_win.toggle()
assert(opened.gsvg and win.tab() == 2)
assert(element("t_info").text:find("has not answered"), element("t_info").text)
assert(element("t_trust").items[1] == "Kupofried (WHM75)", element("t_trust").items[1])

trusts.filter("[VG trust] 16777217|Kupofried|3|0|75")
trusts.filter("[VG uses] 16777217|cure_iv:cure,savage_blade:weaponskill")
local guard = 0
while trusts.step() and guard < 20 do guard = guard + 1 end
win.draw()
assert(element("t_info").text:find("Kupofried: WHM75"), element("t_info").text)
assert(element("t_set").items[1] == "Engaged" and element("t_set").items[3] == "Cure",
  table.concat(element("t_set").items, ","))
assert(element("t_gear").w == win.trust_canvas_w() and #element("t_gear").draw > 0)
assert(#trusts.uses_of(trusts.called()[1]) == 2)

handlers.gsvg(nil, { kind = "set", id = "t_set", index = 3 })
assert(element("t_when").text:find("cure"))
local hx, hy = grid.center(4)   -- Head (grid is left-aligned in the trust canvas)
handlers.gsvg(nil, { kind = "click", id = "t_gear", button = "left", x = hx, y = hy })
local menu = menus[#menus]
assert(menu.items[1] == "Automatic" and menu.items[2] == "Empty" and #menu.items == 5, table.concat(menu.items, ","))
local fast
for i, name in ipairs(menu.items) do if name == "Fast Hat" then fast = i end end
menu.fn(fast)
assert(trusts.own_pick(trusts.called()[1], "Cure", "head") == "Fast Hat")
guard = 0
while trusts.step() and guard < 20 do guard = guard + 1 end
win.redraw()
assert(draw_has_icon(1001), "Fast Hat icon on grid")
assert(element("t_slot_detail").text:find("Fast Hat"), element("t_slot_detail").text)
menus[#menus].fn = nil
handlers.gsvg(nil, { kind = "click", id = "t_gear", button = "left", x = hx, y = hy })
menus[#menus].fn(2)
assert(trusts.own_pick(trusts.called()[1], "Cure", "head") == "remove")
handlers.gsvg(nil, { kind = "click", id = "t_gear", button = "left", x = hx, y = hy })
menus[#menus].fn(1)
assert(trusts.own_pick(trusts.called()[1], "Cure", "head") == nil)

local uses_x = grid.SIZE + win.USES_GAP + 4
handlers.gsvg(nil, { kind = "click", id = "t_gear", button = "left", x = uses_x, y = 40 })
assert(trusts.uses_of(trusts.called()[1])[1].off)
local sent
for _ = 1, 10 do
  now = now + 1.3
  trusts.tick()
end
for _, l in ipairs(lines) do if l == "/say !trustuse 16777217 off cure_iv" then sent = true end end
assert(sent, table.concat(lines, "\n"))

lines = {}
handlers.gsvg(nil, { kind = "press", id = "t_actions", index = 1 })
assert(trusts.queued() > 0)
trust_win.toggle()
assert(not opened.gsvg)

PARTY[2] = nil
win.open_tab(2)
assert(element("t_none").text:find("No trusts"))