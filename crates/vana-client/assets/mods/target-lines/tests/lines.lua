-- Target Lines: a support spell and a first melee hit draw lines, a second hit on the same pair does not, and the
-- glowing arc places sprites along its path.

local H, shapes, over = {}, {}, {}
local defaults = {
  on = true, color_blind = false, regular_attacks = "first", pair_cooldown = 8, special_lines = true,
  player_lines = true, party_lines = true, pet_lines = true, enemy_lines = true, other_party_lines = false,
  aoe_mode = "ring1", fade = 2, screen_lines = false, curved = true, thickness = 6, world_width = 0.1,
  source_height = 1, target_height = 1,
}
settings = { get = function(k) if over[k] ~= nil then return over[k] end return defaults[k] end }
events = { on = function(n, f) H[n] = f end }
draw = {
  clear = function() shapes = {} end,
  line = function(id, s) shapes[id] = s end,
  ring = function(id, s) shapes[id] = s end,
  to_screen = function(p) return { x = 100 + p.x * 40, y = 300 + p.y * 40, on_screen = true } end,
}
local images, moves = 0, 0
hud = {
  clear = function() end,
  image = function(id) shapes[id], images = true, images + 1 end,
  set = function(id) moves = moves + 1 end,
}
local clock = 0
os.clock = function() return clock end
commands = { register = function() end, run = function() end }
chat = { add = function() end }

local entities = {
  [1] = { id = 1, index = 1, kind = "player", pos = { x = 0, y = 0, z = 0 }, height = 2 },
  [2] = { id = 2, index = 2, kind = "player", pos = { x = 1, y = 0, z = 0 }, height = 2 },
  [50] = { id = 50, index = 50, kind = "mob", pos = { x = 5, y = 0, z = 5 }, height = 2, hpp = 100 },
}
game = {
  player = function() return entities[1] end,
  party = function() return { { id = 1, index = 1 }, { id = 2, index = 2 } } end,
  entity = function(id) return entities[id] end,
  entities = function() return { entities[50] } end,
}
res = { spell = function() return nil end }

load(TEST.source("init.lua"), "@init.lua")()
local E = require("engine")

local function count(pattern)
  local n = 0
  for k in pairs(shapes) do if k:match(pattern) then n = n + 1 end end
  return n
end

H.action({ actor = 1, category = 4, param = 3, targets = { { id = 2, results = { { value = 3 } } } } })
H.frame()
assert(count("^l%d") > 0, "a support spell draws a line")

H.action({ actor = 1, category = 1, targets = { { id = 50, results = { { message = 1 } } } } })
local after_first = E.count()
H.action({ actor = 1, category = 1, targets = { { id = 50, results = { { message = 1 } } } } })
assert(E.count() == after_first, "First only: a second hit on the same pair draws no line")

over.screen_lines = true
H.frame()
assert(count("^g%d") > 0, "the glowing arc places glow sprites")

clock = 0.5
H.frame()
local made = images
clock = 0.6
H.frame()
assert(images == made and moves > 0, "the next frame moves the sprites it made instead of loading new ones")

entities[50].hpp = 0
clock = 10
H.frame()
entities[50].hpp = 100
local before = E.count()
H.action({ actor = 1, category = 1, targets = { { id = 50, results = { { message = 1 } } } } })
assert(E.count() > before, "First only: a respawned mob gets its first line again")
