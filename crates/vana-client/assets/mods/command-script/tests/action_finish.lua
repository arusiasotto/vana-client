local match = require("src.match")
local runner = require("src.runner")

game = {
  player = function() return { id = 0x42 } end,
  abilities = function() return { 0x200 + 50 } end,
  spells = function() return {} end,
}
res = {
  ability = function(id) return id == 0x200 + 50 and { name = "Composure" } or nil end,
  spell = function() end,
}

local step = match.lookup_ja("Composure")
assert(step and step.wire == 50)

runner.run("t", { '/ja "Composure" <me>', 'then /ma "Haste II" <me>' })
runner.on_action({ actor = 0x42, category = 6, param = 50 })
assert(runner.running(), "recognizes ja finish wire param")