local match = require("src.match")

local ID = 215

game = { spells = function() return { ID } end }
res = {
  spell = function(id)
    if id == ID then return { name = "Gain-STR" } end
    if id ~= 0 then return { name = "" } end
  end,
}

-- Exact name from the full spell table (hotbar-style), not only a stale game.spells list entry.
assert(match.lookup_spell("Gain-STR").wire == ID)