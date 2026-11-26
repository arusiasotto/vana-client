-- Hotbars' Builder: Rune Enchantment opens its runes, as the game's menu does (a search finds them too); the
-- line it builds can be replaced with the player's, kept with the entry.

local abilities = { [547] = { name = "Provoke", kind = 1, targets = 0x20, recast = 30 },
  [869] = { name = "Rune Enchantment", kind = 1, sub = 21, targets = 1 },
  [870] = { name = "Ignis", kind = 21, targets = 1, recast = 5 },
  [877] = { name = "Tenebrae", kind = 21, targets = 1, recast = 5 } }
res = { spell = function() end, ability = function(id) return abilities[id] end,
  job = function(id) return ({ [22] = "RUN" })[id] end }
game = { player = function() return { main_job = 22, sub_job = 0 } end,
  spells = function() return {} end, abilities = function() return { 547, 869, 870, 877 } end,
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
local function found() return ui.get("manager", "found") end
-- New, Job ability (the dropdown's second): Provoke and the opener; the runes only inside it.
H("manager", { kind = "press", id = "lbtn", index = 1 })
H("manager", { kind = "set", id = "btype", index = 2 })
H("manager", { kind = "select", id = "found", index = 2 })
-- Back, Ignis, Tenebrae.
H("manager", { kind = "select", id = "found", index = 2 })
local line = ui.get("manager", "line").text
assert(line == '/ja "Ignis" <me>', line)
-- A search finds a rune from the top list.
H("manager", { kind = "select", id = "found", index = 1 })
H("manager", { kind = "edit", id = "q", text = "tene" })
H("manager", { kind = "select", id = "found", index = 1 })
line = ui.get("manager", "line").text
assert(line == '/ja "Tenebrae" <me>', line)
-- Its line, saved with the entry and run in place of the built one.
H("manager", { kind = "change", id = "line", text = '/ja "Tenebrae" <stpc>' })
H("manager", { kind = "press", id = "bbar", index = 2 })
local e = data.library("RUN")[1].entry
assert(e.action.name == "Tenebrae" and e.action.line == '/ja "Tenebrae" <stpc>', e.action.line)
assert(data.entry_lines(e)[1] == '/ja "Tenebrae" <stpc>')
-- Provoke starts on the target, the Target dropdown sets another.
H("manager", { kind = "press", id = "lbtn", index = 1 })
H("manager", { kind = "set", id = "btype", index = 2 })
H("manager", { kind = "select", id = "found", index = 1 })
assert(ui.get("manager", "line").text == '/ja "Provoke" <t>')
H("manager", { kind = "set", id = "target", index = 3 })
assert(ui.get("manager", "line").text == '/ja "Provoke" <bt>', ui.get("manager", "line").text)
