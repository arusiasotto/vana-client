local match = require("src.match")
local runner = require("src.runner")

local HASTE = 57
local REFRESH = 81

game = {
  player = function() return { id = 0x42 } end,
  spells = function() return { HASTE, REFRESH } end,
  cast = function()
    return game._cast
  end,
}
res = {
  spell = function(id)
    if id == HASTE then return { name = "Haste II" } end
    if id == REFRESH then return { name = "Refresh II" } end
  end,
  ability = function() end,
}

match.lookup_spell("Haste II")
assert(match.lookup_spell("Haste II").wire == HASTE)
assert(match.lookup_spell("Refresh III").wire == REFRESH)
assert(match.lookup_spell("Refresh III").name == "Refresh II")

runner.run("t", { '/ma "Haste II" <me>', 'then /ma "Refresh III" <me>' })
runner.on_action({
  actor = 0x42,
  category = 8,
  param = 0x6163,
  targets = { { results = { { value = HASTE } } } },
})
runner.on_action({ actor = 0x42, category = 4, param = HASTE })
assert(runner.running(), "haste finish advances script")