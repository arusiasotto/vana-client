-- Hotbars: a sticky change never loses a macro when sticky.json or the world's file cannot be written. Every sticky
-- write saves both files; when either fails, memory, both files and the groups' last picks are as they were.

local files, deny, saves = {}, {}, 0
storage = { character = { hb_last = {} }, save = function() saves = saves + 1 end }
local data = require("src.data")
data.init({ read = function(f) return files[f] end, decode = json.decode, encode = json.encode,
  write = function(f, t)
    if deny[f] then error("denied") end
    files[f] = t
  end })

local function one_entry(job, id)
  local lib = data.library(job)
  return #lib == 1 and lib[1].id == id
end

local warp = data.save_entry("RDM", nil, { name = "Warp", lines = { '/item "Warp Ring" <me>' } })
data.assign("RDM", nil, 1, 9, warp)
storage.character.hb_last["RDM:" .. warp] = 2

-- sticky.json cannot be written: nothing moves, in memory or after a reload, and the caller is told.
deny["sticky.json"] = true
local s, why = data.set_sticky("RDM", warp, true)
assert(s == nil and why and not data.is_sticky(warp))
assert(one_entry("RDM", warp) and data.get_raw("RDM", nil, 1, 9).ref == warp)
assert(storage.character.hb_last["RDM:" .. warp] == 2)
data.load()
assert(data.resolve("RDM", nil, 1, 9).name == "Warp" and data.get_raw("RDM", nil, 1, 9).ref == warp)

-- An edit saved with Sticky ticked while sticky.json cannot be written: the edit stays in the job's file.
local id
id, why = data.save_entry("RDM", warp, { name = "Warp 2", lines = { '/item "Warp Ring" <me>' } }, true)
assert(id == warp and why)
data.load()
assert(data.get_entry("RDM", warp).name == "Warp 2" and one_entry("RDM", warp))

-- A new sticky macro is not made, and no id is given out.
id, why = data.save_entry("RDM", nil, { name = "Choco", lines = { "/mount Chocobo" } }, true)
assert(id == nil and why and one_entry("RDM", warp))
deny["sticky.json"] = nil

-- sticky.json saves but the world's file does not: sticky.json is written back, nothing moves.
deny[data.file()] = true
s, why = data.set_sticky("RDM", warp, true)
assert(s == nil and why and one_entry("RDM", warp) and data.get_raw("RDM", nil, 1, 9).ref == warp)
assert(not files["sticky.json"]:find("Warp"))
deny[data.file()] = nil
data.load()
assert(one_entry("RDM", warp) and data.get_raw("RDM", nil, 1, 9).ref == warp)

-- Made sticky; the last pick follows it.
s = data.set_sticky("RDM", warp, true)
assert(data.is_sticky(s) and data.get_raw("RDM", nil, 1, 9).ref == s)
assert(storage.character.hb_last["RDM:" .. s] == 2 and storage.character.hb_last["RDM:" .. warp] == nil)

-- Unsticking while the world's file cannot be written: memory is as it was at once (one entry, the slot names the
-- sticky one, the last pick keyed to it), and so is everything after a reload.
deny[data.file()] = true
local back
back, why = data.set_sticky("RDM", s, false)
assert(back == nil and why)
assert(one_entry("RDM", s) and data.get_raw("RDM", nil, 1, 9).ref == s)
assert(storage.character.hb_last["RDM:" .. s] == 2)
deny[data.file()] = nil
data.load()
assert(one_entry("RDM", s) and data.get_raw("RDM", nil, 1, 9).ref == s and data.resolve("RDM", nil, 1, 9).name)

-- A copy of a sticky macro, or its delete, while sticky.json cannot be written: neither happens.
deny["sticky.json"] = true
id, why = data.save_entry("RDM", nil, { name = "Warp copy", lines = { "/echo" } }, true)
assert(id == nil and why and one_entry("RDM", s))
local ok
ok, why = data.delete_entry("RDM", s)
assert(not ok and why and one_entry("RDM", s) and data.get_raw("RDM", nil, 1, 9).ref == s)
deny["sticky.json"] = nil
data.load()
assert(one_entry("RDM", s) and data.get_raw("RDM", nil, 1, 9).ref == s)

-- Each file is written once a change.
local writes = {}
data.init({ read = function(f) return files[f] end, decode = json.decode, encode = json.encode,
  write = function(f, t)
    writes[f] = (writes[f] or 0) + 1
    files[f] = t
  end })
back = data.set_sticky("RDM", s, false)
assert(back and writes["sticky.json"] == 1 and writes[data.file()] == 1)
