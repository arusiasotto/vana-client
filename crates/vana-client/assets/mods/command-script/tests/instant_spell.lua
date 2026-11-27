local match = require("src.match")
local runner = require("src.runner")

local ENFIRE = 100
local t = 0
os.clock = function() return t end

game = {
  player = function() return { id = 1 } end,
  spells = function() return { ENFIRE } end,
  cast = function() return nil end,
}
actions = { cast = function() end }
commands = { run = function() end }
res = {
  spell = function(id)
    if id == ENFIRE then return { name = "Enfire", cast_time = 0 } end
  end,
  ability = function() end,
}

runner.SPELL_GAP = 0
runner.run("t", { '/ma "Enfire" <me>', 'then /ma "Gain-STR" <me>' })
runner.tick()
t = 0.1
runner.tick()
local r = runner.running and true
runner.on_action({
  actor = 1,
  category = 8,
  param = 0x6163,
  targets = { { results = { { value = ENFIRE } } } },
})
runner.tick()
t = 0.3
runner.tick()
assert(runner.running(), "enfire without cast bar finishes on magic start packet")