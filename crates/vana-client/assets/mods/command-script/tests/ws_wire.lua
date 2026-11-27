local match = require("src.match")
local runner = require("src.runner")

local wid = 0x20
assert(match.ws_wire({ category = 3, param = wid }) == wid)
assert(match.ws_wire({ category = 7, param = wid }) == wid)
assert(match.ws_wire({ category = 11, param = wid }) == nil)

game = {
  player = function() return { id = 1 } end,
  abilities = function() return { wid } end,
  spells = function() return {} end,
}
res = { ability = function(id) return id == wid and { name = "Fast Blade" } end, spell = function() end }

local step = match.lookup_ws("Fast Blade")
assert(step and step.wire == wid)

runner.run("t", { '/ws "Fast Blade" <t>', 'then /ws "Savage Blade" <t>' })
assert(match.step_finished(step, { actor = 1, category = 3, param = wid }))
assert(not match.step_finished(step, { actor = 1, category = 7, param = wid }))