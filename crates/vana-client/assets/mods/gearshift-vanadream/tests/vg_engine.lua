-- vanagear's engine over the server's real item tables: what it builds, set bonuses, the augments the server applies.

local server = require("src.build.server")
local score = require("src.vg.score")
local pieces_of = require("src.vg.pieces")
local vplan = require("src.vg.plan")
local vdata = require("src.vg.data")

-- Every item the server knows, as a piece.
local function pool_for(job_id, level)
  local out = {}
  for id in pairs(require("data.items")) do
    local s = server.item(id)
    if s and s.level <= level and (s.jobs & (1 << job_id)) ~= 0 and s.slots ~= 0 then
      out[#out + 1] = { Id = id, Name = "#" .. id, Server = s, Races = 0, Equippable = true }
    end
  end
  table.sort(out, function(a, b) return a.Id < b.Id end)
  return out
end
local slots = {}
for s = 1, 16 do slots[s] = s end
local WHM = 3

-- Modes: roles.lua's with the job's band over it.
local job = vplan.Job("WHM")
assert(job and job.Skills, "the WHM file loads")
local tweaks = vplan.BandTweaks(job, 75)
local cure = vplan.Mode("Cure", tweaks)
assert(cure.Stats and next(cure.Stats), "Cure has weights")

-- A WHM's Cure set is built from real items, one piece per slot, nothing the job cannot wear.
local pool = pool_for(WHM, 75)
assert(#pool > 100, "the pool: " .. #pool)
local who = { Job = WHM, Sub = 0, Level = 75, Race = 0 }
local compiled = score.Compile(cure)
local set, _, total = score.Build(compiled, pool, who, slots, { 0 }, true)
local worn = 0
for slot, piece in pairs(set) do
  worn = worn + 1
  assert(pieces_of.can_wear(piece, slot, who, true), "wearable: " .. piece.Id .. " in " .. slot)
end
assert(worn >= 8 and total > 0, "a set: " .. worn .. " pieces, " .. total)

-- The score never drops when a piece is added: the best set beats the set with its head taken out.
local without = {}
for slot, piece in pairs(set) do without[#without + 1] = piece end
local less = {}
for _, piece in ipairs(pool) do
  if set[5] == nil or piece.Id ~= set[5].Id then less[#less + 1] = piece end
end
local _, _, total_less = score.Build(compiled, less, who, slots, { 0 }, true)
assert(total_less <= total + 1e-9, "removing a piece cannot help: " .. total_less .. " vs " .. total)

-- The support job's gear counts for a trust that has one (and not otherwise).
local sub_only
for _, p in ipairs(pool_for(5, 75)) do
  if (p.Server.jobs & (1 << WHM)) == 0 and p.Server.slots == 16 then sub_only = p break end
end
assert(sub_only, "a RDM head the WHM cannot wear")
assert(not pieces_of.can_wear(sub_only, 5, who, true))
assert(pieces_of.can_wear(sub_only, 5, { Job = WHM, Sub = 5, Level = 75, Race = 0 }, true), "the support job's gear")
assert(not pieces_of.can_wear(sub_only, 5, { Job = WHM, Sub = 5, Level = 75, Race = 0 }, false))

-- The level and the race.
local high
for _, p in ipairs(pool) do if p.Server.level > 60 and p.Server.slots == 16 then high = p break end end
assert(high and not pieces_of.can_wear(high, 5, { Job = WHM, Level = 50, Race = 0 }, false), "level")
assert(not pieces_of.can_wear({ Server = high.Server, Races = 1 << 3 }, 5, { Job = WHM, Level = 99, Race = 2 }, false), "race")

-- Augments the server applies: id 1 is HP+1, with the value's step added. Word = id | (step << 11), little-endian.
local function extdata(flag, words)
  local bytes = { 2, flag }
  for _, w in ipairs(words) do bytes[#bytes + 1] = w & 0xff; bytes[#bytes + 1] = w >> 8 end
  while #bytes < 24 do bytes[#bytes + 1] = 0 end
  return string.char(table.unpack(bytes))
end
local aug = pieces_of.augment_mods(extdata(0x00, { 1 | (3 << 11), 2 }))
assert(aug and aug.mods[2] == (1 + 3) + 33, "HP+4 and HP+33: " .. tostring(aug and aug.mods[2]))
assert(pieces_of.augment_mods(extdata(0x08, { 1 })) == nil, "a bundled augment is not applied")
assert(pieces_of.augment_mods("") == nil and pieces_of.augment_mods(nil) == nil)
-- Mezzotint: index 2 (HP) value 4 shows +5.
local mez = string.char(2, 0x20, 0, 0, 0, 0, 2, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
assert(pieces_of.augment_mods(mez).mods[2] == 5, "mezzotint HP+5")

-- An augmented piece beats the plain one when the augment is on a stat the set weighs: MND (mod 13) augment ids.
local mnd_id
for id, list in pairs(vdata.Augments()) do
  if #list == 1 and list[1].mod == 13 and list[1].v > 0 and not list[1].pet then mnd_id = id break end
end
assert(mnd_id, "an MND augment")
local ring
for _, p in ipairs(pool) do
  if p.Server.slots & 24576 ~= 0 and p.Server.level < 50 then ring = p break end
end
local plain = { Id = ring.Id, Name = "plain", Server = ring.Server, Races = 0, Equippable = true }
local better = { Id = ring.Id, Name = "augmented", Server = ring.Server, Races = 0, Equippable = true,
  Aug = pieces_of.augment_mods(extdata(0x00, { mnd_id | (10 << 11) })) }
local one = score.Build(score.Compile({ Stats = { MND = 1 } }), { plain, better }, who, { 14 }, { 0 }, true)
assert(one[14] and one[14].Name == "augmented", "the augmented piece is the better one")

-- A cap: once the cap is reached the second piece is worth nothing and the slot goes elsewhere.
local capped = score.Compile({ Stats = { MND = 1, INT = 0.5 }, Caps = { MND = 1 } })
local mnd_piece = { Id = 1, Name = "mnd", Server = { slots = 0x7000, jobs = 8, level = 1, mods = { [13] = 5 } }, Equippable = true }
local int_piece = { Id = 2, Name = "int", Server = { slots = 0x7000, jobs = 8, level = 1, mods = { [12] = 2 } }, Equippable = true }
local mnd_two = { Id = 3, Name = "mnd2", Server = { slots = 0x7000, jobs = 8, level = 1, mods = { [13] = 4 } }, Equippable = true }
local pair = score.Build(capped, { mnd_piece, int_piece, mnd_two }, who, { 13, 14 }, { 0 }, true)
assert(pair[13] and pair[14], "both slots filled")
local names = { pair[13].Name, pair[14].Name }
table.sort(names)
assert(names[1] == "int" and names[2] == "mnd", "the cap sends the second slot to INT: " .. table.concat(names, ","))

-- Virtual PDT: damage taken (mod DMG) and physical damage taken share the one cap.
local dt = score.Compile({ Stats = { PDT = -1 }, Caps = { PDT = -50 } })
local a = { Id = 1, Name = "a", Server = { slots = 0x7000, jobs = 8, level = 1, mods = { [160] = -3000 } }, Equippable = true }
local b = { Id = 2, Name = "b", Server = { slots = 0x7000, jobs = 8, level = 1, mods = { [161] = -4000 } }, Equippable = true }
local c = { Id = 3, Name = "c", Server = { slots = 0x7000, jobs = 8, level = 1, mods = { [160] = -2500 } }, Equippable = true }
local _, _, t1 = score.Build(dt, { a, b, c }, who, { 13, 14, 15 }, { 0 }, true)
assert(math.abs(t1 - 50) < 1e-6, "capped at -50%: " .. t1)

-- Weaponskill and ability modes from the server's data.
local ws
for _, w in pairs(vdata.Weaponskills()) do if w.key == "savage_blade" then ws = w end end
local m = vplan.WsMode(ws, "Savage Blade")
assert(m.Stats.STR and m.Stats.ALL_WSDMG_ALL_HITS == 3, "a multi-hit physical weaponskill")
