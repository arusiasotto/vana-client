-- Gearshift's window: the sets in categories (two dropdowns), Rare / Ex marks on what is worth getting, each piece's
-- cell naming its item for the tooltip (held pieces with their bag and index), Match as value against the best in
-- slot, and a set turned off is never worn.

local EAR1, EAR2, NECK, THF, ALL = 1 << 11, 1 << 12, 1 << 9, 1 << 6, 0x1fe
local RARE, EX = 0x8000, 0x4000
local ITEMS = {
  [5001] = { name = "Worn Earring", slots = EAR1 | EAR2, jobs = THF, races = ALL, level = 1, flags = 0,
    description = "\"Store TP\"+1" },
  [5002] = { name = "Both Earring", slots = EAR1 | EAR2, jobs = THF, races = ALL, level = 99, flags = RARE | EX,
    description = "\"Store TP\"+9" },
  [5003] = { name = "Ex Earring", slots = EAR1 | EAR2, jobs = THF, races = ALL, level = 99, flags = EX,
    description = "\"Store TP\"+8" },
  [5004] = { name = "Rare Collar", slots = NECK, jobs = THF, races = ALL, level = 99, flags = RARE,
    description = "\"Store TP\"+7" },
  [5005] = { name = "Plain Collar", slots = NECK, jobs = THF, races = ALL, level = 99, flags = 0,
    description = "\"Store TP\"+1" },
}
STATUS, JOB = 0, 6
local BAGS = { [8] = { { bag = 8, slot = 3, id = 5001, count = 1, locked = 0 },
  { bag = 8, slot = 4, id = 5005, count = 1, locked = 0 } } }
game = {
  player = function() return { name = "Tester", id = 100, index = 1, main_job = JOB, main_level = 99, sub_job = 0,
    status = STATUS, pos = { x = 0, y = 0, z = 0 } } end,
  entity = function() return { race = 1 } end,
  entities = function() return {} end,
  equipment = function() return {} end,
  items = function(bag) return BAGS[bag] or {} end,
  time = function() return { weekday = 0 } end, weather = function() return 0 end, buffs = function() return {} end,
}
res = setmetatable({
  item = function(id) return ITEMS[id] end,
  job = function(id) return ({ "WAR", "MNK", "WHM", "BLM", "RDM", "THF" })[id] end,
}, { __index = function() return function() return nil end end })
storage = { character = { builder = { jobs = {}, modes = {} } } }
settings = { get = function(k) if k == "cap" then return "Auto" end return true end }
packets.inject_out = function() end

-- Every set of every job has a category.
local sets = require("src.build.sets")
for job, list in pairs(sets.JOBS) do
  for _, s in ipairs(list) do
    assert(sets.group(s, sets.SETS[s]) ~= "Other", job .. "'s set " .. s .. " has no category")
  end
end

local run = require("src.build.run")
run.RANGES = { { 5001, 5006 } }
run.refresh()
for _ = 1, 200 do run.frame() end
assert(run.state.built.TP, "no TP set built for THF")

-- The window as the client gets it (the real ui.window checks the fields too).
local spec
local real = ui.window
ui.window = function(id, s)
  spec = s
  return real(id, s)
end
local win = require("src.build.window")
win.draw()
local function elem(id)
  for _, e in ipairs(spec.elements) do
    if e.id == id then return e end
  end
end
local group, set = elem("group"), elem("set")
assert(group and group.items[group.at] == "Combat", "THF does not open on its combat sets: " .. tostring(group and group.items[group.at]))
local names = table.concat(group.items, ",")
assert(names:find("Weapon Skills", 1, true) and names:find("Idle and Defence", 1, true), "categories: " .. names)
for _, l in ipairs(set.items) do
  assert(l:find("^TP") or l == "Treasure Hunter", "a set outside Combat listed under it: " .. l)
end

local rows = elem("slots").rows
local neck, lear, rear = rows[10], rows[12], rows[13]
local function tags(r) return table.concat(r.tags[5] or {}, "/") end
assert(neck[5] == "Rare Collar (99)" and tags(neck) == "Rare", "neck worth: " .. neck[5] .. " " .. tags(neck))
local ears = lear[5] .. " " .. tags(lear) .. " | " .. rear[5] .. " " .. tags(rear)
assert(ears:find("Both Earring (99) Rare/Ex", 1, true) and ears:find("Ex Earring (99) Ex", 1, true), "ear worth: " .. ears)
assert(neck.items[5] == 5004 and neck.items[4], "the neck's worth / best in slot cells name no item")
local held = neck.items[2]
assert(type(held) == "table" and held.id == 5005 and held.bag == 8 and held.index == 4,
  "the worn collar's cell does not name where it is held")
assert(neck.items[1] == held, "the slot cell (with the icon) does not name the worn piece")
-- Match is the worn piece's value against the best in slot's ("Store TP"+1 of +7), not how alike their stats are.
assert(neck[4] == "Rare Collar" and neck[3] == "14%", "neck match: " .. tostring(neck[3]) .. " against " .. neck[4])

-- Another category shows its own sets, and each category keeps the set picked in it.
local function index_of(id, label)
  for i, l in ipairs(elem(id).items) do
    if l == label then return i end
  end
  error(id .. " has no " .. label)
end
local handler
local real_on = ui.on
ui.on = function(id, f)
  handler = f
  return real_on(id, f)
end
win.install()
local function send(id, label) handler("gsbuilder", { kind = "set", id = id, index = index_of(id, label) }) end
local function shown() local e = elem("set") return e.items[e.at] end
send("set", "TP - accuracy")
send("group", "Idle and Defence")
assert(shown() == "Idle", "Idle and Defence opens on " .. shown())
send("group", "Combat")
assert(shown() == "TP - accuracy", "Combat forgot its set: " .. shown())

-- A set turned off is marked in the list and never worn; on again, it is.
local sent = 0
packets.inject_out = function() sent = sent + 1 end
STATUS = 1
run.set_active(true)
send("set", "TP")
handler("gsbuilder", { kind = "set", id = "set_on", index = 2 })
assert(run.set_off("THF", "TP"), "Wear This Set Off did not turn the TP set off")
assert(elem("set_on").at == 2 and elem("set").items[elem("set").at] == "TP (off)", "the off set is not marked")
for _ = 1, 5 do run.tick() end
assert(sent == 0, "a set turned off was worn (" .. sent .. " packets)")
handler("gsbuilder", { kind = "set", id = "set_on", index = 1 })
assert(not run.set_off("THF", "TP"), "Wear This Set On did not turn it back on")
run.tick()
assert(sent > 0, "the set turned back on is not worn")

-- Turning an unrelated set off and on again does not wear the status set again (over gear changed by hand).
local core = require("src.core")
local wears, resolve = 0, core.resolve
core.resolve = function(...)
  wears = wears + 1
  return resolve(...)
end
run.set_set_off("THF", "TP - accuracy", true)
run.set_set_off("THF", "TP - accuracy", false)
for _ = 1, 3 do run.tick() end
assert(wears == 0, "an unrelated set's switch wore the status set again (" .. wears .. " times)")
core.resolve = resolve

-- After a job change to a shorter category list, the dropdown shows the set the switch turns off.
handler("gsbuilder", { kind = "set", id = "set", index = #elem("set").items })
JOB = 5
run.refresh()
win.draw()
handler("gsbuilder", { kind = "set", id = "set_on", index = 2 })
local e = elem("set")
assert(e.items[e.at] and e.items[e.at]:find("(off)", 1, true),
  "Wear This Set Off changed a set other than the one shown: " .. tostring(e.items[e.at]) .. " at " .. e.at)
