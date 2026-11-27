local runner = require("src.runner")

local ENFIRE, GAIN = 100, 486
local t = 0
local sent = {}
os.clock = function() return t end

game = {
  player = function() return { id = 1 } end,
  spells = function() return { ENFIRE, GAIN } end,
  cast = function() return nil end,
}
actions = { cast = function(id) sent[#sent + 1] = id end }
commands = { run = function() end }
res = {
  spell = function(id)
    if id == ENFIRE then return { name = "Enfire", cast_time = 3 } end
    if id == GAIN then return { name = "Gain-STR" } end
  end,
  ability = function() end,
}

runner.SPELL_GAP = 0
runner.run("t", { '/ma "Enfire" <me>', 'then /ma "Gain-STR" <me>' })
runner.tick()
assert(#sent == 1 and sent[1] == ENFIRE, "enfire dispatched with watch armed")
t = 0.3
runner.on_buff_gain(94)
runner.tick()
assert(runner.running(), "chain advances after generic buff_gain on <me>")