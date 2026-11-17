-- Which sets to build for the job the player is on, and what each one values: vanagear's vg/plan.lua as it is.
-- A mode is roles.lua's weights and caps with the job file's tweaks laid over it, and the band of the job's level.
-- Trusts and the player's own sets both use this.

local roles = require("src.vg.roles")
local vdata = require("src.vg.data")

local M = {}

-- The game, through one table (tests replace it).
M.H = {
  ability = function(id) return res.ability(id) end,
  spell = function(id) return res.spell(id) end,
  spells = function() return game.spells() end,
  skills = function()
    local ok, s = pcall(function() return game.skills() end)
    return ok and s or { combat = {} }
  end,
  job_points = function()
    local ok, t = pcall(function() return game.job_points() end)
    return ok and t or {}
  end,
}

local function copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = copy(v) end
  return c
end
M.copy = copy

-- roles.lua's mode with the job file's tweaks laid over it, stat by stat.
function M.Mode(name, tweaks)
  local m = copy(roles.Modes[name]) or {}
  m.Name = name
  local t = tweaks and tweaks[name]
  if t then
    for _, part in ipairs({ "Stats", "Caps", "Pet", "PetCaps" }) do
      if t[part] then
        m[part] = m[part] or {}
        for k, v in pairs(t[part]) do m[part][k] = v end
      end
    end
  end
  return m
end

local jobs = {}
-- A job's file (data/jobs/WHM.lua), or the plain fighter's when it has none.
function M.Job(abbr)
  if abbr == nil then return { Fighter = true } end
  if jobs[abbr] == nil then
    local ok, job = pcall(require, "data.jobs." .. tostring(abbr))
    jobs[abbr] = ok and type(job) == "table" and job or { Fighter = true }
  end
  return jobs[abbr]
end

-- A job file's Bands are level ranges, each with its own Tweaks and Modes: { To = 30, Tweaks = {...} } in rising
-- order. The band the level falls in is laid over the job's all-level Tweaks.
function M.Band(job, level)
  for _, b in ipairs(job.Bands or {}) do
    if level <= (b.To or 99) then return b end
  end
  return nil
end

function M.BandTweaks(job, level)
  local band = M.Band(job, level)
  if not band or not band.Tweaks then return job.Tweaks or {} end
  local out = copy(job.Tweaks or {})
  for mode_name, t in pairs(band.Tweaks) do
    out[mode_name] = out[mode_name] or {}
    for _, part in ipairs({ "Stats", "Caps", "Pet", "PetCaps" }) do
      if t[part] then
        out[mode_name][part] = out[mode_name][part] or {}
        for k, v in pairs(t[part]) do out[mode_name][part][k] = v end
      end
    end
  end
  return out
end

-- One weaponskill's mode, from the stats the server's script reads (data/weaponskills.lua).
function M.WsMode(ws, display)
  local m = { Name = display, Stats = {} }
  local s = m.Stats
  for stat, v in pairs(ws.wsc) do s[stat] = v * 2 end
  if ws.kind == "magical" then
    s.MATT = 2; s.MACC = 0.6; s.MAGIC_DAMAGE = 1.2
    s.ALL_WSDMG_FIRST_HIT = 3; s.TP_BONUS = 0.008
  elseif ws.kind == "ranged" then
    s.RATT = 0.6; s.RACC = 0.5; s.ALL_WSDMG_FIRST_HIT = 2.5; s.TP_BONUS = 0.008
    s.AGI = (s.AGI or 0) + 0.2
  else
    s.ATT = 0.5; s.ACC = 0.35; s.TP_BONUS = 0.008; s.CRIT_DMG_INCREASE = 0.3
    if ws.hits > 1 then
      s.ALL_WSDMG_ALL_HITS = 3; s.ALL_WSDMG_FIRST_HIT = 1.5; s.ANY_FTP_BONUS = 0.1
      s.DOUBLE_ATTACK = 0.8; s.TRIPLE_ATTACK = 1.2
    else
      s.ALL_WSDMG_ALL_HITS = 3; s.ALL_WSDMG_FIRST_HIT = 2.5; s.ANY_FTP_BONUS = 0.04
    end
  end
  return m
end

-- The set name a weaponskill's (or spell's, or ability's) set goes by: its name with spaces and punctuation taken out
-- (Savage Blade -> SavageBlade), as the starter profiles name them.
function M.WsSetName(name)
  return (tostring(name or ""):gsub("[^%w]", ""))
end

-- What the player already has toward a stat without gear.
function M.Bonus(who)
  local out = {}
  local function add_traits(job_id, level)
    local best = {}
    for _, t in ipairs(vdata.Traits()[job_id] or {}) do
      if t.level <= level then
        local key = t.trait .. ":" .. t.mod
        if not best[key] or t.rank > best[key].rank then best[key] = t end
      end
    end
    for _, t in pairs(best) do
      local name = vdata.ModName(t.mod)
      if name then out[name] = (out[name] or 0) + t.v end
    end
  end
  if (who.Job or 0) > 0 then add_traits(who.Job, who.Level or 99) end
  if (who.Sub or 0) > 0 then add_traits(who.Sub, who.SubLevel or 0) end
  for _, g in ipairs(vdata.Gifts()[who.Job or 0] or {}) do
    if g.jp <= (who.JobPoints or 0) then
      local name = vdata.ModName(g.mod)
      if name then out[name] = (out[name] or 0) + g.v end
    end
  end
  return out
end

-- A cap gear works toward, less what the job already has toward it.
function M.LowerCaps(m, bonus)
  if not m.Caps then return end
  local score = require("src.vg.score")
  local caps = {}
  for stat, cap in pairs(m.Caps) do
    local have = bonus[stat] or 0
    for _, part in ipairs(score.Virtual[stat] or {}) do have = have + (bonus[part] or 0) end
    have = have / (score.Unit[stat] or 1)
    if cap < 0 then caps[stat] = math.min(0, cap + have) else caps[stat] = math.max(0, cap - have) end
  end
  m.Caps = caps
end

-- Job effects with a set of their own, by the job and level that give them.
M.EffectSets = {
  { set = "Saboteur", job = "RDM", level = 83, mainOnly = true },
  { set = "SneakAttack", job = "THF", level = 15 },
  { set = "TrickAttack", job = "THF", level = 30 },
  { set = "SneakTrickAttack", job = "THF", level = 30 },
  { set = "Cure_Solace", job = "WHM", level = 40 },
  { set = "Souleater", job = "DRK", level = 30 },
  { set = "LastResort", job = "DRK", level = 15 },
  { set = "Enmity", job = "PLD", level = 1, mainOnly = true },
  { set = "SpellInterrupt", job = "PLD", level = 1, mainOnly = true },
  { set = "Tank_Main", job = "PLD", level = 1, mainOnly = true },
  { set = "Tank_MEVA", job = "PLD", level = 1, mainOnly = true },
  { set = "Covering", job = "PLD", level = 35, mainOnly = true },
  { set = "Enmity", job = "RUN", level = 1, mainOnly = true },
  { set = "SpellInterrupt", job = "RUN", level = 1, mainOnly = true },
  { set = "Tank_Main", job = "RUN", level = 1, mainOnly = true },
  { set = "Tank_MEVA", job = "RUN", level = 1, mainOnly = true },
  { set = "FootworkTP", job = "MNK", level = 65, mainOnly = true },
  { set = "Futae", job = "NIN", level = 77, mainOnly = true },
  { set = "Breath", job = "DRG", level = 1, mainOnly = true },
  { set = "ChainAffinity", job = "BLU", level = 40 },
  { set = "TripleShot", job = "COR", level = 87, mainOnly = true },
  { set = "PetRangedWS", job = "PUP", level = 1, mainOnly = true },
  { set = "Sublimation", job = "SCH", level = 35 },
  { set = "Stratagem", job = "SCH", level = 55, mainOnly = true },
  { set = "BurstAffinity", job = "BLU", level = 25 },
  { set = "PetIdle", job = "SMN", level = 1, mainOnly = true },
  { set = "Summoning", job = "SMN", level = 1, mainOnly = true },
  { set = "ThirdEye", job = "SAM", level = 15 },
  { set = "Hasso", job = "SAM", level = 25 },
  { set = "Seigan", job = "SAM", level = 35 },
  { set = "Sengikori", job = "SAM", level = 77, mainOnly = true },
  { set = "Barrage", job = "RNG", level = 30 },
  { set = "Velocity", job = "RNG", level = 45 },
  { set = "Velocity_Preshot", job = "RNG", level = 45 },
  { set = "TrueShot", job = "RNG", level = 78, mainOnly = true },
  { set = "DoubleShot", job = "RNG", level = 79, mainOnly = true },
}

-- The skill of a worn piece (Main / Sub / Range): the server's skill id, or nil.
local function worn_skill(equipment, slot_name)
  local e = equipment and equipment[slot_name]
  if not e or not e.Id then return nil end
  local s = require("src.build.server").item(e.Id)
  return s and s.skill or nil
end

-- Skill ids as the client's spell records have them (DAT; Gearshift's sets.lua uses the same).
local SKILL_IDS = {
  [32] = "Divine Magic", [33] = "Healing Magic", [34] = "Enhancing Magic", [35] = "Enfeebling Magic",
  [36] = "Elemental Magic", [37] = "Dark Magic", [39] = "Ninjutsu", [40] = "Singing", [41] = "Singing",
  [42] = "Singing", [43] = "Blue Magic", [44] = "Geomancy",
}

-- The spells the player has learned and can cast now: { Name, Skill (LuAshitacast's name) }.
function M.Spells(who)
  local known = {}
  for _, id in ipairs(M.H.spells() or {}) do known[id] = true end
  local list, seen = {}, {}
  for id = 1, 1023 do
    if known[id] then
      local s = M.H.spell(id)
      if s and SKILL_IDS[s.skill] then
        local levels = s.levels or {}
        local need_main = levels[who.Job] or -1
        local need_sub = (who.Sub or 0) > 0 and (levels[who.Sub] or -1) or -1
        local ok = (need_main > 0 and need_main <= (who.Level or 0))
          or (need_sub > 0 and need_sub <= (who.SubLevel or 0))
        local name = s.name
        if ok and name and name ~= "" and not seen[name] then
          seen[name] = true
          list[#list + 1] = { Name = name, Skill = SKILL_IDS[s.skill] }
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.Name < b.Name end)
  return list
end

local NIN_DEBUFF = { kurayami = true, hojo = true, jubaku = true, dokumori = true, aisha = true, yurin = true,
  sayonara = true }
local NIN_NUKE = { katon = true, hyoton = true, huton = true, doton = true, raiton = true, suiton = true }

-- The mode a spell's own set is built from, or nil for a spell that gets no set of its own.
function M.SpellMode(skill, name)
  local first = string.lower(string.match(name, "^[%a]+") or "")
  if skill == "Ninjutsu" then
    if first == "utsusemi" then return "Utsusemi" end
    if NIN_NUKE[first] then return "Ninjutsu" end
    if NIN_DEBUFF[first] then return "NinjutsuDebuff" end
    return "NinjutsuBuff"
  elseif skill == "Healing Magic" then
    if first == "cure" or first == "cura" or first == "curaga" then return "Cure" end
    if name == "Cursna" then return "Cursna" end
    return nil
  elseif skill == "Enhancing Magic" then
    if first == "stoneskin" then return "Stoneskin" end
    if first == "phalanx" then return "Phalanx" end
    if first == "regen" then return "Regen" end
    if first == "refresh" then return "Refresh" end
    return "Enhancing"
  elseif skill == "Enfeebling Magic" then
    return "Enfeebling"
  elseif skill == "Elemental Magic" then
    return "Nuke"
  elseif skill == "Dark Magic" then
    if first == "drain" or first == "aspir" then return "Drain" end
    return "Dark"
  elseif skill == "Divine Magic" then
    return "Divine"
  elseif skill == "Singing" then
    local lowered = string.lower(name)
    for _, word in ipairs({ "elegy", "lullaby", "requiem", "threnody", "finale", "nocturne", "virelai",
      "magic finale", "pining nocturne" }) do
      if string.find(lowered, word, 1, true) then return "SongDebuff" end
    end
    return "Song"
  elseif skill == "Blue Magic" then
    local L = require("src.vg.lists")
    if name == "White Wind" then return "WhiteWind" end
    if L.BlueCure[name] then return "Cure" end
    if L.BlueSkill[name] then return "BlueSkill" end
    if L.BlueDebuff[name] then return "BlueDebuff" end
    if L.BlueBuff[name] then return "BlueBuff" end
    if L.BlueEnmity[name] then return "Enmity" end
    return L.BluePhysical[name] and "BluePhysical" or "BlueMagical"
  elseif skill == "Geomancy" then
    if string.find(name, "^Indi%-") then return "Indi" end
    return "Geomancy"
  end
  return nil
end

--[[
  Returns a list of { Name, Mode, Slots, Ability?, Weaponskill?, Spell?, SameAs? } and the reasons slots were held,
  for the job, subjob and weapons the player has right now. Weapons and ammo are never scored (swapping them resets
  TP); opts.Locked also excludes explicitly locked armour slots.
  who: { Job, JobName, Level, Sub, SubName, SubLevel, Race, JobPoints, Zone }
  equipment: { Main = { Id }, Sub = { Id }, Range = { Id } } (what is worn now)
  opts: { Locked = { [slot 1..16] = true } }
]]
function M.For(who, equipment, opts)
  opts = opts or {}
  local job = M.Job(who.JobName)
  local tweaks = M.BandTweaks(job, who.Level or 99)
  local band = M.Band(job, who.Level or 99)
  local names, seen = {}, {}
  local function add(list)
    for _, n in ipairs(list) do
      if not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
  end

  add(roles.Always)
  if job.Support then
    add(roles.Support)
  elseif job.Fighter ~= false then
    add(roles.Fighter)
  end

  local skills, have_skill = {}, {}
  for _, s in ipairs(job.Skills or {}) do
    if not have_skill[s] then have_skill[s] = true; skills[#skills + 1] = s end
  end
  for _, s in ipairs(roles.SubSkills[who.SubName] or {}) do
    if not have_skill[s] then have_skill[s] = true; skills[#skills + 1] = s end
  end
  if #skills > 0 then
    add(roles.Caster)
    for _, s in ipairs(skills) do add(roles.SkillSets[s] or {}) end
  end

  local range_skill = worn_skill(equipment, "Range")
  local shooting = range_skill == 25 or range_skill == 26 or range_skill == 27
  if job.Shooter or shooting then add(roles.Shooter) end
  if job.Pet then add(roles.Pet) end
  add(job.Modes or {})
  if band then add(band.Modes or {}) end

  -- Player weapons and ammo are never chosen by scoring: swapping them resets TP. Only the player or an explicit
  -- profile/action set chooses those slots.
  local slots, held = {}, {}
  for i = 1, 16 do
    local keep = false
    if i <= 4 then
      keep = true
    elseif opts.Locked and opts.Locked[i] then
      keep = true
      held[i] = "locked with /vg lock"
    end
    if not keep then slots[#slots + 1] = i end
  end

  local sub_skill = worn_skill(equipment, "Sub")
  local dual_wield = sub_skill ~= nil and sub_skill >= 1 and sub_skill <= 12

  local out = {}
  for _, n in ipairs(names) do
    local m = M.Mode(n, tweaks)
    if string.sub(n, 1, 3) == "Tp_" then
      if dual_wield then
        m.Stats.DUAL_WIELD = m.Stats.DUAL_WIELD or 1.2
        m.Caps = m.Caps or {}
        m.Caps.DUAL_WIELD = m.Caps.DUAL_WIELD or 35
      else
        m.Stats.DUAL_WIELD = nil
      end
    end
    out[#out + 1] = { Name = n, Mode = m, Slots = slots }
  end

  -- Job ability sets: what the server reads when the ability goes off, under the ability's own name with spaces taken
  -- out (Blood Rage -> BloodRage).
  local by_name = {}
  local sub_level = who.SubLevel or 0
  for id, a in pairs(vdata.Abilities()) do
    local mine = ((a.job == who.Job) and (a.level <= who.Level))
      or ((a.job == who.Sub) and (a.level <= sub_level))
    if mine then
      local rec = M.H.ability(id + 0x200)
      local display = (rec and rec.name) or a.key
      local m = { Name = M.WsSetName(display), Stats = {} }
      for k, v in pairs(job.AbilityBase or {}) do m.Stats[k] = v end
      for _, mod in ipairs(a.mods) do
        if mod ~= "ONE_HOUR_RECAST" and vdata.ModId(mod) then m.Stats[mod] = 1 end
      end
      by_name[display] = m
    end
  end
  for ability, extra in pairs(job.Abilities or {}) do
    local m = by_name[ability] or { Name = M.WsSetName(ability), Stats = {} }
    for _, part in ipairs({ "Stats", "Caps", "Pet", "PetCaps" }) do
      if extra[part] then
        m[part] = m[part] or {}
        for k, v in pairs(extra[part]) do m[part][k] = v end
      end
    end
    by_name[ability] = m
  end
  for ability, m in pairs(by_name) do
    if next(m.Stats) ~= nil or m.Pet ~= nil then
      out[#out + 1] = { Name = m.Name, Mode = m, Slots = slots, Ability = ability }
    end
  end

  -- A set for every weaponskill the weapons in hand can use at the skill the player has.
  local skills_in_hand = {}
  local main = worn_skill(equipment, "Main")
  if main then skills_in_hand[main] = true end
  if range_skill then skills_in_hand[range_skill] = true end
  local combat = (M.H.skills().combat) or {}
  local function skill_of(skill_id)
    local s = combat[skill_id]
    return (s and s.level) or 999
  end
  for id, ws in pairs(vdata.Weaponskills()) do
    if skills_in_hand[ws.skill] and next(ws.wsc) ~= nil and ws.level <= skill_of(ws.skill) then
      local rec = M.H.ability(id)
      local display = (rec and rec.name) or ws.key
      local m = M.WsMode(ws, display)
      local wiki = require("src.vg.wsguide")[display]
      if wiki then
        for k, v in pairs(wiki) do m.Stats[k] = v end
      end
      for _, from in ipairs({ job.Weaponskills, band and band.Weaponskills }) do
        local extra = from and from[display]
        if extra then
          for _, part in ipairs({ "Stats", "Caps" }) do
            if extra[part] then
              m[part] = m[part] or {}
              for k, v in pairs(extra[part]) do m[part][k] = v end
            end
          end
        end
      end
      out[#out + 1] = { Name = M.WsSetName(display), Mode = m, Slots = slots, Weaponskill = display }
    end
  end

  -- A set for every spell the player knows and can cast at this level.
  local have = {}
  for _, o in ipairs(out) do have[string.lower(o.Name)] = true end
  local ok_spells, known = pcall(M.Spells, who)
  for _, s in ipairs(ok_spells and known or {}) do
    local set_name = M.WsSetName(s.Name)
    local kind = M.SpellMode(s.Skill, s.Name)
    if roles.Modes[set_name] ~= nil then kind = set_name end
    if kind ~= nil and not have[string.lower(set_name)] then
      have[string.lower(set_name)] = true
      local m = M.Mode(kind, tweaks)
      m.Name = set_name
      local enf = vdata.Enfeeble(s.Name)
      if enf and m.Stats then
        local other = (enf.stat == "MND") and "INT" or "MND"
        m.Stats[enf.stat] = math.max(m.Stats[enf.stat] or 0, m.Stats[other] or 0, 0.6) + 0.4
        m.Stats[other] = nil
      end
      out[#out + 1] = { Name = set_name, Mode = m, Slots = slots, Spell = s.Name,
        SameAs = (kind ~= set_name) and kind or nil }
    end
  end

  -- Sets for the job effects the templates lay over a phase while they are up.
  local function add_effect(name, only_slots)
    if not have[string.lower(name)] then
      have[string.lower(name)] = true
      out[#out + 1] = { Name = name, Mode = M.Mode(name, tweaks), Slots = only_slots or slots }
    end
  end
  local elemental_ws = false
  for _, o in ipairs(out) do
    if o.Weaponskill and vdata.WsElement(o.Weaponskill) then elemental_ws = true end
  end
  if (ok_spells and known and #known > 0) or elemental_ws then
    for _, n in ipairs({ "Obi", "Obi_Fire", "Obi_Ice", "Obi_Wind", "Obi_Earth", "Obi_Thunder", "Obi_Water",
      "Obi_Light", "Obi_Dark" }) do
      add_effect(n, { 11 })
    end
  end
  for _, e in ipairs(M.EffectSets) do
    local main_ok = who.JobName == e.job and who.Level >= e.level
    local sub_ok = who.SubName == e.job and (who.SubLevel or 0) >= e.level
    if main_ok or (sub_ok and not e.mainOnly) then add_effect(e.set) end
  end
  for _, s in ipairs(ok_spells and known or {}) do
    if s.Skill == "Enhancing Magic" and (string.find(s.Name, "^En%a+$") or string.find(s.Name, "^En%a+ II$")) then
      add_effect("Enspell")
    end
    if string.find(s.Name, "helix") then add_effect("Helix") end
    if s.Skill == "Dark Magic" and string.find(s.Name, "^Absorb") then add_effect("Absorb") end
  end

  -- Sets vanagear does not score but the templates still wear (empty until filled by hand).
  for _, name in ipairs({ "Sleeping", "Reraise", "Town", "HolyWater", "Ws_Acc", "Tp_Proc", "Ws_Proc" }) do
    if not have[string.lower(name)] then
      have[string.lower(name)] = true
      out[#out + 1] = { Name = name, Mode = { Name = name, Stats = {} }, Slots = slots, Empty = true }
    end
  end

  local bonus = M.Bonus(who)
  for _, o in ipairs(out) do M.LowerCaps(o.Mode, bonus) end

  local standing = { Idle = true, Idle_Regen = true, Idle_Refresh = true, Resting = true, Movement = true }
  for _, o in ipairs(out) do
    if string.sub(o.Name, 1, 3) == "Tp_" or string.sub(o.Name, 1, 3) == "Ws_" or o.Weaponskill then
      o.Mode.Drawn = true
    elseif standing[o.Name] then
      o.Mode.Drawn = false
    end
  end

  return out, held
end

return M
