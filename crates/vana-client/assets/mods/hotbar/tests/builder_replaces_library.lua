-- Hotbars: New opens the Builder in the window's place (no tabs) and Save or Cancel brings the Library back; a
-- second New after a Save is a new entry, and the first, already on a slot, stays.

local spells = { [1] = { name = "Cure", mp = 8, kind = 1, targets = 0x1F },
  [144] = { name = "Fire", mp = 7, kind = 2, targets = 0x20 } }
res = { spell = function(id) return spells[id] end, ability = function() end,
  job = function(id) return ({ [5] = "RDM", [3] = "WHM" })[id] end }
game = { player = function() return { main_job = 5, sub_job = 3 } end,
  spells = function() return { 1, 144 } end, abilities = function() return {} end,
  find_items = function() return {} end }
chat = { add = function() end }
local on_window = ui.on
ui.on = function(id, f) if id == "manager" then H = f end; on_window(id, f) end
local data = require("src.data")
data.init({ read = function() return nil end, write = function() end, decode = json.decode,
  encode = json.encode })
local manager = require("src.manager")
manager.hooks = { changed = function() end, rebind = function() end }
manager.open()
local function has(id) return (pcall(ui.get, "manager", id)) end
assert(has("tabs") and has("lbtn") and not has("found"))
-- New, Cure, Save; its tile dropped on bar 1, slot 1.
H("manager", { kind = "press", id = "lbtn", index = 1 })
assert(has("found") and not has("tabs") and not has("lbtn"))
H("manager", { kind = "select", id = "found", index = 1 })
H("manager", { kind = "press", id = "bbar", index = 2 })
assert(has("tabs") and has("lbtn") and not has("found"))
data.assign("RDM", nil, 1, 1, data.library("RDM")[1].id)
-- New again: Fire, Save.
H("manager", { kind = "press", id = "lbtn", index = 1 })
H("manager", { kind = "select", id = "found", index = 2 })
H("manager", { kind = "press", id = "bbar", index = 2 })
-- Cancel keeps nothing and goes back.
H("manager", { kind = "press", id = "lbtn", index = 1 })
H("manager", { kind = "press", id = "bbar", index = 3 })
assert(has("lbtn") and not has("found"))
local lib = data.library("RDM")
assert(#lib == 2 and lib[1].entry.name == "Cure" and lib[2].entry.name == "Fire", #lib)
assert(data.resolve("RDM", nil, 1, 1).name == "Cure")
