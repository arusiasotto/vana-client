-- Trust gear (the Vanadreams server's !trustgear): a trust in the party is asked about once, its answer builds its sets
-- from the pieces we do not wear ourselves, the lines go out one at a time and their echo stays out of the chat log.

local HEAD, RING = 1 << 4, (1 << 13) | (1 << 14)
local WHM, ALL = 1 << 3, 0x1fe
local ITEMS = {
  [1001] = { name = "Fast Hat", slots = HEAD, jobs = WHM, races = ALL, level = 1, description = 'DEF:5 "Fast Cast"+5%' },
  [1002] = { name = "Healer Hat", slots = HEAD, jobs = WHM, races = ALL, level = 40, description = 'DEF:6 MND+3\n"Cure" potency +10%' },
  [1003] = { name = "Plain Hat", slots = HEAD, jobs = WHM, races = ALL, level = 1, description = "DEF:10" },
  [1004] = { name = "Mender Hat", slots = HEAD, jobs = WHM, races = ALL, level = 10, description = 'DEF:4 MND+2\n"Cure" potency +5%' },
  [1006] = { name = "Mind Ring", slots = RING, jobs = WHM, races = ALL, level = 1, description = "MND+4" },
}
local BAG = { { slot = 1, id = 1001 }, { slot = 2, id = 1002 }, { slot = 3, id = 1003 }, { slot = 4, id = 1004 },
  { slot = 5, id = 1006 } }
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

local run = require("src.build.run")
local trusts = require("src.trusts")
run.RANGES = { { 1001, 1010 } }
run.refresh()
for _ = 1, 80 do run.frame() end
assert(run.state.built.Cure, "our Cure set is built")

local lines, now = {}, 10
trusts.H.say = function(line) lines[#lines + 1] = line end
trusts.H.now = function() return now end
local function pump()
  for _ = 1, 20 do
    now = now + 1.3
    trusts.tick()
  end
end

-- Names as the server keeps them.
assert(trusts.key("Savage Blade") == "savageblade" and trusts.pretty("cure_iv") == "Cure IV")

-- A trust called: asked about once (its info, and what is switched off), nothing built before it answers.
trusts.tick()
assert(#lines == 1, "the first line goes at once")
-- The echo of our line stays out of the log, once; a line of someone else's is kept.
assert(trusts.filter("Tester : !trustgear 16777217 info") == false)
assert(trusts.filter("Tester : !trustgear 16777217 info") == nil, "the echo dropped twice")
assert(trusts.filter("Someone : hello") == nil)
pump()
assert(#lines == 2, table.concat(lines, "\n"))
assert(lines[1] == "/say !trustgear 16777217 info" and lines[2] == "/say !trustuse 16777217 info", lines[1])
pump()
assert(#lines == 2, "asked again")
assert(not trusts.step() and not trusts.built[TRUST], "built before the server answered")

-- The answers are dropped from the log.
assert(trusts.filter("[VG trust] 16777217|Kupofried|3|0|75") == false)
assert(trusts.filter("[VG uses] 16777217|cure_iv:cure,savage_blade:weaponskill") == false)
assert(trusts.filter("[VG off] 16777217|cureiv") == false)
assert(trusts.info[TRUST].level == 75 and #trusts.info[TRUST].uses == 2 and trusts.info[TRUST].off.cureiv)

-- The sets: Engaged, Weaponskill (it uses one) and Cure (a weapon skill with no facts here gets no set of its own),
-- built from what we do not hold.
local guard = 0
while trusts.step() and guard < 20 do guard = guard + 1 end
local b = assert(trusts.built[TRUST], "no sets built")
local keys = {}
for _, e in ipairs(b.plan) do keys[#keys + 1] = e.key end
assert(table.concat(keys, ",") == "engaged,weaponskill,cure", table.concat(keys, ","))
local ours = run.state.built.Cure.slots[4].pick.id
local head = tonumber(b.ids.cure:match("^%d+ %d+ %d+ %d+ (%d+)"))
assert(ours == 1002, "our Cure hat is the Healer Hat, not " .. tostring(ours))
assert(head ~= 1002 and head ~= 0, "the trust took our hat or none: " .. tostring(head))

-- Every set with a piece is sent (the empty Weaponskill set is not: the server has none to clear), one line each,
-- 1.2 s apart, with the 16 ids.
lines = {}
now = now + 1.3
trusts.tick()
-- The line we sent is dropped when it comes back.
assert(#lines == 1 and trusts.filter("Tester : " .. lines[1]:gsub("^/say ", "")) == false)
pump()
assert(#lines == 2, table.concat(lines, "\n"))
for _, l in ipairs(lines) do
  assert(l:match("^/say !trustgear 16777217 %l+ [%d ]+$"), l)
  local n = 0
  for _ in l:gsub("^/say !trustgear %d+ %l+ ", ""):gmatch("%d+") do n = n + 1 end
  assert(n == 16, l)
end

-- Nothing is sent again while nothing changed.
lines = {}
trusts.rebuild()
guard = 0
while trusts.step() and guard < 20 do guard = guard + 1 end
pump()
assert(#lines == 0, "sent again with nothing changed: " .. table.concat(lines, "\n"))

-- The send command sends everything again.
trusts.command({ "send" })
pump()
assert(#lines == 3, #lines)

-- A pick of ours for a slot goes out in its place.
lines = {}
trusts.command({ "set", "Kupofried", "cure", "head", "Fast Hat" })
guard = 0
while trusts.step() and guard < 20 do guard = guard + 1 end
pump()
assert(#lines == 1 and lines[1]:match("^/say !trustgear 16777217 cure 0 0 0 0 1001 "), table.concat(lines, "\n"))

-- A use switched off goes to the server as !trustuse.
lines = {}
trusts.command({ "use", "Kupofried", "off", "Cure", "IV" })
pump()
assert(lines[1] == "/say !trustuse 16777217 off Cure IV", tostring(lines[1]))

-- The trust leaves: forgotten.
PARTY[2] = nil
trusts.tick()
assert(trusts.built[TRUST] == nil and trusts.info[TRUST] == nil)
