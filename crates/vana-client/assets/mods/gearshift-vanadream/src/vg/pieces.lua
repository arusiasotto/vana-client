-- Inventory rows as scorable pieces (wear rules, augments).

local server = require("src.build.server")
local vdata = require("src.vg.data")

local M = {}

-- Mezzotint (Delve, Geas Fete) augments as the server applies them (ApplyMezzotint): three slots of client index and
-- value; the value is the number shown less one, an _II index adds 256, and an index the server has no stat for does
-- nothing. { mod name, added to the value, multiplier, the pet's }.
local MEZZOTINT = {
  [2] = { "HP" }, [3] = { "HP", 256 }, [4] = { "MP" }, [5] = { "MP", 256 }, [8] = { "ATT" }, [9] = { "ATT", 256 },
  [10] = { "RATT" }, [11] = { "RATT", 256 }, [12] = { "ACC" }, [13] = { "ACC", 256 }, [14] = { "RACC" },
  [15] = { "RACC", 256 }, [16] = { "DEF" }, [17] = { "DEF", 256 }, [18] = { "EVA" }, [19] = { "EVA", 256 },
  [20] = { "MATT" }, [21] = { "MATT", 256 }, [22] = { "MDEF" }, [23] = { "MDEF", 256 }, [24] = { "MACC" },
  [25] = { "MACC", 256 }, [26] = { "MEVA" }, [27] = { "MEVA", 256 }, [28] = { "DMG_RATING" },
  [29] = { "DMG_RATING", 256 },
  [128] = { "MATT", 0, 1, true }, [129] = { "MACC", 0, 1, true }, [130] = { "ATT", 0, 1, true },
  [131] = { "ACC", 0, 1, true },
  [185] = { "STORETP" }, [186] = { "DOUBLE_ATTACK" }, [187] = { "SNAPSHOT" },
  [188] = { "DMGPHYS", 0, -100 }, [189] = { "DMGMAGIC", 0, -100 },
  [191] = { "STR" }, [192] = { "DEX" }, [193] = { "VIT" }, [194] = { "AGI" }, [195] = { "INT" }, [196] = { "MND" },
  [197] = { "CHR" },
}

local function mezzotint(extra)
  local mods, pet = {}, {}
  for i = 0, 2 do
    local index = extra:byte(7 + i * 2) or 0
    local value = (extra:byte(8 + i * 2) or 0) + 1
    local m = MEZZOTINT[index]
    local id = m and vdata.ModId(m[1]) or nil
    if id and index ~= 0 then
      local v = (value + (m[2] or 0)) * (m[3] or 1)
      if m[4] then
        pet[0] = pet[0] or {}
        pet[0][id] = (pet[0][id] or 0) + v
      else
        mods[id] = (mods[id] or 0) + v
      end
    end
  end
  return { mods = mods, pet = pet }
end

-- What an item's augments add on this server, by mod id: { mods = {[id] = v}, pet = {[type] = {[id] = v}} }, or nil.
-- The plain (Oseem style) and Magian augments and the mezzotint ones are what the server applies; Odyssey and other
-- bundled augments are stored but not applied by it, so they count for nothing here too.
function M.augment_mods(extdata)
  if type(extdata) ~= "string" or #extdata < 12 then return nil end
  local kind, flag = extdata:byte(1), extdata:byte(2)
  if kind ~= 2 and kind ~= 3 then return nil end
  if kind == 2 and flag & 0x20 ~= 0 then return mezzotint(extdata) end
  if flag & 0x20 ~= 0 or flag == 131 or flag & 0x08 ~= 0 or flag & 0x80 ~= 0 then return nil end
  local count = (flag & 0x40 ~= 0) and 4 or 5
  local table_ = vdata.Augments()
  local mods, pet = {}, {}
  for i = 1, count do
    -- a 16-bit little-endian word each: the augment's id in its low 11 bits, its value's step in the top 5
    local lo, hi = extdata:byte(2 * i + 1), extdata:byte(2 * i + 2)
    if not lo or not hi then break end
    local word = lo | (hi << 8)
    local id, level = word & 0x7ff, word >> 11
    for _, a in ipairs(table_[id] or {}) do
      -- the server's own sum: (value > 0 and value + level or value - level) * max(multiplier, 1)
      local v = ((a.v > 0) and (a.v + level) or (a.v - level)) * math.max(a.m, 1)
      if a.pet ~= nil then
        pet[a.pet] = pet[a.pet] or {}
        pet[a.pet][a.mod] = (pet[a.pet][a.mod] or 0) + v
      else
        mods[a.mod] = (mods[a.mod] or 0) + v
      end
    end
  end
  return { mods = mods, pet = pet }
end

-- The piece for one owned entry ({id, name, key, extdata, ...} from the builder's scan), or nil.
function M.of(o)
  if o.piece ~= nil then return o.piece or nil end
  local s = server.item(o.id)
  if not s then
    o.piece = false
    return nil
  end
  local rec = require("src.build.pick").item(o.id)
  o.piece = { Id = o.id, Name = o.name, Key = o.key, Server = s, Races = rec and rec.races or 0, Equippable = true,
    Aug = M.augment_mods(o.extdata), Owned = o }
  return o.piece
end

-- Can the player or trust wear this piece in this slot (1 to 16, Main to Back) at this job and level? withSub: the
-- support job's gear counts too (Vanadreams lets you and your trusts wear it, at the main job's level).
function M.can_wear(piece, slot, who, withSub)
  local s = piece.Server
  if s.slots & vdata.SlotBit[slot] == 0 then return false end
  if s.jobs & (1 << who.Job) == 0
    and (not withSub or (who.Sub or 0) == 0 or s.jobs & (1 << who.Sub) == 0) then
    return false
  end
  if s.level > who.Level then return false end
  local races = piece.Races or 0
  if races ~= 0 and (who.Race or 0) > 0 and races & (1 << who.Race) == 0 then return false end
  return true
end

return M
