-- Text Auto-Advance: OFF never moves a message on, Instant moves it as soon as it waits, a number of seconds once the
-- page has been open that long; never while a menu asks.

local secs, tick, advanced = 0, nil, 0
local ev = { text = { waiting = true, open = 0 } }
settings = { get = function() return secs end }
timer = { every = function(_, f) tick = f end }
game = { event = function() return ev end }
actions = { advance = function() advanced = advanced + 1 end }
load(TEST.source("init.lua"), "@init.lua")()

tick()
assert(advanced == 0, "OFF")

secs = -1
tick()
assert(advanced == 1, "Instant moves a waiting message on at once")

ev.menu = { question = "Yes?" }
tick()
assert(advanced == 1, "not while a menu asks")
ev.menu = nil

secs, ev.text.open = 3, 2.5
tick()
assert(advanced == 1, "3 s: not yet")
ev.text.open = 3
tick()
assert(advanced == 2, "3 s: once the page has been open 3 s")

ev.text.waiting = false
tick()
assert(advanced == 2, "a message that does not wait")
