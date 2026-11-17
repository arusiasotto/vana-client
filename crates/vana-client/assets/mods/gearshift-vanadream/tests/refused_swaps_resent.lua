-- Gearshift's core: a refused swap is sent again only around a weapon skill or a shot (LSB's weapons and ammo
-- lock), at most until the window closes, never once a later wear overtook it or the player changed the slot;
-- and it knows which worn pieces it put on (not one the player took off and put back).

local core = require("src.core")
local T, EQ, out = 0, {}, {}
local ITEMS = {
  [18136] = { name = "Morion Tathlum", slots = 1 << 3, level = 1 },
  [18254] = { name = "Tiphia Sting", slots = 1 << 3, level = 1 },
  [18166] = { name = "Happy Egg", slots = 1 << 3, level = 1 },
}
local BAG = { { bag = 0, slot = 1, id = 18136, count = 1, locked = 0 },
  { bag = 0, slot = 2, id = 18254, count = 1, locked = 0 }, { bag = 0, slot = 3, id = 18166, count = 1, locked = 0 } }
core.H = {
  player = function() return { main_job = 5, main_level = 75 } end,
  equipment = function() return EQ end,
  items = function(bag) return bag == 0 and BAG or {} end,
  item = function(id) return ITEMS[id] end,
  inject = function(d) out[#out + 1] = d end,
  now = function() return T end,
}
local function wear(name)
  core.send(core.packets(core.resolve({ [3] = { name = name } }, { log_names = false }), "single"))
end
local function retry_at(t) T = t return core.retry() end
EQ[3] = { bag = 0, slot = 1, id = 18136 }
-- No weapon skill or shot: a refusal is not sent again.
wear("Tiphia Sting")
assert(#out == 1, #out)
assert(retry_at(3) == 0, "retried outside a weapon skill")
-- A weapon skill at 3 s (window to 9 s): sent again while the refused send was inside the window.
core.note_action({ category = 7 })
wear("Tiphia Sting")
local n = {}
for _, t in ipairs({ 5.5, 8, 10.5, 13 }) do n[#n + 1] = retry_at(t) end
assert(table.concat(n, " ") == "1 1 1 0", table.concat(n, " "))
-- Taken this time: nothing to send again.
T = 20
core.note_action({ category = 7 })
wear("Tiphia Sting")
EQ[3] = { bag = 0, slot = 2, id = 18254 }
assert(retry_at(22.5) == 0, "retried a piece the server took")
assert(core.put_by_us(3, core.worn()[3]), "our own piece not known as ours")
-- A later wear overtakes a refusal: the stale piece never goes on.
T = 30
core.note_action({ category = 7 })
wear("Morion Tathlum")
T = 30.5
wear("Happy Egg")
assert(retry_at(33) == 1, "the newest refusal not sent again")
assert(core.sent[3].id == 18166, "the stale piece was sent")
-- The player put another piece there: not a refusal, and not ours.
T = 40
core.note_action({ category = 7 })
wear("Morion Tathlum")
EQ[3] = { bag = 0, slot = 3, id = 18166 }
assert(retry_at(42.5) == 0, "retried over the player's change")
assert(not core.put_by_us(3, core.worn()[3]), "the player's piece taken as ours")
-- Ours, taken off by the player and put back by hand: the player's now.
T = 50
wear("Tiphia Sting")
EQ[3] = { bag = 0, slot = 2, id = 18254 }
assert(core.put_by_us(3, core.worn()[3]), "our own piece not known as ours")
EQ[3] = nil
core.worn()
EQ[3] = { bag = 0, slot = 2, id = 18254 }
assert(not core.put_by_us(3, core.worn()[3]), "a piece put back by hand taken as ours")
