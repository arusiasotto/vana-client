-- vanagear's /vg words: the toggles land in the builder's modes, /vg trusts reaches the trust gear, an unknown word says so.

game = { party = function() return {} end, player = function() return nil end }
res = setmetatable({}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function() return true end }

local vg = require("src.vg")
local run = require("src.build.run")
local trusts = require("src.trusts")

local said = {}
local add = chat.add
chat.add = function(t) said[#said + 1] = t end
local opened, reloaded = 0, 0
local ctx = { window = function() opened = opened + 1 end, reload = function() reloaded = reloaded + 1 end,
  file = function() return nil end }
local function cmd(...) said = {} vg.command({ ... }, ctx) return said[1] or "" end
local modes = run.modes()

cmd()
assert(opened == 1, "/vg opens the window")
assert(#vg.LINES > 5 and cmd("help") ~= "" and #said > 5, "/vg help lists the commands")

assert(cmd("dt", "pdt"):find("physical") and modes.pdt and not modes.mdt)
assert(cmd("dt", "mdt"):find("magic") and modes.mdt and not modes.pdt)
assert(cmd("dt", "all"):find("all") and modes.pdt and modes.mdt)
assert(cmd("dt", "off"):find("off") and not modes.pdt and not modes.mdt)
assert(cmd("dt"):find("all") and modes.pdt and modes.mdt, "no word turns it on")
assert(cmd("dt"):find("off") and not modes.pdt)

assert(cmd("tp", "hybrid"):find("hybrid") and modes.hybrid and not modes.acc)
assert(cmd("tp", "acc"):find("acc") and modes.acc and not modes.hybrid)
assert(cmd("tp", "default"):find("default") and not modes.acc and not modes.hybrid)
assert(cmd("tp"):find("hybrid") and modes.hybrid, "no word cycles")

assert(cmd("nuke", "acc"):find("acc") and modes.macc)
assert(cmd("nuke", "power"):find("power") and not modes.macc)
assert(cmd("burst", "on"):find("on") and modes.mb)
assert(cmd("burst", "off"):find("off") and not modes.mb)

assert(cmd("kite", "on"):find("on") and modes.kite)
assert(cmd("kite"):find("off") and not modes.kite, "no word flips it")
assert(cmd("th", "on"):find("on") and modes.th)
assert(cmd("th", "off"):find("off") and not modes.th)
assert(cmd("idle", "regen"):find("regen") and modes.idle == "regen")
assert(cmd("idle", "speed"):find("speed") and modes.idle == "speed")
assert(cmd("idle", "auto"):find("auto") and modes.idle == nil)
assert(cmd("pet", "dt"):find("dt") and modes.pet == "dt")
assert(cmd("pet"):find("tp") and modes.pet == nil, "no word is tp")
assert(cmd("lock", "nonsense"):find("Usage"))
assert(cmd("weapon", "main"):find("Usage") and cmd("why", "nothing"):find("Usage"))

-- /vg trusts goes to the trust gear: off stops sending, on starts it, a word it does not know says so.
local off = {}
cmd("trusts", "off")
assert(said[1]:find("off") and trusts.H.enabled() == false, said[1])
cmd("trusts", "on")
assert(trusts.H.enabled() == true)
assert(cmd("trusts"):find("on"), "the trust list starts with its state")

-- /gs: GearSwap's words as vanagear takes them.
local function gs(...) said = {} vg.gs({ ... }, ctx) return said[1] or "" end
assert(gs("c", "cycle", "OffenseMode", "Acc"):find("acc") and modes.acc)
assert(gs("c", "set", "HybridMode", "hybrid"):find("hybrid") and modes.hybrid)
gs("c", "set", "DefenseMode", "Physical")
assert(modes.pdt and modes.mdt, "a defense mode turns the damage taken gear on")
gs("c", "set", "DefenseMode", "None")
assert(not modes.pdt and not modes.mdt, "none turns it off")
assert(gs("c", "set", "IdleMode", "regen"):find("regen") and modes.idle == "regen")
gs("c", "toggle", "kiting")
assert(modes.kite)
gs("c", "toggle", "kiting")
assert(not modes.kite)
assert(gs("c", "update"):find("current"))
assert(gs("c", "th", "on"):find("on") and modes.th, "other words are /vg's")
assert(gs("th", "off"):find("off") and not modes.th)
assert(gs("equip"):find("Usage"), "equip takes a set")
assert(gs("validate"):find("not in this port"))
reloaded = 0
gs("reload")
assert(reloaded == 1)

assert(cmd("reload") and reloaded == 2)
assert(cmd("stage"):find("not in this port yet"))
chat.add = add
