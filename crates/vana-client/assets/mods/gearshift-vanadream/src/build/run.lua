-- The set builder's engine: the whole item list indexed by slot (a slice a frame), our gear scanned, each set of the
-- job built for our level (one a frame, again when the job, the level or the bags change), and the sets worn around
-- actions as the other front ends wear theirs: precast, the action, midcast; between actions the set for our status.
-- Saved per character (storage.character.builder): only what the player chose by hand (a slot's piece, held through
-- rebuilds) and the toggles; every other pick follows the level.

local core = require("src.core")
local pick = require("src.build.pick")
local sets = require("src.build.sets")
local wslist = require("src.build.ws")
local blu = require("src.build.blu")
local engine = require("src.vg.player")

local M = {}

-- The game, through one table (tests replace it).
M.H = {
  player = function() return game.player() end,
  me = function()
    local p = game.player()
    return p and game.entity(p.id)
  end,
  items = function(bag) return game.items(bag) end,
  item = function(id) return res.item(id) end,
  spell = function(id) return res.spell(id) end,
  ability = function(id) return res.ability(id) end,
  job = function(id) return res.job(id) end,
  time = function() return game.time() end,
  weather = function() return game.weather() end,
  buffs = function() return game.buffs() end,
  -- Our pet is out: an entity marked as ours.
  pet = function()
    for _, e in ipairs(game.entities() or {}) do
      if e.pet then return true end
    end
    return false
  end,
  pet_hpp = function()
    for _, e in ipairs(game.entities() or {}) do
      if e.pet then return e.hpp end
    end
  end,
  -- The name of the zone we are in.
  zone_name = function()
    local info = game.info and game.info()
    local zone = info and info.zone
    local name = zone and res.zone and res.zone(zone)
    return type(name) == "table" and name.name or name
  end,
  storage = function() return storage.character end,
  -- vanagear's engine picks the gear (off: the builder's references).
  engine = function() return settings.get("engine") ~= false end,
  cap_setting = function() return settings.get("cap") end,
  ws_line = function() return settings.get("ws_line") ~= false end,
  -- Gear Swapping and Set Builder on: the sets are built (worn only with the window's switch on too).
  on = function() return settings.get("on") ~= false and settings.get("builder") ~= false end,
}

-- Equipment item ids (armour and weapons).
M.RANGES = { { 0x2800, 0x3FFF }, { 0x4000, 0x59FF }, { 0x5A00, 0x6FFF } }
M.SLICE = 600

local state = {
  index = {}, next_id = nil, range = 1, ready = false,
  job = nil, level = nil, owned = nil, owned_sig = nil,
  at_cap = nil, at_level = nil, need_cands = false,
  -- built: the sets (stale ones kept through a rebuild); fresh: those built since the last rebuild began.
  built = {}, queue = {}, names = {}, fresh = {}, built_job = nil,
}
M.state = state

-- ---- The saved choices ----

local function saved()
  local st = M.H.storage()
  st.builder = st.builder or { jobs = {}, modes = {} }
  return st.builder
end

-- The hand picks of a job's set: {slot name = {name, augments}}.
function M.hand(job, set_name)
  local b = saved()
  b.jobs[job] = b.jobs[job] or {}
  b.jobs[job][set_name] = b.jobs[job][set_name] or {}
  return b.jobs[job][set_name]
end

function M.modes() return saved().modes end

-- The player turned the builder's swapping on (the window's switch), per character.
function M.active() return saved().active == true end
function M.set_active(on) saved().active = on or nil end

-- ---- The level cap the references are for ----

function M.cap()
  local c = M.H.cap_setting()
  if c == "75" or c == 75 then return 75 end
  if c == "99" or c == 99 then return 99 end
  return (state.level or 1) > 75 and 99 or 75
end

-- ---- Our gear ----

local ALL_BAGS = { 0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
local EQUIP = {}
for _, b in ipairs(core.EQUIP_BAGS) do EQUIP[b] = true end

-- Every piece in the equippable bags, and the others' too (to say where a piece is kept).
local function scan()
  local owned, elsewhere, sig = {}, {}, {}
  for _, bag in ipairs(ALL_BAGS) do
    for _, it in ipairs(M.H.items(bag) or {}) do
      local rec = it.id and it.id > 0 and pick.item(it.id)
      if rec and rec.slots and rec.slots ~= 0 then
        core.want_augments(it.extdata, it.id)
        local entry = { id = it.id, name = rec.name, key = bag .. ":" .. it.slot, bag = bag, index = it.slot,
          augments = it.extdata and core.augments[it.extdata] or nil, extdata = it.extdata }
        if EQUIP[bag] then owned[#owned + 1] = entry else elsewhere[#elsewhere + 1] = entry end
        -- The augments themselves, not whether they are decoded yet: an enchantment's timer changes the data when
        -- the item is put on, and must not rebuild every set.
        local aug = entry.augments and #entry.augments > 0 and ("a" .. table.concat(entry.augments, ";")) or ""
        sig[#sig + 1] = entry.key .. "=" .. it.id .. aug
      end
    end
  end
  return owned, elsewhere, table.concat(sig, ",")
end

-- ---- The sets of a job ----

-- The weapon types we hold weapons of (their weapon skills get sets).
local SKILL_NAME = { [1] = "hand_to_hand", [2] = "dagger", [3] = "sword", [4] = "great_sword", [5] = "axe",
  [6] = "great_axe", [7] = "scythe", [8] = "polearm", [9] = "katana", [10] = "great_katana", [11] = "club",
  [12] = "staff", [25] = "archery", [26] = "marksmanship", [27] = "throwing" }

function M.weapon_types()
  local out = {}
  for _, o in ipairs(state.owned or {}) do
    local rec = pick.item(o.id)
    if rec and rec.skill and SKILL_NAME[rec.skill] then out[SKILL_NAME[rec.skill]] = true end
  end
  return out
end

-- A set by name: vanagear's plan entry when the engine is on, else a catalogue set / "WS:<id>".
local ctx
function M.set_def(name)
  if M.H.engine() and state.job then
    local d = engine.def(name, ctx())
    if d then return d end
  end
  local id = name:match("^WS:(%d+)$")
  if id then
    id = tonumber(id)
    local ws = wslist[id]
    if not ws then return nil end
    local a = M.H.ability(id)
    return sets.ws_set(id, ws, a and a.name)
  end
  return sets.SETS[name]
end

-- The job's sets in the window's order: vanagear's plan.For for the job, subjob and weapons you have right now.
function M.job_sets(job)
  if not M.H.engine() then
    -- The Gearshift catalogue when vanagear's engine is off.
    local out, seen = {}, {}
    for _, s in ipairs(sets.JOBS[job] or {}) do out[#out + 1] = s; seen[s] = true end
    local function extra(name)
      if not seen[name] and sets.SETS[name] then seen[name] = true; out[#out + 1] = name end
    end
    if seen.Idle then
      extra("Idle_Regen") extra("Idle_Refresh")
      extra("Dt") extra("Doomed") extra("Sleeping") extra("Reraise") extra("Town")
    end
    if seen.TP_Pet or seen.Idle_Pet then extra("PetDT") end
    if seen.TP_Pet then extra("TP_Pet_DT") extra("TP_Pet_Acc") end
    local modes = M.modes()
    if modes.th then extra("TH") end
    if modes.kite or modes.idle == "speed" then extra("Movement") end
    local types = M.weapon_types()
    for _, id in ipairs(sets.ws_ids(job, wslist)) do
      if types[wslist[id].skill] then out[#out + 1] = "WS:" .. id end
    end
    return out
  end
  if not state.job or state.job ~= job then return {} end
  return engine.names(ctx())
end

-- A weapon in the off hand (dual wield is worth something only with one).
local function dual_wield()
  local w = core.worn()[1]
  local rec = w and w.id and pick.item(w.id)
  return rec ~= nil and rec.skill ~= nil and rec.skill >= 1 and rec.skill <= 12
end

ctx = function()
  local p = M.H.player() or {}
  local me = M.H.me() or {}
  local owns = {}
  for _, o in ipairs(state.owned or {}) do owns[o.id] = true end
  return { job = state.job, job_id = p.main_job, sub_id = p.sub_job, race = me.race, level = state.level, cap = M.cap(),
    owned = state.owned or {}, owns = owns, at_cap = state.at_cap or {}, at_level = state.at_level or {},
    names = state.names, player = p, dual = dual_wield(), locked = M.locks(),
    mage = sets.MAGE_JOBS[state.job], melee_sets = sets.MELEE_SETS, bis = nil }
end

-- Builds one set now (the window's selection may ask before the queue reaches it).
function M.build(name)
  local def = M.set_def(name)
  if not def or not state.ready or not state.at_cap then return nil end
  local c = ctx()
  -- vanagear's engine where it has a mode for the set, else the builder's own way
  local r = M.H.engine() and engine.build(name, c) or nil
  if not r then
    local ok, bis = pcall(require, "src.build.bis")
    if ok and bis then c.bis = bis.lookup(M.cap(), state.job, name) end
    r = pick.build(c, def, name)
  end
  r.at = state.level
  state.built[name] = r
  state.fresh = state.fresh or {}
  state.fresh[name] = true
  return r
end

-- ---- The frame: the index, the scan and the build queue ----

local function index_step()
  if state.ready then return end
  local r = M.RANGES[state.range]
  local from = state.next_id or r[1]
  local to = math.min(from + M.SLICE - 1, r[2])
  local ids = {}
  for id = from, to do ids[#ids + 1] = id end
  pick.index_add(state.index, ids)
  for _, id in ipairs(ids) do
    local rec = pick.item(id)
    if rec and rec.name and rec.name ~= "" and rec.slots and rec.slots ~= 0 then
      state.names[rec.name] = state.names[rec.name] or {}
      table.insert(state.names[rec.name], id)
    end
  end
  if to >= r[2] then
    state.range, state.next_id = state.range + 1, nil
    if state.range > #M.RANGES then state.ready = true end
  else
    state.next_id = to + 1
  end
end

-- Queues every set of the job again. The sets built stay in use until each is built again (a weapon skill right
-- after a loot still has its set); another job's are dropped.
function M.rebuild()
  state.queue, state.fresh = {}, {}
  engine.forget()
  if state.built_job ~= state.job then state.built, state.built_job = {}, state.job end
  if not state.job then return end
  for _, s in ipairs(M.job_sets(state.job)) do state.queue[#state.queue + 1] = s end
end

-- Puts a set first in the queue (the one the window shows, or an action wants).
function M.want_first(name)
  if state.fresh and state.fresh[name] then return end
  for i, s in ipairs(state.queue) do
    if s == name then table.remove(state.queue, i) break end
  end
  table.insert(state.queue, 1, name)
end

-- The job, the level and the bags: a change rebuilds every set (a timer and item_change call it).
function M.refresh()
  if not M.H.on() then return end
  local p = M.H.player()
  if not p or not p.main_job or p.main_job == 0 then return end
  local job = M.H.job(p.main_job)
  local owned, elsewhere, sig = scan()
  state.elsewhere = elsewhere
  local sub = p.sub_job or 0
  if job ~= state.job or p.main_level ~= state.level or sub ~= state.sub then state.need_cands = true end
  local dual = dual_wield()
  if job ~= state.job or p.main_level ~= state.level or sub ~= state.sub or sig ~= state.owned_sig or dual ~= state.dual then
    state.job, state.level, state.sub, state.owned, state.owned_sig, state.dual = job, p.main_level, sub, owned, sig, dual
    M.rebuild()
  end
end

-- One step of the work: a slice of the index; once it is whole, the job's candidates (at the cap and at our level)
-- when the job or the level changed; then one set from the queue. Returns true while there is work left.
function M.step()
  if not M.H.on() then return false end
  if not state.ready then
    index_step()
    return true
  end
  if not state.job then return false end
  if state.need_cands or not state.at_cap then
    state.need_cands = false
    local p = M.H.player() or {}
    local me = M.H.me() or {}
    state.at_cap = pick.candidates(state.index, p.main_job, me.race, M.cap())
    state.at_level = pick.candidates(state.index, p.main_job, me.race, state.level, p.sub_job)
    if state.built_job ~= state.job then state.built, state.built_job = {}, state.job end
    return true
  end
  if #state.queue > 0 then
    M.build(table.remove(state.queue, 1))
    return true
  end
  return false
end
M.frame = M.step

-- The worker: steps the work in the background, yielding when its share of a frame is used.
local SHARE = 0.0015
function M.worker()
  local t0 = clock()
  pick.pace = function()
    if clock() - t0 > SHARE then
      sleep_frames(1)
      t0 = clock()
    end
  end
  while true do
    t0 = clock()
    local more = M.step()
    -- Other work that wants the item index and the pace (the trusts' sets) when the job's own is done.
    if not more and M.extra then more = M.extra() end
    sleep_frames(more and 1 or 10)
  end
end

-- ---- Wearing sets ----

-- A set's pieces: the hand picks first, then the build's (a set not built yet is asked for first).
function M.pieces(name)
  local out = {}
  local r = state.built[name]
  if not (state.fresh and state.fresh[name]) then M.want_first(name) end
  if r then
    for slot, o in pairs(r.slots) do
      if o.pick then
        local rec = pick.item(o.pick.id)
        out[slot] = { name = rec and rec.name, augments = o.pick.owned and o.pick.owned.augments or nil }
      end
    end
  end
  -- /vg weapon: the player's weapon in every set.
  for slot_name, weapon in pairs(saved().weapons or {}) do
    for slot, n in pairs(pick.SLOT_NAMES) do
      if n == slot_name then out[slot] = { name = weapon } end
    end
  end
  for slot_name, h in pairs(M.hand(state.job, name)) do
    for slot, n in pairs(pick.SLOT_NAMES) do
      if n == slot_name then out[slot] = h end
    end
  end
  return out
end

-- The owned piece named in `names` (the first we hold), for the element rules.
local function owned_named(names)
  for _, n in ipairs(names) do
    for _, o in ipairs(state.owned or {}) do
      if o.name == n then return { name = n } end
    end
  end
end

-- The element rules over a casting set's pieces: the element's staff (affinity; up to level 75, mages), the obi when
-- the day or the weather is the element.
local OBI_SETS = { Nuke = true, Nuke_MB = true, NukeACC = true, Burst = true, Cure = true, Drain = true,
  DrainAspir = true, Divine = true, Dark = true, Ninjutsu = true, Ninjutsu_Nuke = true, BlueMagical = true,
  BluMag = true, QuickDraw = true, MagicAcc = true, Macc = true, Enfeebling = true, Enfeebling_MND = true,
  Enfeebling_INT = true }
-- game.time().weekday (0 Firesday .. 7 Darksday) -> the day's element.
local DAY_ELEMENT = { [0] = "fire", "earth", "water", "wind", "ice", "thunder", "light", "dark" }

local function element_gear(pieces, set_name, el)
  if not el or not OBI_SETS[set_name] then return end
  if sets.MAGE_JOBS[state.job] and (state.level or 0) <= 75 then
    local staves = sets.STAVES[el]
    local staff = owned_named({ staves[2], staves[1] })
    if staff then pieces[0] = staff; pieces[1] = nil end
  end
  local t = M.H.time() or {}
  local weather = M.H.weather()
  local day_el = DAY_ELEMENT[t.weekday or -1]
  local w_el = weather and res and res.weather_element and sets.ELEMENT_ID[res.weather_element(weather) or -1]
  if day_el == el or w_el == el then
    if M.H.engine() then
      local named = "Obi_" .. el:sub(1, 1):upper() .. el:sub(2)
      local r = state.built[named] or state.built.Obi
      local waist = r and r.slots[10] and r.slots[10].pick
      if waist then pieces[10] = { name = pick.item(waist.id).name } end
    else
      local obi = owned_named({ sets.OBIS[el], sets.OBI_ALL })
      if obi then pieces[10] = obi end
    end
  end
end

-- A weapon skill's gorget and belt by its skillchain elements (Fotia for any).
local function ws_gear(pieces, ws)
  if not ws or not ws.sc then return end
  local els = {}
  for _, p in ipairs(ws.sc) do
    for _, e in ipairs(sets.SC_ELEMENTS[p] or {}) do els[e] = true end
  end
  local neck, waist = { sets.FOTIA.neck }, { sets.FOTIA.waist }
  for e in pairs(els) do
    neck[#neck + 1] = sets.GORGETS[e]
    waist[#waist + 1] = sets.BELTS[e]
  end
  pieces[9] = owned_named(neck) or pieces[9]
  pieces[10] = owned_named(waist) or pieces[10]
end

-- The pieces as core.resolve wants.
local function wants(pieces)
  local w = {}
  for slot, p in pairs(pieces) do
    if p and p.name then w[slot] = { name = p.name, augments = p.augments } end
  end
  return w
end

-- Ammo stays while a bow, gun or crossbow is worn, or while the ammo is thrown (shuriken): another piece there would
-- break the next shot or throw.
local function keep_ammo()
  local worn = core.worn()
  local range = worn[2] and pick.item(worn[2].id)
  local ammo = worn[3] and pick.item(worn[3].id)
  return (range and (range.skill == 25 or range.skill == 26)) or (ammo and ammo.skill == 27)
end

-- Usable gear the player put on (charges: Warp Ring, Empress Band...) keeps its slot until used or taken off.
local used = {}
local function keep_usable(pieces)
  local worn = core.worn()
  for slot, w in pairs(worn) do
    local rec = pick.item(w.id)
    if rec and (rec.max_charges or 0) > 0 and not used[w.id] and not core.put_by_us(slot, w) and pieces[slot]
      and pieces[slot].name ~= rec.name then
      pieces[slot] = nil
    end
  end
  for id in pairs(used) do
    local on = false
    for _, w in pairs(worn) do on = on or w.id == id end
    if not on then used[id] = nil end
  end
end

-- Returns how many slots it changed.
local function wear(pieces, style)
  if pieces[3] and keep_ammo() then pieces[3] = nil end
  -- A locked slot (/vg lock) is left as it is.
  for slot in pairs(M.locks()) do pieces[slot] = nil end
  keep_usable(pieces)
  local list = core.resolve(wants(pieces), { log_names = false })
  core.send(core.packets(list, style or "auto", 8))
  return #list
end

-- Wears a set now (the window's Wear Now).
function M.wear_set(name)
  wear(M.pieces(name), "set")
end

-- Auto idle: regen below 60% HP and refresh below 70% MP, held until 80% / 90% (not flapping at the edge).
local auto = { regen = false, refresh = false }
local function auto_idle(p)
  local hpp, mpp = p.hpp or 100, p.mpp or 100
  auto.regen = hpp < 60 or (auto.regen and hpp < 80)
  auto.refresh = (p.mp_max or 0) > 0 and (mpp < 70 or (auto.refresh and mpp < 90))
  return auto.regen and "regen" or (auto.refresh and "refresh") or nil
end

-- The set our status and toggles want between actions (vanagear template names when the engine is on).
function M.default_set()
  local p = M.H.player() or {}
  local job_sets = {}
  for _, s in ipairs(M.job_sets(state.job or "")) do job_sets[s] = true end
  local modes = M.modes()
  local function first(...)
    for _, s in ipairs({ ... }) do
      if job_sets[s] then return s end
    end
  end
  local eng = M.H.engine()
  if p.status == 1 then
    -- Engaged: Tp_<mode> (Default / Acc / Hybrid), or a pet fighting set.
    local tp = modes.hybrid and "Hybrid" or (modes.acc and "Acc") or "Default"
    if eng then
      if M.H.pet() then
        if modes.pet == "dt" then return first("PetDT", "PetTP", "Tp_" .. tp, "Tp_Default") end
        if modes.pet == "acc" then return first("PetAcc", "PetTP", "Tp_" .. tp, "Tp_Default") end
        return first("PetTP", "Tp_" .. tp, "Tp_Default")
      end
      return first("Tp_" .. tp, "Tp_Default")
    end
    if modes.hybrid then return first("TP_Hybrid", "TP_MNK", "TP") end
    if modes.acc then return first("TP_Acc", "TP_MNK", "TP") end
    if M.H.pet() then
      if modes.pet == "dt" then return first("TP_Pet_DT", "TP_Pet", "Automaton", "TP_MNK", "TP") end
      if modes.pet == "acc" then return first("TP_Pet_Acc", "TP_Pet", "Automaton", "TP_MNK", "TP") end
      return first("TP_Pet", "Automaton", "TP_MNK", "TP")
    end
    return first("TP_MNK", "TP")
  end
  if p.status == 33 then return first("Resting", "Idle") end
  if M.H.pet() then
    if eng then return first("PetIdle", "Idle") end
    return first("Idle_Avatar", "Idle_Luopan", "Idle_Pet", "Idle")
  end
  local idle = modes.idle or "auto"
  if idle == "auto" then idle = auto_idle(p) end
  if idle == "regen" then return first("Idle_Regen", "Idle") end
  if idle == "refresh" then return first("Idle_Refresh", "Idle") end
  return "Idle"
end

-- ---- Actions ----

local busy_until = 0
-- An action wore its sets: the status set goes back on once it ends.
local restore = false

-- Wearing the sets: the settings, and the player turned it on in the window (nothing moves after an update until
-- they do).
function M.loaded()
  return M.H.on() and M.active() and state.job ~= nil and state.ready
end

-- The sets an action wears: {precast, midcast} names, and its element / weapon skill.
-- With the engine on, names are vanagear's (Cure, Nuke, Burst, Ws_Default, SavageBlade...); otherwise the catalogue's.
function M.route(act)
  local job_sets = {}
  for _, s in ipairs(M.job_sets(state.job)) do job_sets[s] = true end
  local modes = M.modes()
  local eng = M.H.engine()
  local function have(name) return name and job_sets[name] and name or nil end

  if act.category == 3 then
    local sp = M.H.spell(act.param)
    if not sp then return nil end
    sp.id = sp.id or act.param
    if eng then
      local vplan = require("src.vg.plan")
      local skill_name = ({
        [32] = "Divine Magic", [33] = "Healing Magic", [34] = "Enhancing Magic", [35] = "Enfeebling Magic",
        [36] = "Elemental Magic", [37] = "Dark Magic", [39] = "Ninjutsu", [40] = "Singing", [41] = "Singing",
        [42] = "Singing", [43] = "Blue Magic", [44] = "Geomancy",
      })[sp.skill]
      local own = vplan.WsSetName(sp.name)
      local kind = skill_name and vplan.SpellMode(skill_name, sp.name)
      local mid = have(own) or have(kind)
      -- family sets the templates wear (Regen II -> Regen, Aspir -> Drain)
      if not have(own) then
        local n = sp.name or ""
        if n:find("^Phalanx") then mid = have("Phalanx") or mid end
        if n:find("^Stoneskin") then mid = have("Stoneskin") or mid end
        if n:find("^Regen") then mid = have("Regen") or mid end
        if n:find("^Refresh") then mid = have("Refresh") or mid end
        if n:find("^Drain") or n:find("^Aspir") then mid = have("Drain") or mid end
        if n:find("helix") then mid = have("Helix") or mid end
        if n:find("na$") or n == "Cursna" then mid = have("Cursna") or mid end
      end
      local n = sp.name or ""
      local pre = have("Precast")
      if n:find("^Cur") then pre = have("Cure_Precast") or pre end
      if skill_name == "Singing" then pre = have("Song_Precast") or pre end
      if (skill_name == "Elemental Magic" or (skill_name == "Ninjutsu" and (sp.name or ""):find("^%a+ton:"))) then
        if modes.macc then mid = have("NukeACC") or mid end
        if modes.mb then mid = have("Burst") or mid end
      elseif skill_name == "Enfeebling Magic" and modes.macc then
        mid = have("Macc") or mid
      end
      return { pre, mid, element = sets.ELEMENT_ID[sp.element or -1], cast = sp.cast_time }
    end
    local r = sets.spell_sets(sp, blu)
    if r[2] == "Nuke" and modes.mb and job_sets.Nuke_MB then r[2] = "Nuke_MB" end
    if r[2] == "Nuke" and modes.macc and job_sets.MagicAcc then r[2] = "MagicAcc" end
    return { job_sets[r[1]] and r[1] or nil, job_sets[r[2]] and r[2] or nil, element = sets.ELEMENT_ID[sp.element or -1],
      cast = sp.cast_time }
  elseif act.category == 7 then
    local id = act.param
    local a = M.H.ability(id)
    local ws = wslist[id]
    if eng then
      local own = a and require("src.vg.plan").WsSetName(a.name)
      if have(own) then return { nil, own, ws = ws } end
      return { nil, have("Ws_Default"), ws = ws }
    end
    local own = "WS:" .. id
    if job_sets[own] then return { nil, own, ws = ws } end
    if ws and ws.kind == "ranged" and job_sets.RangedWS then return { nil, "RangedWS", ws = ws } end
    return { nil, job_sets.WS and "WS" or nil, ws = ws }
  elseif act.category == 9 then
    local a = M.H.ability(core.res_id(act))
    if not a then return nil end
    if eng then
      local own = require("src.vg.plan").WsSetName(a.name)
      return { nil, have(own) or have("Enmity") }
    end
    local r = sets.ability_sets(a.name, job_sets)
    return { nil, r[1] }
  elseif act.category == 16 then
    local mid = have("Midshot")
    if eng and modes.acc then mid = have("Midshot_Acc") or mid end
    return { have("Preshot"), mid }
  end
end


function M.action(act)
  if not M.loaded() or act.kind == "item" then return end
  local r = M.route(act)
  if not r or (not r[1] and not r[2]) then
    if act.category == 7 and M.H.ws_line() then
      local a = M.H.ability(act.param)
      chat.add("Gearshift: no set for " .. (a and a.name or ("weapon skill " .. act.param)) .. ".")
    end
    return
  end
  if r[1] then wear(M.pieces(r[1]), "auto") end
  local main
  if r[2] then
    main = M.pieces(r[2])
    element_gear(main, r[2], r.element)
    if r.ws then
      if r.ws.kind == "magic" then element_gear(main, "Nuke", r.ws.element) end
      ws_gear(main, r.ws)
    end
  end
  -- A weapon skill or an ability lands at once: its set goes first (the server also refuses weapons and ammo once a
  -- weapon skill has started). A spell's or a shot's comes after, for the cast.
  local instant = act.category == 7 or act.category == 9
  local changed = main and instant and wear(main, "single")
  if act.category == 7 and M.H.ws_line() then
    local a = M.H.ability(act.param)
    local ws = a and a.name or ("weapon skill " .. act.param)
    local def = r[2] and M.set_def(r[2])
    local set = def and def.label or r[2]
    if changed == 0 then
      chat.add(string.format("Gearshift: %s, the %s set already on.", ws, set))
    else
      chat.add(string.format("Gearshift: %s, the %s set on before it (%d piece%s).", ws, set, changed,
        changed == 1 and "" or "s"))
    end
  end
  core.H.inject(act.packet)
  if main and not instant then wear(main, "single") end
  -- Held until the action ends (its finish or interruption below), at most its cast time and a margin.
  busy_until = clock() + math.max(3, (r.cast or 0) + 2)
  restore = true
  return false
end

local DONE = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [14] = true, [15] = true }
function M.on_action(a)
  if not M.loaded() then return end
  local p = M.H.player()
  if not p or a.actor ~= p.id then return end
  -- A finish, or an interrupted cast / shot (param 28787).
  if DONE[a.category] or ((a.category == 8 or a.category == 12) and a.param == 28787) then busy_until = 0 end
  -- A worn charged piece used (category 5, the item's id): it is let go, and the status set comes back (a potion or
  -- food changes nothing).
  if a.category == 5 and a.param then
    for slot, w in pairs(core.worn()) do
      local rec = pick.item(w.id)
      if w.id == a.param and rec and (rec.max_charges or 0) > 0 and not core.put_by_us(slot, w) then
        used[a.param] = true
        restore = true
      end
    end
  end
end

-- Between actions: the status's set, and the Movement set's moving pieces while we run.
local last_default, last_pos
local function moving()
  local p = M.H.player()
  local pos = p and p.pos
  if not pos then return false end
  local moved = last_pos and ((pos.x - last_pos.x) ^ 2 + (pos.z - last_pos.z) ^ 2) > 0.01
  last_pos = { x = pos.x, z = pos.z }
  return moved or false
end

-- A set's pieces that carry the stat, laid over the pieces of the set worn (a set not built yet is asked for first).
local function overlay(pieces, set_name, stat)
  local r = state.built[set_name]
  if not r then
    M.want_first(set_name)
    return
  end
  for slot, o in pairs(r.slots) do
    if o.pick and (o.pick.s.stats[stat] or 0) > 0 then pieces[slot] = { name = pick.item(o.pick.id).name } end
  end
end

-- The towns where the Town set goes on (GetAwayCoxn's list, as vanagear has it).
local TOWNS = {}
for _, n in ipairs({ "Tavnazian Safehold", "Al Zahbi", "Aht Urhgan Whitegate", "Nashmau", "Southern San d'Oria [S]",
  "Bastok Markets [S]", "Windurst Waters [S]", "San d'Oria-Jeuno Airship", "Bastok-Jeuno Airship",
  "Windurst-Jeuno Airship", "Kazham-Jeuno Airship", "Southern San d'Oria", "Northern San d'Oria", "Port San d'Oria",
  "Chateau d'Oraguille", "Bastok Mines", "Bastok Markets", "Port Bastok", "Metalworks", "Windurst Waters",
  "Windurst Walls", "Port Windurst", "Windurst Woods", "Heavens Tower", "Ru'Lude Gardens", "Upper Jeuno",
  "Lower Jeuno", "Port Jeuno", "Rabao", "Selbina", "Mhaura", "Kazham", "Norg", "Mog Garden",
  "Celennia Memorial Library", "Western Adoulin", "Eastern Adoulin" }) do
  TOWNS[n] = true
end
-- The status effects the ailment sets answer to (the server's effect ids).
local SLEEP, DOOM, WEAKNESS = { [2] = true, [19] = true }, { [15] = true, [30] = true }, { [1] = true }

-- A whole set laid over the pieces (no weapons: they would reset TP), when it holds anything.
local function lay(pieces, set_name)
  local r = state.built[set_name]
  local mine = M.hand(state.job, set_name)
  if not r then
    M.want_first(set_name)
  end
  local any = false
  for slot, piece in pairs(M.pieces(set_name)) do
    if slot > 2 and piece.name then
      pieces[slot] = piece
      any = true
    end
  end
  return any or next(mine) ~= nil
end

-- Vanagear's include.Default, over the status set: the Town set standing in a town, the damage taken gear (the toggle,
-- or below 40% HP), the pet's below half its HP, and the ailment sets last, so what you wear for them beats the rest.
function M.lay_status_sets(pieces, p, modes)
  local function has(ids)
    for _, b in ipairs(M.H.buffs() or {}) do
      if ids[b.id] then return true end
    end
  end
  if (p.status or 0) == 0 then
    local zone = M.H.zone_name()
    if zone and TOWNS[zone] then lay(pieces, "Town") end
  end
  if M.H.engine() then
    -- vanagear: /vg dt all|pdt|mdt
    if modes.pdt and not modes.mdt then
      lay(pieces, "Dt_Physical")
    elseif modes.mdt and not modes.pdt then
      lay(pieces, "Dt_Magic")
    elseif modes.pdt or modes.mdt then
      lay(pieces, "Dt")
    end
  else
    if modes.pdt and modes.mdt then
      lay(pieces, "Dt")
    elseif modes.pdt then
      lay(pieces, "PDT")
    elseif modes.mdt then
      lay(pieces, "MDT")
    end
  end
  if (p.hpp or 100) < 40 then lay(pieces, "Dt") end
  local pet_hpp = M.H.pet_hpp()
  if pet_hpp and pet_hpp < 50 then lay(pieces, "PetDT") end
  if has(SLEEP) then lay(pieces, "Sleeping") end
  if has(DOOM) then lay(pieces, "Doomed") end
  if has(WEAKNESS) then lay(pieces, "Reraise") end
end

-- The status set is worn when it changes (the status, a toggle, the level's picks, running) or after an action, not
-- every tick: a piece changed by hand stays on until then.
local last_sig
function M.tick()
  if not M.loaded() or clock() < busy_until then return end
  local name = M.default_set()
  -- Not while it is being built: half a set would be worn, then the whole one.
  if not state.built[name] then
    M.want_first(name)
    return
  end
  local pieces = M.pieces(name)
  -- Gear laid over the status set: Movement while we run, or always with /vg kite (and /vg idle speed, standing
  -- still), Treasure Hunter with /vg th.
  local modes = M.modes()
  local running = moving()
  local p = M.H.player() or {}
  if running or modes.kite or (modes.idle == "speed" and (p.status or 0) == 0) then overlay(pieces, "Movement", "move") end
  if modes.th and p.status == 1 then overlay(pieces, "TH", "th") end
  M.lay_status_sets(pieces, p, modes)
  last_default = name
  local sig = {}
  for slot = 0, 15 do sig[#sig + 1] = pieces[slot] and pieces[slot].name or "" end
  sig = name .. "|" .. table.concat(sig, "|")
  if sig == last_sig and not restore then return end
  last_sig, restore = sig, false
  wear(pieces, "auto")
end

function M.current() return last_default end

-- //vg mode <hybrid|acc|pdt|mdt|mb|macc> toggles one; "off" clears them.
function M.toggle(mode)
  local modes = M.modes()
  if mode == "off" then
    for k in pairs(modes) do modes[k] = nil end
    return "toggles off"
  end
  modes[mode] = not modes[mode] or nil
  return mode .. (modes[mode] and " on" or " off")
end

-- ---- /vg: locks, weapons, one slot of a set, why a piece won, upgrades in storage ----

-- Slot words: ours, and the equipment menu's (ear1, ring2...).
local SLOT_ALIAS = { ear1 = "left_ear", ear2 = "right_ear", lear = "left_ear", rear = "right_ear", ring1 = "left_ring",
  ring2 = "right_ring", lring = "left_ring", rring = "right_ring" }
M.SLOT_NAME = pick.SLOT_NAMES
M.SLOT_LABEL = { [0] = "Main", "Sub", "Range", "Ammo", "Head", "Body", "Hands", "Legs", "Feet", "Neck", "Waist",
  "L. Ear", "R. Ear", "L. Ring", "R. Ring", "Back" }
function M.slot_index(word)
  word = (word or ""):lower()
  word = SLOT_ALIAS[word] or word
  for slot, n in pairs(pick.SLOT_NAMES) do
    if n == word then return slot end
  end
end

local function norm(s) return (tostring(s or ""):lower():gsub("[^%w]", "")) end

-- A set of the job by its name or label ("tp", "Cure", "Savage Blade"), as the window lists them.
function M.find_set(word)
  local w = norm(word)
  if w == "" then return nil end
  for _, name in ipairs(M.job_sets(state.job or "")) do
    local def = M.set_def(name)
    if norm(name) == w or (def and norm(def.label) == w) then return name end
  end
end

-- Slots left alone for the job (/vg lock): {slot = true}.
function M.locks()
  local b = saved()
  b.locks = b.locks or {}
  return b.locks[state.job or ""] or {}
end

-- slot: 0..15, or "all".
function M.lock(slot, on)
  local b = saved()
  b.locks = b.locks or {}
  local job = state.job or ""
  b.locks[job] = b.locks[job] or {}
  for s = 0, 15 do
    if slot == "all" or slot == s then b.locks[job][s] = on or nil end
  end
  if not next(b.locks[job]) then b.locks[job] = nil end
  last_sig = nil
  M.rebuild()   -- the engine leaves a locked slot out of every set
end

-- A piece we carry by name (any case), as it is spelled.
local function owned_name(word)
  local w = norm(word)
  for _, o in ipairs(state.owned or {}) do
    if norm(o.name) == w then return o.name end
  end
end

-- /vg weapon main|sub|range <item | none>: kept in every set. Returns the piece's name, or nil for none.
function M.set_weapon(slot_name, item)
  local b = saved()
  b.weapons = b.weapons or {}
  if item == nil or item:lower() == "none" then
    b.weapons[slot_name] = nil
    if not next(b.weapons) then b.weapons = nil end
    return true
  end
  local name = owned_name(item)
  if not name then return false end
  b.weapons[slot_name] = name
  last_sig = nil
  return true, name
end

-- /vg set <set> <slot> <item | auto>: one slot of a built set by hand, as the window's lists do.
function M.set_slot(set_name, slot_name, item)
  local h = M.hand(state.job, set_name)
  if item:lower() == "auto" then
    h[slot_name] = nil
    return true
  end
  local name = owned_name(item)
  if not name then return false end
  h[slot_name] = { name = name }
  last_sig = nil
  return true, name
end

-- What an owned piece is worth in a slot of a set: by the engine's weights for a set it built, else the builder's.
function M.rate(set_name, def, o, slot)
  local r = state.built[set_name]
  local v = r and r.engine and engine.rate(set_name, ctx(), o, slot)
  if v then return v end
  return pick.score(pick.stats_of(o.id, o.augments), def)
end

-- /vg why <set> <slot>: the piece that won and the ones behind it, by the set's score.
function M.why(set_name, slot)
  local def, r = M.set_def(set_name), state.built[set_name]
  if not def or not r then
    M.want_first(set_name)
    return nil
  end
  local c = ctx()
  local list, seen = {}, {}
  for _, o in ipairs(state.owned or {}) do
    local rec = pick.item(o.id)
    if not seen[o.name] and pick.fits(rec, slot, c.job_id, c.race, c.level, c.sub_id) then
      seen[o.name] = true
      list[#list + 1] = { name = o.name, score = M.rate(set_name, def, o, slot) }
    end
  end
  table.sort(list, function(a, b) return a.score > b.score end)
  local won = r.slots[slot] and r.slots[slot].pick
  return { won = won and pick.item(won.id).name, how = r.slots[slot] and r.slots[slot].how, list = list, def = def }
end

-- /vg upgrades: pieces in storage (outside the bags we wear from) that would win a slot of a set we built.
function M.upgrades()
  local c = ctx()
  local out, seen = {}, {}
  for _, name in ipairs(M.job_sets(state.job or "")) do
    local def, r = M.set_def(name), state.built[name]
    if def and r then
      for slot = 4, 15 do
        local cur = r.slots[slot] and r.slots[slot].pick
        local cur_score = cur and (cur.owned and M.rate(name, def, cur.owned, slot) or pick.score(cur.s, def)) or 0
        for _, o in ipairs(state.elsewhere or {}) do
          local rec = pick.item(o.id)
          if pick.fits(rec, slot, c.job_id, c.race, c.level, c.sub_id) then
            local sc = M.rate(name, def, o, slot)
            if sc > cur_score and sc > 0 and not seen[o.name] then
              seen[o.name] = true
              out[#out + 1] = { name = o.name, bag = core.BAG_NAMES[o.bag] or tostring(o.bag), set = def.label or name,
                slot = pick.SLOT_NAMES[slot] }
            end
          end
        end
      end
    end
  end
  return out
end

return M
