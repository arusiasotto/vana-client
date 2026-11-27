local runner = require("src.runner")

local A, B, C = 57, 81, 100
local t = 0
local sent = {}

os.clock = function() return t end
actions = {
  cast = function(id) sent[#sent + 1] = id end,
}
commands = { run = function() end }
game = {
  player = function() return { id = 1 } end,
  spells = function() return { A, B, C } end,
  cast = function() end,
}
res = {
  spell = function(id)
    if id == A then return { name = "Haste II" } end
    if id == B then return { name = "Refresh II" } end
    if id == C then return { name = "Enfire" } end
  end,
  ability = function() end,
}

runner.SPELL_GAP = 0
runner.LINK_GAP = 0

runner.run("t", {
  '/ma "Haste II" <me>',
  'then /ma "Refresh III" <me>',
  'then /ma "Enfire" <me>',
})

runner.tick() -- haste
t = t + 0.1
runner.on_action({ actor = 1, category = 4, param = A })
runner.tick() -- refresh
t = t + 0.1
runner.on_action({ actor = 1, category = 4, param = B })
runner.tick()

assert(sent[1] == A, "first cast is haste")
assert(sent[2] == B, "second cast is refresh (then line must not be skipped)")