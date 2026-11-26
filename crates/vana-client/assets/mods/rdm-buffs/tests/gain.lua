-- RDM Buffs, Gain-STR: retail's STR Boost (119) and LSB's (80) both count as up; with neither it is missing.

local SET = {
  window = true, early = 20, composure = false, haste = false, refresh = false, phalanx = false, temper = false,
  gain = "STR", enspell = "Off", protect = false, regen = false, stoneskin = false, aquaveil = false, shadows = false,
  spikes = "Off", reraise = false, sublimation = false,
}
local SPELLS = {
  [57] = { name = "Haste", levels = { [5] = 48 }, mp = 40 },
  [109] = { name = "Refresh", levels = { [5] = 41 }, mp = 40 },
  [473] = { name = "Refresh II", levels = { [5] = 82 }, mp = 60 },
  [486] = { name = "Gain-STR", levels = { [5] = 90 }, mp = 36 },
  [106] = { name = "Phalanx", levels = { [5] = 33 }, mp = 21 },
  [107] = { name = "Phalanx II", levels = { [5] = 75 }, mp = 42 },
  [53] = { name = "Blink", levels = { [5] = 23 }, mp = 20 },
  [338] = { name = "Utsusemi: Ichi", levels = { [13] = 12 }, mp = 0 },
  [339] = { name = "Utsusemi: Ni", levels = { [13] = 37 }, mp = 0 },
}

local tick, rows, cmd, handler
BUFFS = {}
local casts, lines = {}, {}
settings = { get = function(k) return SET[k] end }
timer = { every = function(_, f) tick = f end }
events = { on = function() end }
res = { spell = function(id) return SPELLS[id] end, ability = function() end }
game = {
  player = function() return { main_job = 5, main_level = 99, sub_job = 13, sub_level = 49, mp = 900 } end,
  buffs = function() return BUFFS end,
  spells = function()
    local out = {}
    for id in pairs(SPELLS) do out[#out + 1] = id end
    return out
  end,
  abilities = function() return {} end,
  recasts = function() return { abilities = {}, spells = { [339] = 30 } } end,
  cast = function() return nil end,
  job_points = function() return {} end,
}
actions = { cast = function(id) casts[#casts + 1] = id end, ability = function() end }
wait_until = function() end
chat = { add = function(t) lines[#lines + 1] = t end }
commands = { register = function(_, f) cmd = f end }
ui = {
  window = function(_, spec)
    rows = spec.elements[1].rows
  end,
  open = function() end,
  close = function() end,
  on = function(_, f) handler = f end,
}
load(TEST.source("init.lua"), "@init.lua")()

local function listed()
  rows = {}
  tick()
  local got = {}
  for _, r in ipairs(rows or {}) do got[#got + 1] = r.cells[1] end
  return table.concat(got, ", ")
end

BUFFS = { { id = 119, remaining = 1000 } }
assert(listed() == "", "retail STR Boost: " .. listed())
BUFFS = { { id = 80, remaining = 1000 } }
assert(listed() == "", "LSB STR Boost: " .. listed())
BUFFS = {}
assert(listed() == "Gain-STR", "none: " .. listed())
