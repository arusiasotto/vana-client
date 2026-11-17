-- What the Vanadreams server says about an item. The server's own tables (data/items.lua, from vanagear) are what it
-- enforces and what it adds up, so they beat the client's item text: its level, jobs, slots and weapon figures
-- override the record the game gives, and its mods become the stats gear is scored on. An item the tables do not
-- know keeps the client's record and the stats read from its description.

local M = {}

-- The data, read on first use (tests replace M.H).
M.H = {
  items = function() return require("data.items") end,
  mods = function() return require("data.mods") end,
  blocks = function() return require("data.slotblocks") end,
}

-- Server mod name -> the stat key gear is scored on (src/build/stats.lua names them). Mods not here are kept as
-- "mod_<name>"; nothing weighs them unless a set says so.
local KEY = {
  DEF = "def", HP = "hp", HPP = "hpp", MP = "mp", MPP = "mpp",
  STR = "str", DEX = "dex", VIT = "vit", AGI = "agi", INT = "int", MND = "mnd", CHR = "chr",
  FIRE_MEVA = "res_fire", ICE_MEVA = "res_ice", WIND_MEVA = "res_wind", EARTH_MEVA = "res_earth",
  THUNDER_MEVA = "res_thunder", WATER_MEVA = "res_water", LIGHT_MEVA = "res_light", DARK_MEVA = "res_dark",
  ATT = "att", RATT = "ratt", ACC = "acc", RACC = "racc", ENMITY = "enmity", MATT = "mab", MDEF = "mdb",
  MACC = "macc", MEVA = "meva", WSACC = "wsacc", ATTP = "attp", EVA = "eva", MPHEAL = "hmp", HPHEAL = "hhp",
  STORETP = "stp", MOVE_SPEED_STACKABLE = "move", MOVE_SPEED_GEAR_BONUS = "move",
  -- Skills
  HTH = "sk_h2h", DAGGER = "sk_dagger", SWORD = "sk_sword", GSWORD = "sk_gsword", AXE = "sk_axe", GAXE = "sk_gaxe",
  SCYTHE = "sk_scythe", POLEARM = "sk_polearm", KATANA = "sk_katana", GKATANA = "sk_gkatana", CLUB = "sk_club",
  STAFF = "sk_staff", ARCHERY = "sk_archery", MARKSMAN = "sk_marks", THROW = "sk_throw", GUARD = "sk_guard",
  EVASION = "sk_evasion", SHIELD = "sk_shield", PARRY = "sk_parry",
  DIVINE = "divine", HEALING = "healing", ENHANCE = "enhancing", ENFEEBLE = "enfeebling", ELEM = "elemental",
  DARK = "dark", SUMMONING = "summoning", NINJUTSU = "ninjutsu", SINGING = "singing", STRING = "string",
  WIND = "wind", BLUE = "blue", GEOMANCY_SKILL = "geomancy", HANDBELL_SKILL = "handbell",
  -- Offence
  CRITHITRATE = "crit", CRIT_DMG_INCREASE = "critdmg", MARTIAL_ARTS = "ma", SKILLCHAINDMG = "scb",
  DUAL_WIELD = "dw", DOUBLE_ATTACK = "da", TRIPLE_ATTACK = "ta", QUAD_ATTACK = "qa", SUBTLE_BLOW = "sb",
  SUBTLE_BLOW_II = "sb2", COUNTER = "counter", KICK_ATTACK_RATE = "kick", ZANSHIN = "zanshin", TP_BONUS = "tpb",
  REGAIN = "regain", HASTE_GEAR = "haste", DAMAGE_LIMITP = "pdl", DOUBLE_ATTACK_DMG = "dadmg",
  TRIPLE_ATTACK_DMG = "tadmg", COUNTER_DAMAGE = "counterdmg", CONSERVE_TP = "ctp", FENCER_CRITHITRATE = "fencer",
  ALL_WSDMG_ALL_HITS = "wsd", ALL_WSDMG_FIRST_HIT = "wsd1", ANY_FTP_BONUS = "ftp",
  OCCULT_ACUMEN = "occult", SHIELD_BASH = "shieldbash", WEAPON_BASH = "weaponbash", STEP_ACCURACY = "stepacc",
  -- Defence
  DMG = "dt", DMGPHYS = "pdt", DMGPHYS_II = "pdt2", DMGMAGIC = "mdt", DMGMAGIC_II = "mdt2", DMGBREATH = "bdt",
  REFRESH = "refresh", REGEN = "regen", SHIELDBLOCKRATE = "block", SHIELD_DEF_BONUS = "shielddef",
  SPELLINTERRUPT = "sird", TACTICAL_PARRY = "tparry", STATUSRES = "resstatus", ENHANCES_REFRESH = "refreshpot",
  CURE_POTENCY_RCVD = "curercv",
  -- Magic
  MAGIC_DAMAGE = "mdmg", FASTCAST = "fc", UFASTCAST = "fc", QUICK_MAGIC = "quickcast", CURE_POTENCY = "cure",
  CURE_POTENCY_II = "cure2", CURE_CAST_TIME = "curect", CONSERVE_MP = "cmp", ENH_MAGIC_DURATION = "enhdur",
  ENF_MAG_POTENCY = "enfeffect", ENH_DRAIN_ASPIR = "drain", MAGIC_BURST_BONUS_CAPPED = "mbb",
  MAGIC_BURST_BONUS_UNCAPPED = "mbb2", MAGIC_CRITHITRATE = "mcrit", MAGIC_CRIT_DMG_INCREASE = "mcritdmg",
  REGEN_DURATION = "regendur", SUBLIMATION_BONUS = "sublimation", ENHANCES_CURSNA = "cursna",
  NIN_NUKE_BONUS_GEAR = "nindmg", INDI_DURATION = "indidur", GEOMANCY_BONUS = "geomancy_pot",
  -- Jobs
  TREASURE_HUNTER = "th", SNAPSHOT = "snapshot", RAPID_SHOT = "rapid", RECYCLE = "recycle", STEAL = "steal",
  DESPOIL = "despoil", TAME = "tame", CHARM_CHANCE = "charm", QUICK_DRAW_DMG = "qd", DOUBLE_SHOT_RATE = "doubleshot",
  TRIPLE_SHOT_RATE = "tripleshot", BARRAGE_COUNT = "barrage", BP_DAMAGE = "bpdmg", BP_DELAY = "bpdelay",
  BP_DELAY_II = "bpdelay2", PERPETUATION_REDUCTION = "perp", BLOOD_BOON = "bloodboon", WALTZ_POTENCY = "waltz",
  SAMBA_DURATION = "sambadur", JIG_DURATION = "jigdur", PHANTOM_DURATION = "rolldur", MEDITATE_DURATION = "meditate",
  -- Songs
  MINNE_EFFECT = "song_minne", MINUET_EFFECT = "song_minuet", PAEON_EFFECT = "song_paeon",
  REQUIEM_EFFECT = "song_requiem", THRENODY_EFFECT = "song_threnody", MADRIGAL_EFFECT = "song_madrigal",
  MAMBO_EFFECT = "song_mambo", LULLABY_EFFECT = "song_lullaby", ETUDE_EFFECT = "song_etude",
  BALLAD_EFFECT = "song_ballad", MARCH_EFFECT = "song_march", CAROL_EFFECT = "song_carol",
  MAZURKA_EFFECT = "song_mazurka", ELEGY_EFFECT = "song_elegy", PRELUDE_EFFECT = "song_prelude",
  HYMNUS_EFFECT = "song_hymnus", VIRELAI_EFFECT = "song_virelai", SCHERZO_EFFECT = "song_scherzo",
  ALL_SONGS_EFFECT = "allsongs", SONG_DURATION_BONUS = "songdur", SONG_SPELLCASTING_TIME = "songct",
  SONG_RECAST_DELAY = "songrecast",
  -- Killer effects
  VERMIN_KILLER = "killer", BIRD_KILLER = "killer", AMORPH_KILLER = "killer", LIZARD_KILLER = "killer",
  AQUAN_KILLER = "killer", PLANTOID_KILLER = "killer", BEAST_KILLER = "killer", UNDEAD_KILLER = "killer",
  ARCANA_KILLER = "killer", DRAGON_KILLER = "killer", DEMON_KILLER = "killer", EMPTY_KILLER = "killer",
  HUMANOID_KILLER = "killer", LUMINIAN_KILLER = "killer", LUMINION_KILLER = "killer",
}

-- The server keeps haste and damage taken in hundredths of a percent; players (and the weights) count whole points.
local UNIT = { haste = 100, dt = 100, pdt = 100, pdt2 = 100, mdt = 100, mdt2 = 100, bdt = 100 }

-- The pet each server pet type is: 0 is every pet, 1 an avatar, 2 a wyvern, 3 to 7 the automaton's frames, 8 a luopan.
local PET = { [0] = "pet", "avatar", "wyvern", "automaton", "automaton", "automaton", "automaton", "automaton", "luopan" }

local items, mod_key, blocks
local function load()
  if items then return end
  items = M.H.items() or {}
  blocks = M.H.blocks() or {}
  mod_key = {}
  for id, name in pairs(M.H.mods() or {}) do
    -- A mod no stat above names is kept as "mod_<name>", for a set that weighs it (job abilities, pets, spell effects).
    mod_key[id] = KEY[name] or ("mod_" .. name:lower())
  end
end

local function numbers(text)
  local out = {}
  for k, v in text:gmatch("(%d+)=(%-?%d+)") do out[tonumber(k)] = tonumber(v) end
  return out
end

-- An item's server record, decoded once: {level, jobs, slots, skill, delay, damage, rslot, mods, pets}, or nil.
-- jobs counts job n as bit n (the client's way; the server's is bit n-1).
local records = {}
function M.item(id)
  local r = records[id]
  if r ~= nil then return r or nil end
  load()
  local line = items[id]
  if not line then
    records[id] = false
    return nil
  end
  local level, jobs, slot, skill, delay, dmg, mods, pets = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
  r = {
    level = tonumber(level), jobs = (tonumber(jobs) or 0) << 1, slots = tonumber(slot) or 0,
    skill = tonumber(skill), delay = tonumber(delay), damage = tonumber(dmg),
    rslot = blocks[id] or 0, mods = numbers(mods), pets = {},
  }
  for pet, k, v in pets:gmatch("(%d+)%.(%d+)=(%-?%d+)") do
    pet = tonumber(pet)
    r.pets[pet] = r.pets[pet] or {}
    r.pets[pet][tonumber(k)] = tonumber(v)
  end
  records[id] = r
  return r
end

-- The client's record with the server's level, jobs, slots and weapon figures put over it (a copy).
function M.apply(id, rec)
  local s = M.item(id)
  if not s or not rec then return rec end
  local r = {}
  for k, v in pairs(rec) do r[k] = v end
  r.level, r.jobs, r.slots = s.level, s.jobs, s.slots
  r.superior_level = 0
  if s.skill then r.skill = s.skill end
  if s.delay then r.delay = s.delay end
  if s.damage then r.damage = s.damage end
  r.rslot = s.rslot
  r.server = true
  return r
end

-- The stats the server gives an item, in the shape stats.parse returns ({stats, pet, cond, unknown}); nil when the
-- server's tables do not know it.
local cache = {}
function M.stats(id)
  local c = cache[id]
  if c ~= nil then return c or nil end
  local s = M.item(id)
  if not s then
    cache[id] = false
    return nil
  end
  local r = { stats = {}, pet = {}, cond = {}, unknown = {} }
  local function add(into, mods)
    for mod, v in pairs(mods) do
      local key = mod_key[mod]
      if key then into[key] = (into[key] or 0) + v / (UNIT[key] or 1) end
    end
  end
  add(r.stats, s.mods)
  if s.damage then r.stats.dmg = s.damage end
  if s.delay then r.stats.delay = s.delay end
  for pet, mods in pairs(s.pets) do
    local kind = PET[pet] or "pet"
    r.pet[kind] = r.pet[kind] or {}
    add(r.pet[kind], mods)
  end
  cache[id] = r
  return r
end

-- Whether the item takes other slots as well as its own, so nothing can be worn there with it (a suit, a coat).
function M.blocks_slots(id)
  local s = M.item(id)
  return s ~= nil and s.rslot ~= 0
end

return M
