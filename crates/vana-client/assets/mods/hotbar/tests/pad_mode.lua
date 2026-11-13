-- Hotbars' gamepad mode: the crossbars keep library macros per main job (by reference, like the bars' slots), a
-- button press runs one (a group runs the member picked last), and the mode switches between the crossbars and the
-- keyboard's bars.

local abilities = { [869] = { name = "Rune Enchantment", kind = 1, sub = 21, targets = 1 },
  [870] = { name = "Ignis", kind = 21, targets = 1, recast = 5 },
  [877] = { name = "Tenebrae", kind = 21, targets = 1, recast = 5 } }
res = { spell = function() end, ability = function(id) return abilities[id] end,
  job = function(id) return ({ [22] = "RUN" })[id] end }
game = { player = function() return { main_job = 22, sub_job = 0 } end,
  spells = function() return {} end, abilities = function() return { 869, 870, 877 } end,
  find_items = function() return {} end,
  recasts = function() return { spells = {}, abilities = {}, totals = { spells = {}, abilities = {} } } end }
chat = { add = function() end }
SENT = {}
commands.run = function(line) SENT[#SENT + 1] = line end

local data = require("src.data")
data.init({ read = function() return nil end, write = function() end, decode = json.decode,
  encode = json.encode })

-- The slots: a library entry by reference, swapped, cleared, counted among its uses and gone with it.
local id = data.save_entry("RUN", nil, { name = "Ignis", action = { kind = "ja", name = "Ignis", target = "me" },
  lines = { "/p Ignis up" } })
assert(data.pad_resolve("RUN", "lt", "up") == nil)
data.pad_assign("RUN", "lt", "up", id)
local m = data.pad_resolve("RUN", "lt", "up")
assert(m.ref == id and m.lines[1] == '/ja "Ignis" <me>' and m.lines[2] == "/p Ignis up")
assert(data.uses("RUN", id) == 1)
data.pad_swap("RUN", "lt", "up", "rt", "a")
assert(data.pad_resolve("RUN", "lt", "up") == nil and data.pad_resolve("RUN", "rt", "a").ref == id)
assert(data.get_raw("RUN", nil, 1, 1) == nil, "the bars are not touched")
data.pad_clear("RUN", "rt", "a")
assert(data.pad_resolve("RUN", "rt", "a") == nil and data.uses("RUN", id) == 0)
data.pad_assign("RUN", "rt", "x", id)
data.delete_entry("RUN", id)
assert(data.pad_resolve("RUN", "rt", "x") == nil and data.uses("RUN", id) == 0)

-- A slot of its own lines (macros.json written by hand).
local own = data.pad_get_raw("RUN", "rt", "x")
assert(own == nil)

-- A button press: the macro's lines run in order.
local pad = require("src.pad")
local one = data.save_entry("RUN", nil, { name = "Ignis", action = { kind = "ja", name = "Ignis", target = "me" },
  lines = { "/p Ignis up" } })
data.pad_assign("RUN", "lt", "b", one)
pad.fire("lt", "b", true)
assert(SENT[1] == '/ja "Ignis" <me>' and SENT[2] == "/p Ignis up", tostring(SENT[1]))
SENT = {}
pad.fire("rt", "y", true)
assert(#SENT == 0, "an empty slot runs nothing")

-- A group: a button press opens its list; the d-pad moves the cursor and Accept runs the row (the one picked last
-- under the cursor first).
local grp = data.save_entry("RUN", nil, { name = "Runes", group = {
  { name = "Ignis", action = { kind = "ja", name = "Ignis", target = "me" } },
  { name = "Tenebrae", action = { kind = "ja", name = "Tenebrae", target = "me" } } } })
data.pad_assign("RUN", "rt", "up", grp)
local chooser = require("src.chooser")
SENT = {}
pad.fire("rt", "up", true)
assert(chooser.is_open() and #SENT == 0, "the list opens, nothing runs yet")
chooser.step(1)
chooser.step(1)   -- wraps back to the first row
chooser.step(-1)  -- and up to the last
chooser.accept()
assert(not chooser.is_open() and SENT[1] == '/ja "Tenebrae" <me>', tostring(SENT[1]))
assert(data.last_member(data.macro_of("RUN", grp)) == 2)
SENT = {}
pad.fire("rt", "up", true)
chooser.accept()   -- the one picked last is under the cursor first
assert(SENT[1] == '/ja "Tenebrae" <me>', tostring(SENT[1]))
SENT = {}
pad.fire("rt", "up", true)
chooser.close()
assert(not chooser.is_open() and #SENT == 0)

-- The mode: the bars by default, switched and parsed.
local mode = require("src.mode")
assert(mode.get() == "hotbars" and not mode.is_pad())
assert(mode.parse("Pad") == "gamepad" and mode.parse("keyboard") == "hotbars" and mode.parse("nope") == nil)
mode.set("gamepad")
assert(mode.is_pad())
assert(mode.toggle() == "hotbars" and not mode.is_pad())
assert(mode.toggle() == "gamepad")
-- Changing the Mode setting hands the choice back to it (the default: the hotbars).
mode.use_setting()
assert(mode.get() == "hotbars")
mode.set("gamepad")

-- In gamepad mode the bars' keys and window stand down.
local bar = require("src.bar")
bar.rebuild()
assert(not ui.is_open("bars"))


-- The crossbars' window: nothing shows while Hotbars is off, and rebuilding or the recast tick raise nothing.
pad.rebuild()
pad.recasts()
pad.tick()
assert(not ui.is_open("pads"))

-- The bumpers' and stick clicks' slots hold macros as the others do, per trigger side.
data.init({ read = function() return nil end, write = function() end, decode = json.decode, encode = json.encode })
local bid = data.save_entry("RUN", nil, { name = "Ignis", action = { kind = "ja", name = "Ignis", target = "me" },
  lines = { "/p Ignis up" } })
for _, b in ipairs({ "lb", "rb", "l3", "r3" }) do
  data.pad_assign("RUN", "lt", b, bid)
  assert(data.pad_resolve("RUN", "lt", b).ref == bid)
  assert(data.pad_resolve("RUN", "rt", b) == nil)
end
SENT = {}
pad.fire("lt", "l3", true)
assert(#SENT == 2 and SENT[2] == "/p Ignis up", #SENT)

-- Slots saved while the sides were the bumpers ("lb", "rb") are the triggers' again.
data.init({ read = function() return '{"RUN":{"pad":{"lb":{"up":{"name":"Old","lines":["/echo old"]}}}}}' end,
  write = function() end, decode = json.decode, encode = json.encode })
local old = data.pad_resolve("RUN", "lt", "up")
assert(old and old.name == "Old")
assert(data.pad_resolve("RUN", "lb", "up") == nil)

-- Both triggers held: a third set, apart from the other two.
data.init({ read = function() return nil end, write = function() end, decode = json.decode, encode = json.encode })
local lid = data.save_entry("RUN", nil, { name = "Ignis", action = { kind = "ja", name = "Ignis", target = "me" },
  lines = { "/p both" } })
data.pad_assign("RUN", "lr", "a", lid)
assert(data.pad_resolve("RUN", "lr", "a").ref == lid)
assert(data.pad_resolve("RUN", "lt", "a") == nil and data.pad_resolve("RUN", "rt", "a") == nil)
SENT = {}
pad.fire("lr", "a", true)
assert(SENT[2] == "/p both", tostring(SENT[2]))
