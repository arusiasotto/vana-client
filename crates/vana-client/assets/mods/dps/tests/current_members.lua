-- DPS: only the members with us get a row; the totals keep everyone's damage, and a pet briefly out of the entity
-- list keeps its history.

local H, T, CMD, shown, lines = {}, nil, nil, {}, {}
settings = { get = function() return true end }
events = { on = function(n, f) H[n] = f end }
timer = { every = function(_, f) T = f end }
commands = { register = function(_, f) CMD = f end }
ui = { window = function(_, s) shown = s.elements end, open = function() end, close = function() end }
chat = { add = function(s) lines[#lines + 1] = s end }
local now = 100
clock = function() return now end
local me = { id = 1, index = 10, name = "Nine" }
local party = { { party = 0, id = 1, name = "Nine" }, { party = 0, id = 2, name = "Shantotto" } }
local carbuncle = { id = 3, index = 12, name = "Carbuncle", master = 10 }
local ents = { [1] = me, [2] = { id = 2, index = 11, name = "Shantotto", master = 0 }, [3] = carbuncle,
  [4] = { id = 4, index = 13, name = "Stranger", master = 0 } }
game = { player = function() return me end, party = function() return party end, entity = function(id) return ents[id] end }
load(TEST.source("init.lua"), "@init.lua")()

H.damage(1, nil, 300)
H.damage(2, nil, 200)
H.damage(3, nil, 100)
H.damage(4, nil, 999)
now = 110
T()
assert(#shown == 3 and shown[1].label:find("^Nine") and shown[2].label:find("^Shantotto") and shown[3].label:find("^Carbuncle"))

-- The pet leaves the entity list for a tick and comes back: its row goes and returns with its damage.
ents[3] = nil
T()
assert(#shown == 2, #shown)
ents[3] = carbuncle
T()
assert(#shown == 3 and shown[3].label:find("^Carbuncle") and shown[3].text == "100  17%", shown[3].text)

-- Shantotto is dismissed: gone from the party and the zone. Her row goes; the total keeps her damage.
party[2], ents[2] = nil, nil
T()
assert(#shown == 2 and shown[1].label:find("^Nine") and shown[2].label:find("^Carbuncle"), #shown)
assert(shown[1].text == "300  50%", shown[1].text)
CMD()
assert(#lines == 3 and lines[1]:find("600 damage") and lines[2]:find("Nine: 300") and lines[3]:find("Carbuncle: 100"))
for _, l in ipairs(lines) do
  assert(not l:find("0x"), l)
end
