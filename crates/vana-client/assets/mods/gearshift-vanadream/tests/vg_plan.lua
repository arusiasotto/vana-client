-- vanagear's plan.For: the sets a job gets by its skills, subjob, weapons in hand and known spells.

local vplan = require("src.vg.plan")
local roles = require("src.vg.roles")

-- A WHM/BLM with a club, no spells known yet (the spell list is empty until game.spells is set).
vplan.H.spells = function() return {} end
vplan.H.skills = function() return { combat = { [11] = { level = 200 } } } end
vplan.H.ability = function(id)
  if id == 42 then return { name = "Hexa Strike" } end   -- a club WS id in the data, if present
  return { name = "Ability" .. id }
end
vplan.H.spell = function() return nil end

local who = { Job = 3, JobName = "WHM", Level = 75, Sub = 4, SubName = "BLM", SubLevel = 37, Race = 1,
  JobPoints = 0, Zone = 0 }
-- A club in Main (skill 11): weaponskills of that skill that the player can use.
local equipment = { Main = { Id = 17451 } }   -- an id; worn_skill reads the server's skill from data/items

local list, held = vplan.For(who, equipment, {})
assert(held, "held slots returned")
local names = {}
for _, o in ipairs(list) do names[o.Name] = o end

-- Support job (WHM): Idle, Dt, Movement; not Tp_Default (Fighter).
assert(names.Idle and names.Dt and names.Movement and names.Doomed and names.TH and names.HolyWater)
assert(not names.Tp_Default, "a support job has no fighting set of its own")
-- Caster from WHM skills and BLM sub: Precast, Cure, Nuke, ...
assert(names.Precast and names.Interim and names.Cure and names.Nuke and names.Enhancing and names.Enfeebling)
assert(names.Dark, "BLM sub brings Dark")
assert(names.Divine, "WHM brings Divine")
-- Weapons and ammo are held out of every set (TP reset).
for _, o in ipairs(list) do
  for _, slot in ipairs(o.Slots) do assert(slot > 4, o.Name .. " scored a weapon slot") end
end

-- A fighter (WAR) gets Tp_ and Ws_Default.
local war = { Job = 1, JobName = "WAR", Level = 75, Sub = 0, SubName = "", SubLevel = 0, Race = 1, JobPoints = 0,
  Zone = 0 }
local war_list = vplan.For(war, { Main = { Id = 16558 } }, {})   -- a sword if the server knows it
local war_names = {}
for _, o in ipairs(war_list) do war_names[o.Name] = true end
assert(war_names.Tp_Default and war_names.Ws_Default and war_names.Idle)

-- SpellMode sorts ninjutsu and blue magic.
assert(vplan.SpellMode("Ninjutsu", "Utsusemi: Ichi") == "Utsusemi")
assert(vplan.SpellMode("Ninjutsu", "Katon: Ichi") == "Ninjutsu")
assert(vplan.SpellMode("Ninjutsu", "Hojo: Ichi") == "NinjutsuDebuff")
assert(vplan.SpellMode("Blue Magic", "White Wind") == "WhiteWind")
assert(vplan.SpellMode("Blue Magic", "Foot Kick") == "BluePhysical")
assert(vplan.SpellMode("Healing Magic", "Cure IV") == "Cure")
assert(vplan.SpellMode("Elemental Magic", "Fire") == "Nuke")

-- Known spells add their own sets.
vplan.H.spells = function() return { 1, 144 } end   -- Cure, Fire (ids as the client has them; may not match)
-- Use fake spell records.
vplan.H.spell = function(id)
  if id == 1 then return { name = "Cure", skill = 33, levels = { [3] = 1 } } end
  if id == 144 then return { name = "Fire", skill = 36, levels = { [4] = 1, [3] = 50 } } end
end
local with = vplan.For(who, equipment, {})
local with_names = {}
for _, o in ipairs(with) do with_names[o.Name] = o end
-- Cure the kind set already exists; Fire gets its own set named Fire.
assert(with_names.Fire and with_names.Fire.Spell == "Fire", "a known spell gets its own set")
assert(with_names.Obi and with_names.Obi_Fire, "obi sets for a caster")
assert(with_names.Cure_Solace, "WHM Afflatus Solace set")

-- A locked slot is held out.
local locked = vplan.For(who, equipment, { Locked = { [5] = true } })   -- Head
for _, o in ipairs(locked) do
  for _, slot in ipairs(o.Slots) do assert(slot ~= 5, "locked head scored") end
end

-- Dual wield: a weapon in Sub weighs DUAL_WIELD in Tp_ sets.
local dw_who = { Job = 1, JobName = "WAR", Level = 75, Sub = 13, SubName = "NIN", SubLevel = 37, Race = 1,
  JobPoints = 0, Zone = 0 }
-- Find any dagger and any sword in the server's items for Main/Sub.
local server = require("src.build.server")
local sword, dagger
for id in pairs(require("data.items")) do
  local s = server.item(id)
  if s and s.skill == 3 and s.level <= 75 then sword = id end
  if s and s.skill == 2 and s.level <= 75 then dagger = id end
  if sword and dagger then break end
end
assert(sword and dagger, "a sword and a dagger in the data")
local dw = vplan.For(dw_who, { Main = { Id = sword }, Sub = { Id = dagger } }, {})
local tp
for _, o in ipairs(dw) do if o.Name == "Tp_Default" then tp = o end end
assert(tp and (tp.Mode.Stats.DUAL_WIELD or 0) > 0, "dual wield weighed with a weapon in Sub")
local shield
for id in pairs(require("data.items")) do
  local s = server.item(id)
  if s and s.skill == 0 and (s.slots & 2) ~= 0 and s.level <= 75 then shield = id break end
end
if shield then
  local one = vplan.For(dw_who, { Main = { Id = sword }, Sub = { Id = shield } }, {})
  for _, o in ipairs(one) do
    if o.Name == "Tp_Default" then assert(o.Mode.Stats.DUAL_WIELD == nil, "no dual wield under a shield") end
  end
end

assert(roles.Modes.Idle and roles.Fighter[1] == "Idle")
