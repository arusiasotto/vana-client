-- The server's item tables: level, jobs, slots and stats read from them, over the client's text.

local server = require("src.build.server")
local pick = require("src.build.pick")

-- Enif Gambieras (10367): body-armour figures and a wyvern's HP.
local s = server.stats(10367)
assert(s, "known item")
assert(s.stats.def == 29 and s.stats.hp == 48 and s.stats.mp == 48 and s.stats.att == 6 and s.stats.acc == 6,
  "base stats")
assert(s.stats.haste == 4, "haste is kept in hundredths: " .. tostring(s.stats.haste))
assert(s.pet.wyvern and s.pet.wyvern.hp == 80, "pet stats go to the pet")

-- A weapon (Cesti, 16385): its damage and delay are stats like the item window shows them.
local cesti = server.stats(16385)
assert(cesti.stats.dmg == 1 and cesti.stats.delay == 528 and cesti.stats.acc == 3)

-- Damage taken, in whole points.
local dt = server.stats(28671)
assert(dt.stats.pdt == -4, tostring(dt.stats.pdt))

-- An item the tables do not know.
assert(server.item(1001) == nil and server.stats(1001) == nil)

-- Jobs: the server's job n is bit n-1, the client's bit n.
local haubert = server.item(10240)
assert(haubert.jobs == 8641 << 1 and haubert.level == 99)

-- The record the game gives, with the server's level, jobs and slots over it, and its text kept.
local rec = server.apply(10240, { name = "Hexed Haubert", description = "DEF:1", level = 1, jobs = 0, slots = 0,
  races = 0x1fe, superior_level = 1 })
assert(rec.level == 99 and rec.jobs == 8641 << 1 and rec.slots == 32 and rec.superior_level == 0)
assert(rec.name == "Hexed Haubert" and rec.races == 0x1fe and rec.server == true)
local plain = { name = "Fast Hat", level = 5 }
assert(server.apply(1001, plain) == plain, "unknown items are left as they are")

-- Through the picker: the server's figures count, augment lines add to them, and what takes other slots is left out.
pick.H.item = function(id)
  if id == 10367 then
    return { name = "Enif Gambieras", slots = 1 << 8, jobs = 0, races = 0x1fe, level = 1, description = "DEF:1 STR+1" }
  end
  if id == 10250 then
    return { name = "Moogle Suit", slots = 1 << 5, jobs = 0, races = 0x1fe, level = 1, description = "DEF:1" }
  end
end
local base = pick.stats_of(10367)
assert(base.stats.def == 29 and (base.stats.str or 0) == 0, "the server's figures, not the text's")
local augmented = pick.stats_of(10367, { "Accuracy+5" })
assert(augmented.stats.acc == 11, tostring(augmented.stats.acc))
assert(base.stats.acc == 6, "the plain stats are not changed by an augmented copy")
local feet = pick.item(10367)
assert(feet.level == 99 and feet.server, "the server's record")
assert(pick.fits(feet, 8, 7, 1, 99), "PLD (server jobs 41184 has bit 6) wears it at 99")
assert(not pick.fits(feet, 8, 7, 1, 98), "not below the server's level")
assert(not pick.fits(feet, 8, 3, 1, 99), "WHM is not in its jobs")
assert(pick.fits(pick.item(10250), 5, 1, 1, 99) == false, "a suit takes other slots")
