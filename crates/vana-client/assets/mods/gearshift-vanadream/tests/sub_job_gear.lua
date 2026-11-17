-- The Vanadreams server lets the support job's gear be worn, at the main job's level.

local pick = require("src.build.pick")
local WHM, BLM, WAR = 3, 4, 1
local rec = { name = "Black Hat", slots = 1 << 4, jobs = 1 << BLM, races = 0x1fe, level = 20 }
assert(not pick.fits(rec, 4, WHM, 1, 75), "a WHM cannot wear BLM gear alone")
assert(pick.fits(rec, 4, WHM, 1, 75, BLM), "with BLM as support it can")
assert(not pick.fits(rec, 4, WHM, 1, 75, WAR), "another support job does not help")
assert(not pick.fits(rec, 4, WHM, 1, 10, BLM), "the level is still the main job's")
assert(not pick.fits(rec, 4, WHM, 1, 75, 0), "no support job")
assert(not pick.fits(rec, 5, WHM, 1, 75, BLM), "the slot still has to fit")

-- Candidates take the support job's pieces too.
pick.H.item = function(id) if id == 1 then return rec end end
local index = { [4] = { 1 } }
assert(#pick.candidates(index, WHM, 1, 75, BLM)[4] == 1)
assert(#pick.candidates(index, WHM, 1, 75)[4] == 0)
