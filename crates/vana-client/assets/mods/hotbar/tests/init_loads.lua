-- Hotbars: init.lua loads and wires every module.

chat = { add = function() end }
local HIDDEN = nil
local WINDOWS = {}
ui.native = { hide = function(_, on) HIDDEN = on end, list = function() return nil end,
  windows = function() return WINDOWS end }
res = setmetatable({ job = function(id) return ({ [1] = "WAR" })[id] end },
  { __index = function() return function() end end })
game = setmetatable({
  player = function() return { main_job = 1, sub_job = 0 } end,
  recasts = function() return { spells = {}, abilities = {}, totals = { spells = {}, abilities = {} } } end,
  info = function() return { server = "Test" } end,
}, { __index = function() return function() return {} end end })
local TIMERS = {}
local real_every = timer.every
timer.every = function(s, f) TIMERS[#TIMERS + 1] = f return real_every(s, f) end
local OVER = { on = true, hide_stock = true }
local real_get = settings.get
settings.get = function(k) if OVER[k] ~= nil then return OVER[k] end return real_get(k) end
local ok, err = pcall(require, "init")
assert(ok, tostring(err))

local function tick() for _, f in ipairs(TIMERS) do pcall(f) end end

-- Hide Stock Macro Bar: in gamepad mode a stock palette the game opened shows while it is up.
local mode = require("src.mode")
mode.set("gamepad")
tick()
assert(HIDDEN == true, "hidden while none is up")
WINDOWS = { "palette" }
tick()
assert(HIDDEN == false, "a stock palette up in gamepad mode shows")
WINDOWS = {}
tick()
assert(HIDDEN == true, "hidden again once it closes")
mode.set("hotbars")
WINDOWS = { "palette" }
tick()
assert(HIDDEN == true, "the keyboard's bars keep it hidden")
