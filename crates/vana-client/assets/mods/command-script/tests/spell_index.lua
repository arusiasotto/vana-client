local match = require("src.match")

game = {
  spells = function() return { 100, 101 } end,
}
res = {
  spell = function(id)
    if id == 100 then return { name = "Enfire" } end
    if id == 101 then return { name = "Enfire II" } end
  end,
}

match.clear_spell_cache()
assert(match.lookup_spell("Enfire").wire == 100)
assert(match.lookup_spell("Enfire II").wire == 101)