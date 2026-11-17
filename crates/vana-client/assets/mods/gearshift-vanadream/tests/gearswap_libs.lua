-- Gearshift's built-in GearSwap libraries: M() modes, and texts boxes drawn as HUD texts (fields filled, colour
-- runs placed one after another by their drawn widths).

local M = require("src.modes")
local idle = M('refresh', 'dt', 'mdt')
assert(idle.value == 'refresh' and idle.current == 'refresh' and idle[1] == 'refresh' and idle.index == 1)
assert(idle:cycle() == 'dt' and idle:cycleback() == 'refresh' and idle:cycleback() == 'mdt')
idle:set('DT')
assert(idle.value == 'dt' and idle:contains('mdt') and not idle:contains('x') and tostring(idle) == 'dt')
idle:reset()
assert(idle.value == 'refresh')
local burst = M(false, 'Magic Burst')
assert(burst.value == false and burst.description == 'Magic Burst')
burst:toggle()
assert(burst.value == true)
burst:set('off')
assert(burst.value == false)
local s = M{ ['description'] = 'Weapon', ['string'] = 'Naegling' }
assert(s.value == 'Naegling' and s.description == 'Weapon')
local d = M{ ['description'] = 'Nuke', 'normal', 'acc' }
assert(d.description == 'Nuke' and d:length() == 2)

local drawn = {}
hud = { text = function(id, spec) drawn[id] = spec end, rect = function(id, spec) drawn[id] = spec end,
  remove = function(id) drawn[id] = nil end, screen = function() return { width = 1000, height = 800, ui_scale = 1 } end,
  bounds = function(id) local d = drawn[id] return d and d.text and { x = d.x, y = d.y, w = #d.text * 10, h = 18 * d.size } end }
local texts = require("src.texts")
local t = texts.new('Idle: \\cs(0,0,255)${idle|none}\\cr!', { pos = { x = 100, y = 50 }, padding = 5 })
t:show()
texts.frame()
texts.frame()
local a, b, c = drawn['gstext1_1_1'], drawn['gstext1_1_2'], drawn['gstext1_1_3']
assert(a.text == 'Idle: ' and b.text == 'none' and c.text == '!', tostring(b and b.text))
assert(b.colour[3] == 255 and a.x == 105 and b.x == 105 + 60 and c.x == 105 + 100, b.x .. ' ' .. c.x)
t.idle = 'dt'
texts.frame()
texts.frame()
assert(drawn['gstext1_1_2'].text == 'dt' and drawn['gstext1_1_3'].x == 105 + 80)
t:hide()
assert(next(drawn) == nil)
