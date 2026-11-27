local runner = require("src.runner")

local TEMPER, ENFIRE = 493, 100
local t = 0
local sent = {}

os.clock = function() return t end
actions = {
  cast = function(id, tgt) sent[#sent + 1] = ("cast:%d"):format(id) end,
}
commands = { run = function() end }

game = {
  player = function() return { id = 1 } end,
  spells = function() return { TEMPER, ENFIRE } end,
  cast = function() return game._cast end,
  buffs = function() return {} end,
}
res = {
  spell = function(id)
    if id == TEMPER then return { name = "Temper II", cast_time = 0 } end
    if id == ENFIRE then return { name = "Enfire", cast_time = 3 } end
  end,
  ability = function() end,
}

runner.SPELL_GAP = 0
runner.LINK_GAP = 0

runner.run("t", {
  '/ma "Temper II" <me>',
  'then /ma "Enfire" <me>',
  'then /ma "Gain-STR" <me>',
})

runner.tick()
t = 0.1
runner.on_action({ actor = 1, category = 4, param = TEMPER })
runner.tick()

runner.tick()
game._cast = { spell = ENFIRE }
assert(sent[#sent] == ("cast:%d"):format(ENFIRE), "enfire dispatches after temper")
runner.tick()
game._cast = nil
runner.tick()
assert(runner.running(), "enfire cast bar seen while watch is armed")