local runner = require("src.runner")
local match = require("src.match")

local ENFIRE, ENFIRE_II = 100, 312
local t = 0

os.clock = function() return t end
game = {
  player = function() return { id = 1 } end,
  spells = function() return { ENFIRE_II } end,
  cast = function() return game._cast end,
}
actions = { cast = function() end }
commands = { run = function() end }
res = {
  spell = function(id)
    if id == ENFIRE then return { name = "Enfire" } end
    if id == ENFIRE_II then return { name = "Enfire II" } end
  end,
  ability = function() end,
}

match.clear_spell_cache()
local step = match.lookup_spell("Enfire")
assert(step.wire == ENFIRE_II, "Enfire script picks learned Enfire II")

runner.SPELL_GAP = 0
runner.run("t", { '/ma "Enfire" <me>', 'then /ma "Gain-STR" <me>' })
runner.tick()
t = 0.1
runner.tick()
game._cast = { spell = ENFIRE_II }
runner.tick()
game._cast = nil
runner.tick()
assert(runner.running(), "enfire completes via cast bar even when script said Enfire")