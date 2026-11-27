local runner = require("src.runner")

local HASTE, REFRESH = 57, 81
local t = 0
local sent = {}

os.clock = function() return t end
actions = {
  cast = function(id, tgt) sent[#sent + 1] = ("cast:%d %s"):format(id, tgt or "") end,
}
commands = { run = function(line) sent[#sent + 1] = line end }

game = {
  player = function() return { id = 0x42 } end,
  spells = function() return { HASTE, REFRESH } end,
  cast = function() end,
}
res = {
  spell = function(id)
    if id == HASTE then return { name = "Haste II" } end
    if id == REFRESH then return { name = "Refresh II" } end
  end,
  ability = function() end,
}

runner.SPELL_GAP = 0
runner.LINK_GAP = 0

runner.run("t", { '/ma "Haste II" <me>', 'then /ma "Refresh III" <me>' })
runner.tick()
t = t + 0.1
runner.tick()
runner.on_action({ actor = 0x42, category = 4, param = HASTE })
runner.tick()
t = t + 0.1
runner.tick()
assert(#sent == 2, "both spells dispatched")
assert(sent[1]:find("cast:" .. HASTE) and sent[2]:find("cast:" .. REFRESH), "refresh casts after haste finishes")