-- Your own sets, built by vanagear's engine: each of the builder's sets is a roles.lua mode (the job file's tweaks and
-- the band of your level laid over it, the caps lowered by what your traits and gifts already give), scored over every
-- piece you carry by src/vg/score.lua. A set with no mode here (an ability's, the odd job set) keeps the builder's own
-- way of picking.
--
-- As in vanagear, weapons and ammo are never chosen by scoring: only hand picks and /vg weapon fill those slots.

local vplan = require("src.vg.plan")
local vdata = require("src.vg.data")
local score = require("src.vg.score")
local pieces_of = require("src.vg.pieces")

local M = {}

-- The builder's set -> the roles.lua mode its pieces are scored by.
M.MODE = {
  Idle = "Idle", Idle_Regen = "Idle_Regen", Idle_Refresh = "Idle_Refresh", Resting = "Resting", Movement = "Movement",
  Dt = "Dt", PDT = "Dt_Physical", MDT = "Dt_Magic", PetDT = "PetDT", Doomed = "Doomed", TH = "TH",
  TP = "Tp_Default", TP_MNK = "Tp_Default", TP_Hybrid = "Tp_Hybrid", TP_Acc = "Tp_Acc",
  TP_Pet = "PetTP", TP_Pet_DT = "PetDT", TP_Pet_Acc = "PetAcc", Automaton = "PetTP",
  Idle_Pet = "PetIdle", Idle_Avatar = "PetIdle", Idle_Luopan = "PetIdle",
  WS = "Ws_Default", RangedWS = "Ws_Default",
  Precast = "Precast", Precast_Cure = "Cure_Precast", Precast_Song = "Song_Precast",
  Cure = "Cure", Healing = "Cure", NaSpells = "Cursna",
  Nuke = "Nuke", Nuke_MB = "Burst", MagicAcc = "Macc",
  Enfeebling_MND = "Enfeebling", Enfeebling_INT = "Enfeebling",
  Enhancing = "Enhancing", Stoneskin = "Stoneskin", Phalanx = "Phalanx", RegenSpell = "Regen", RefreshSpell = "Refresh",
  Dark = "Dark", DrainAspir = "Drain", Divine = "Divine",
  Ninjutsu_Nuke = "Ninjutsu", Ninjutsu_Debuff = "NinjutsuDebuff", Utsusemi = "Utsusemi",
  Songs_Buff = "Song", Songs_Debuff = "SongDebuff",
  BluPhys = "BluePhysical", BluMag = "BlueMagical", BluDebuff = "BlueDebuff", BluBuff = "BlueBuff", BluHeal = "WhiteWind",
  Geo = "Geomancy",
  Preshot = "Preshot", Midshot = "Midshot", QuickDraw = "QuickDraw", Roll = "PhantomRoll",
  Enmity = "Enmity", Charm = "Charm", Reward = "Reward", BP_Delay = "BPDelay", BloodPact = "BPWard", Breath = "Breath",
}

local STANDING = { Idle = true, Idle_Regen = true, Idle_Refresh = true, Resting = true, Movement = true }

-- The game, through one table (tests replace it).
M.H = {
  zone = function()
    local ok, info = pcall(function() return game.info() end)
    return ok and info and info.zone or 0
  end,
  ability = function(id) return res.ability(id) end,
}

-- What the engine needs to know of you: ctx from the builder (job, job_id, sub_id, race, level, owned) and the party.
local function who_of(ctx)
  local p = ctx.player or {}
  return { Job = ctx.job_id, JobName = ctx.job, Level = ctx.level, Sub = ctx.sub_id or 0, SubLevel = p.sub_level or 0,
    Race = ctx.race or 0, JobPoints = 0, Zone = M.H.zone() }
end

-- The mode of a set, or nil when the engine has none for it. ctx.dual: a weapon in the off hand.
function M.mode(name, ctx)
  local job = vplan.Job(ctx.job)
  local tweaks = vplan.BandTweaks(job, ctx.level or 99)
  local band = vplan.Band(job, ctx.level or 99)
  local mode
  local ws_id = name:match("^WS:(%d+)$")
  if ws_id then
    local ws = vdata.Weaponskills()[tonumber(ws_id)]
    if not ws or next(ws.wsc) == nil then return nil end
    local a = M.H.ability(tonumber(ws_id))
    local display = a and a.name or ws.key
    mode = vplan.WsMode(ws, display)
    -- what the wiki weaponskill pages add, then the job file's Weaponskills and the band's, stat by stat
    local wiki = require("src.vg.wsguide")[display]
    for k, v in pairs(wiki or {}) do mode.Stats[k] = v end
    for _, from in ipairs({ job.Weaponskills, band and band.Weaponskills }) do
      local extra = from and from[display]
      if extra then
        for _, part in ipairs({ "Stats", "Caps" }) do
          if extra[part] then
            mode[part] = mode[part] or {}
            for k, v in pairs(extra[part]) do mode[part][k] = v end
          end
        end
      end
    end
    mode.Drawn = true
  else
    local base = M.MODE[name]
    if not base then return nil end
    mode = vplan.Mode(base, tweaks)
    if not mode.Stats then return nil end
    mode.Name = name
    -- an enfeeble reads one of MND and INT against the target's: the set for the other stat's casters
    if name == "Enfeebling_MND" or name == "Enfeebling_INT" then
      local stat, other = "MND", "INT"
      if name == "Enfeebling_INT" then stat, other = other, stat end
      mode.Stats[stat] = math.max(mode.Stats[stat] or 0, mode.Stats[other] or 0, 0.6) + 0.4
      mode.Stats[other] = nil
    end
    if base:sub(1, 3) == "Tp_" then
      if ctx.dual then
        mode.Stats.DUAL_WIELD = mode.Stats.DUAL_WIELD or 1.2
        mode.Caps = mode.Caps or {}
        mode.Caps.DUAL_WIELD = mode.Caps.DUAL_WIELD or 35
      else
        mode.Stats.DUAL_WIELD = nil   -- under a shield or a two-hander it is worth nothing
      end
    end
    if base:sub(1, 3) == "Tp_" then mode.Drawn = true elseif STANDING[name] then mode.Drawn = false end
  end
  vplan.LowerCaps(mode, vplan.Bonus(who_of(ctx)))
  return mode
end

function M.has(name, ctx)
  if name:match("^WS:") then
    local ws = vdata.Weaponskills()[tonumber(name:match("%d+"))]
    return ws ~= nil and next(ws.wsc) ~= nil
  end
  return M.MODE[name] ~= nil
end

-- Builds one set from the pieces in ctx.owned. Returns the builder's result shape: {slots = {[0..15] = {pick = ...}},
-- score}, or nil when the engine has no mode for the set.
function M.build(name, ctx)
  local mode = M.mode(name, ctx)
  if not mode then return nil end
  local pick = require("src.build.pick")
  local who = who_of(ctx)
  local pieces = {}
  for _, o in ipairs(ctx.owned) do
    local piece = pieces_of.of(o)
    if piece then pieces[#pieces + 1] = piece end
  end
  -- Never the weapons and ammo (slots 1 to 4), nor a slot the player locked.
  local slots = {}
  for slot = 5, 16 do
    if not (ctx.locked and ctx.locked[slot - 1]) then slots[#slots + 1] = slot end
  end
  local set, _, total = score.Build(score.Compile(mode), pieces, who, slots, { 0 }, true)
  local out = { slots = {}, score = total, engine = true, mode = mode }
  for slot = 0, 15 do
    local piece = set[slot + 1]
    if piece then
      local o = piece.Owned
      out.slots[slot] = { how = "engine", pick = { id = piece.Id, key = piece.Key, rec = pick.item(piece.Id),
        s = pick.stats_of(piece.Id, o and o.augments), owned = o } }
    else
      out.slots[slot] = {}
    end
  end
  return out
end

-- What one piece is worth in a slot of a set (0 to 15) by the engine's weights: its own stats, before caps and set
-- bonuses. nil when the engine has no mode for the set.
local rated = {}
function M.rate(name, ctx, o, slot)
  local key = table.concat({ name, ctx.job or "", ctx.level or 0, ctx.sub_id or 0, ctx.dual and 1 or 0 }, "|")
  local compiled = rated[key]
  if compiled == nil then
    local mode = M.mode(name, ctx)
    compiled = mode and score.Compile(mode) or false
    if compiled then compiled.Who = who_of(ctx) end
    rated = { [key] = compiled }   -- one set at a time: the cache is dropped when another is asked for
  end
  if not compiled then return nil end
  local piece = pieces_of.of(o)
  if not piece then return 0 end
  local rate = 0
  for k, v in pairs(score.Vector(piece, slot + 1, compiled, { 0 })) do rate = rate + (compiled.w[k] or 0) * v end
  return rate
end

return M
