-- Trust gear for the Vanadreams server (port of vanagear's vg/trusts.lua): every trust you have called gets gear sets
-- built from your bags for its job and level, sent to the server as `!trustgear <trust id> <set> <16 item ids>`.
-- The trust never wears anything and your gear never leaves your bags: the server gives the trust the stats of the
-- pieces while you carry them in your inventory or a wardrobe, and swaps its sets as its actions go off.
--
-- The server's side (what vanagear speaks):
--   !trustgear <id> info            -> [VG trust] <id>|<name>|<main job>|<sub job>|<level>
--                                      [VG uses] <id>|<name>:<kind>,<name>:<kind>...
--   !trustuse  <id> info            -> [VG off] <id>|<key>,<key>...       (what the player switched off)
--   !trustgear <id> <set> <ids>     (16 item ids, Main 0 .. Back 15; "clear" deletes the set)
--   !trustuse  <id> off|on <action>
-- The server answers only for your own trusts. Those answer lines are dropped from the chat log, and so is the echo
-- of the lines we send.
--
-- A piece goes to one user: your own sets have first call on what you carry, then your trusts in party order, each
-- built from what is left, so a trust gets the next best piece or leaves the slot empty.
--
-- The sets are built by vanagear's own engine (src/vg: its weights, caps, set bonuses, latents and rounds, over the
-- server's item data and the augments the server applies), not by this mod's builder.

local pick = require("src.build.pick")
local run = require("src.build.run")
local core = require("src.core")
local vplan = require("src.vg.plan")
local score = require("src.vg.score")
local pieces_of = require("src.vg.pieces")
local vdata = require("src.vg.data")

local M = {}

-- The game, through one table (tests replace it).
M.H = {
  party = function() return game.party() end,
  player = function() return game.player() end,
  job = function(id) return res.job(id) end,
  ability = function(id) return res.ability(id) end,
  storage = function() return storage.character end,
  say = function(line) commands.run(line) end,
  now = function() return clock() end,
  print = function(text) chat.add(text) end,
  enabled = function() return settings.get("trustgear") ~= false end,
}

-- Players' server ids are below 0x01000000; trusts are zone entities above it.
local TRUST_ID = 0x01000000

-- ---- Names the server uses ----

-- How the server keeps set names: "Savage Blade" -> "savageblade".
function M.key(name)
  local s = (name or ""):lower():gsub("%W", "")
  return s:sub(1, 32)
end

-- The game data's names read nicely: "cure_iv" -> "Cure IV", "savage_blade" -> "Savage Blade".
local ROMAN = { i = true, ii = true, iii = true, iv = true, v = true, vi = true, vii = true, viii = true, ix = true, x = true }
function M.pretty(key)
  local words = {}
  for w in (key or ""):gmatch("[^_%s]+") do
    words[#words + 1] = ROMAN[w] and w:upper() or (w:sub(1, 1):upper() .. w:sub(2))
  end
  return table.concat(words, " ")
end

-- ---- What a trust's sets are ----

-- What an Engaged set values, by job: one of roles.lua's modes, or "Tank" below.
M.MODE_FOR = {
  WAR = "Tp_Default", MNK = "Tp_Default", THF = "Tp_Default", DRK = "Tp_Default", BST = "Tp_Default",
  SAM = "Tp_Default", NIN = "Tp_Default", DRG = "Tp_Default", DNC = "Tp_Default", BLU = "Tp_Default",
  PUP = "Tp_Default", PLD = "Tank", RUN = "Tank", RNG = "Midshot", COR = "Midshot",
  WHM = "Idle_Refresh", BLM = "Idle_Refresh", SCH = "Idle_Refresh", RDM = "Tp_Default", BRD = "Idle_Refresh",
  GEO = "Idle_Refresh", SMN = "Idle_Refresh",
}

-- Jobs that hold hate: their Engaged set is a tank's and they get an Ability set for enmity.
M.TANKS = { PLD = true, RUN = true }

-- Jobs that stand back and cast: no Weaponskill set unless they use one.
local CASTERS = { WHM = true, BLM = true, SCH = true, BRD = true, GEO = true, SMN = true }

-- Trust-only modes, laid out like roles.lua's.
local DT = { PDT = -50, MDT = -50 }
local TRUST_MODES = {
  Tank = {
    Stats = { PDT = -6, MDT = -5, HP = 0.04, ENMITY = 1, DEF = 0.03, MEVA = 0.05, ACC = 0.3, STORETP = 0.6,
      DOUBLE_ATTACK = 0.8, HASTE_GEAR = 1.5 },
    Caps = { PDT = -50, MDT = -50, HASTE_GEAR = 25 },
  },
  Enmity = { Stats = { ENMITY = 3, PDT = -1.5, MDT = -1, HP = 0.03 }, Caps = DT },
}

-- The server's spell kinds (trustgearutils::SpellKind): the name of its set here and the roles.lua mode it is built
-- from.
M.KINDS = {
  { key = "cure", name = "Cure", mode = "Cure" },
  { key = "nuke", name = "Nuke", mode = "Nuke" },
  { key = "enfeebling", name = "Enfeebling", mode = "Enfeebling" },
  { key = "enhancing", name = "Enhancing", mode = "Enhancing" },
  { key = "dark", name = "Dark", mode = "Dark" },
  { key = "divine", name = "Divine", mode = "Divine" },
  { key = "song", name = "Song", mode = "Song" },
  { key = "ninjutsu", name = "Ninjutsu", mode = "Ninjutsu" },
  { key = "bluemagic", name = "Blue Magic", mode = "BluePhysical" },
  { key = "geomancy", name = "Geomancy", mode = "Geomancy" },
}
local KIND_BY_KEY = {}
for _, k in ipairs(M.KINDS) do KIND_BY_KEY[k.key] = k end

-- The spell kinds a job's trusts cast, until the server says what this one uses.
local JOB_KINDS = {
  WHM = { "cure", "enhancing", "divine" }, RDM = { "enfeebling", "enhancing", "cure", "nuke" },
  BLM = { "nuke", "enfeebling", "dark" }, SCH = { "nuke", "cure", "enhancing" }, PLD = { "cure", "divine" },
  DRK = { "dark" }, NIN = { "ninjutsu" }, BLU = { "bluemagic" }, BRD = { "song" }, GEO = { "geomancy", "nuke" },
  RUN = { "enhancing" },
}

-- The sets planned for a trust: {name, key, mode (a roles.lua mode table), when}. `uses` is what the server said the
-- trust uses ({name, kind}), nil until it does.
function M.plan(t, uses)
  local job = vplan.Job(t.job)
  -- the job template's band for the trust's level laid over its all-level tweaks, as your own sets are built
  local tweaks = vplan.BandTweaks(job, t.level or 99)
  local function named(name)
    local m = TRUST_MODES[name]
    if m then
      local c = { Name = name, Stats = {}, Caps = {} }
      for k, v in pairs(m.Stats) do c.Stats[k] = v end
      for k, v in pairs(m.Caps or {}) do c.Caps[k] = v end
      return c
    end
    return vplan.Mode(name, tweaks)
  end

  local list, seen = {}, {}
  local function add(name, mode, when)
    local key = M.key(name)
    if key ~= "" and not seen[key] then
      seen[key] = true
      list[#list + 1] = { name = name, key = key, mode = mode, when = when }
    end
  end

  -- A trust needs no Idle set: it fights in Engaged and its abilities, spells and weaponskills swap in over that (out
  -- of a fight the server falls back to Engaged).
  local tank = M.TANKS[t.job]
  add("Engaged", named(M.MODE_FOR[t.job] or "Tp_Default"), tank and "fighting: damage taken down and enmity" or "fighting")

  local kinds, uses_ws = {}, false
  if uses then
    for _, u in ipairs(uses) do
      if KIND_BY_KEY[u.kind] then kinds[u.kind] = true end
      if u.kind == "weaponskill" then uses_ws = true end
    end
  else
    for _, k in ipairs(JOB_KINDS[t.job] or {}) do kinds[k] = true end
    uses_ws = not CASTERS[t.job]
  end
  if uses_ws then add("Weaponskill", named("Ws_Default"), "any weapon skill without a set of its own") end
  for _, k in ipairs(M.KINDS) do
    if kinds[k.key] then add(k.name, named(k.mode), string.lower(k.name) .. " spells") end
  end
  if tank then add("Ability", named("Enmity"), "job abilities: enmity") end

  -- Each weaponskill it uses that the server's scripts give stat modifiers for gets a set of its own, and each job
  -- ability it uses that the server reads gear for (data/abilities.lua) gets its own swap-in.
  if uses then
    local ws_by_key, ability_by_key = {}, {}
    for _, ws in pairs(vdata.Weaponskills()) do ws_by_key[ws.key] = ws end
    for _, a in pairs(vdata.Abilities()) do ability_by_key[a.key] = a end
    for _, u in ipairs(uses) do
      local ws = ws_by_key[u.name]
      if u.kind == "weaponskill" and ws and next(ws.wsc) ~= nil then
        local display = M.pretty(u.name)
        add(display, vplan.WsMode(ws, display), display)
      end
      local a = ability_by_key[u.name]
      if u.kind == "ability" and a then
        local m = { Name = M.pretty(u.name), Stats = {}, Caps = {} }
        for _, mod in ipairs(a.mods) do
          if mod ~= "ONE_HOUR_RECAST" and vdata.ModId(mod) then m.Stats[mod] = 1 end
        end
        if next(m.Stats) ~= nil then add(m.Name, m, m.Name) end
      end
    end
  end
  return list
end

-- ---- The trusts in the party ----

-- { id, index, name, job (abbreviation), job_id, level, sub, sub_id }, in party order.
function M.called()
  local out = {}
  for _, m in ipairs(M.H.party() or {}) do
    if m.party == 0 and m.id and m.id >= TRUST_ID then
      out[#out + 1] = { id = m.id, index = m.index, name = m.name, job_id = m.main_job, job = M.H.job(m.main_job) or "",
        level = m.main_level or 0, sub_id = m.sub_job, sub = M.H.job(m.sub_job or 0) or "" }
    end
  end
  return out
end

-- ---- What the server said ----

local info = {}            -- trust id -> { name, job, sub, level, uses = {{name, kind}}, off = {key = true} }
local info_version = 0     -- bumped by every answer: a trust's sets are built again
local checked_at = 0       -- the work looks again at this time (an answer, a party change or a pick resets it)
local asked = {}           -- trust id -> true once its info was asked for

-- A trust's support job: the server's word for it, else the party's. Its gear may be worn too (Vanadreams).
local function sub_of(t)
  local i = info[t.id]
  return (i and (i.sub or 0) > 0) and i.sub or t.sub_id
end

-- The chat filter: the server's answers (kept, dropped from the log) and the echo of what we sent (dropped).
local echoes = {}          -- line text -> time to forget it
function M.filter(text)
  local id, name, job, sub, level = text:match("%[VG trust%] (%d+)|([^|]*)|(%d+)|(%d+)|(%d+)")
  if id then
    id = tonumber(id)
    local old = info[id]
    info[id] = { name = name, job = tonumber(job), sub = tonumber(sub), level = tonumber(level), uses = {},
      off = old and old.off or {} }
    info_version = info_version + 1
    checked_at = 0
    return false
  end
  local off_id, off_list = text:match("%[VG off%] (%d+)|([^\r\n]*)")
  if off_id then
    local i = info[tonumber(off_id)]
    if i then
      i.off = {}
      for key in off_list:gmatch("%w+") do i.off[key] = true end
    end
    return false
  end
  local uses_id, list = text:match("%[VG uses%] (%d+)|([^\r\n]*)")
  if uses_id then
    local i = info[tonumber(uses_id)]
    if i then
      for name, kind in list:gmatch("([%w_]+):(%a+)") do i.uses[#i.uses + 1] = { name = name, kind = kind } end
      info_version = info_version + 1
      checked_at = 0
    end
    return false
  end
  -- Our own lines, echoed: the first matching line of each is dropped.
  if next(echoes) and (text:find("!trustgear ", 1, true) or text:find("!trustuse ", 1, true)) then
    local now = M.H.now()
    for line, expires in pairs(echoes) do
      if expires < now then
        echoes[line] = nil
      elseif text:find(line, 1, true) then
        echoes[line] = nil
        return false
      end
    end
  end
end

-- ---- Saved: what the server has, and the picks you made ----

local function saved()
  local st = M.H.storage()
  st.trustgear = st.trustgear or {}
  local s = st.trustgear
  s.sent = s.sent or {}   -- trust name -> set key -> ids
  s.own = s.own or {}     -- trust name -> set name -> slot name -> item name | "remove"
  return s
end

-- ---- The send queue: one line at a time, so chat is not flooded ----

local queue, send_at = {}, 0
local function enqueue(key, line)
  for _, q in ipairs(queue) do
    if q.key == key then q.line = line return end
  end
  queue[#queue + 1] = { key = key, line = line }
end

-- ---- Pieces: one user each ----

-- The pieces a set group names, by lower-case name: the most copies any one set needs (two of the same ring in one
-- set need two rings; the same piece in two sets is one, as only one set is worn at a time).
-- groups: set name -> slot -> item name.
local function needed(groups, into)
  for _, set in pairs(groups or {}) do
    local in_set = {}
    for _, name in pairs(set) do
      if type(name) == "string" and name ~= "remove" then
        local key = name:lower()
        in_set[key] = (in_set[key] or 0) + 1
      end
    end
    for key, n in pairs(in_set) do
      if n > (into[key] or 0) then into[key] = n end
    end
  end
  return into
end

-- Our own sets as names: set name -> slot -> item name (what was built, then what we picked by hand).
local function player_sets()
  local out = {}
  for name, r in pairs(run.state.built or {}) do
    local set = {}
    for slot, o in pairs(r.slots) do
      if o.pick then
        local rec = pick.item(o.pick.id)
        if rec then set[slot] = rec.name end
      end
    end
    out[name] = set
  end
  if run.state.job then
    for name, picks in pairs(run.H.storage().builder and run.H.storage().builder.jobs[run.state.job] or {}) do
      out[name] = out[name] or {}
      for slot_name, h in pairs(picks) do
        for slot, n in pairs(pick.SLOT_NAMES) do
          if n == slot_name and h and h.name then out[name][slot] = h.name end
        end
      end
    end
  end
  return out
end

-- The weapons and ammo we wear now: not ours to give away.
local function worn_names()
  local set = {}
  for slot, w in pairs(core.worn()) do
    local rec = slot <= 3 and w and w.id and pick.item(w.id)
    if rec then set[slot] = rec.name end
  end
  return { worn = set }
end

-- ---- Building ----

local built = {}           -- trust id -> { sig, plan, final = {key -> {slot -> name}}, ids = {key -> "..."} }

-- The trust as the engine needs it. Trusts have no race limit, and their support job's gear may be worn too.
function M.who(t)
  return { Job = t.job_id, JobName = t.job, Level = t.level, Sub = sub_of(t), SubLevel = 0, Race = 0 }
end

-- The pool for a trust: our equip bags less what we and the trusts before it hold.
local function pool_for(order, upto)
  local held = needed(player_sets(), {})
  needed(worn_names(), held)
  for i = 1, upto - 1 do
    local b = built[order[i].id]
    if b then
      local finals = {}
      for key, names in pairs(b.final) do finals[key] = names end
      for key, n in pairs(needed(finals, {})) do held[key] = (held[key] or 0) + n end
    end
  end
  local keys = {}
  for k, n in pairs(held) do keys[#keys + 1] = k .. "=" .. n end
  table.sort(keys)
  local left, pool = {}, {}
  for k, n in pairs(held) do left[k] = n end
  for _, o in ipairs(run.state.owned or {}) do
    local key = (o.name or ""):lower()
    if (left[key] or 0) > 0 then
      left[key] = left[key] - 1
    else
      pool[#pool + 1] = o
    end
  end
  return pool, table.concat(keys, ",")
end

-- The final piece names of a set (slots 0 to 15): our picks over what was built (slots 1 to 16, vanagear's numbering).
local function final_of(t, entry, set)
  local out = {}
  for slot, piece in pairs(set) do out[slot - 1] = piece.Name end
  local mine = saved().own[t.name] and saved().own[t.name][entry.name] or {}
  for slot, n in pairs(pick.SLOT_NAMES) do
    if mine[n] == "remove" then
      out[slot] = nil
    elseif mine[n] then
      out[slot] = mine[n]
    end
  end
  return out
end

-- An item id by name in our bags, a piece the trust may use first.
local function id_of(name, owned_index)
  return owned_index[name:lower()] or 0
end

local function ids_of(final, owned_index)
  local ids, any = {}, false
  for slot = 0, 15 do
    local name = final[slot]
    ids[slot + 1] = name and id_of(name, owned_index) or 0
    any = any or ids[slot + 1] ~= 0
  end
  return any and table.concat(ids, " ") or "clear"
end

-- The whole of what a trust's sets depend on, as one string.
local function signature(t, i, held_sig)
  return table.concat({ tostring(run.state.owned_sig), info_version, i and #i.uses or -1, t.job_id, sub_of(t), t.level, held_sig },
    "|")
end

local sig_cache = {}

-- Builds one trust's sets again if anything they depend on changed; true when it did work.
local function refresh(order, n)
  local t = order[n]
  local i = info[t.id]
  if not i or not run.state.ready then return false end
  local pool, held_sig = pool_for(order, n)
  local sig = signature(t, i, held_sig)
  local b = built[t.id]
  if b and b.sig == sig then return false end

  local plan = M.plan(t, i.uses)
  local who = M.who(t)
  local slots = {}
  for slot = 1, 16 do slots[slot] = slot end
  local pieces = {}
  for _, o in ipairs(pool) do
    local piece = pieces_of.of(o)
    if piece then pieces[#pieces + 1] = piece end
  end

  local nb = { sig = sig, plan = plan, final = {}, ids = {}, result = {} }
  local owned_index = {}
  -- Every piece we carry, not only the pool: a piece the player picked by hand may be one we wear ourselves.
  for _, o in ipairs(run.state.owned or {}) do
    local key = (o.name or ""):lower()
    if not owned_index[key] then owned_index[key] = o.id end
  end
  for _, entry in ipairs(plan) do
    local set, _, total = score.Build(score.Compile(entry.mode), pieces, who, slots, { 0 }, true)
    nb.result[entry.key] = { set = set, score = total }
    nb.final[entry.key] = final_of(t, entry, set)
    nb.ids[entry.key] = ids_of(nb.final[entry.key], owned_index)
  end
  built[t.id] = nb
  M.send(t)
  return true
end

-- ---- Sending ----

-- What changed since the server last had this trust's sets (everything with all = true).
function M.send(t, all)
  local b = built[t.id]
  if not b then return end
  local s = saved()
  local had = s.sent[t.name] or {}
  local now, changed, listed = {}, false, {}
  for _, entry in ipairs(b.plan) do
    listed[entry.key] = true
    local ids = b.ids[entry.key]
    if ids ~= "clear" then now[entry.key] = ids end
    if all or had[entry.key] ~= now[entry.key] then
      changed = true
      enqueue(t.id .. " " .. entry.key, string.format("/say !trustgear %d %s %s", t.id, entry.key, ids))
    end
  end
  -- Sets the server has that are planned no more (a use switched off, a set of yours deleted).
  for key in pairs(had) do
    if not listed[key] then
      changed = true
      enqueue(t.id .. " " .. key, string.format("/say !trustgear %d %s clear", t.id, key))
    end
  end
  if changed then s.sent[t.name] = next(now) and now or nil end
end

-- ---- The work: the party, the answers, the builds ----

local party_sig

-- Called from the builder's worker when it has nothing left to do: one trust's sets again if they changed.
function M.step()
  if not M.H.enabled() or not run.H.on() or not run.state.ready or not run.state.owned then return false end
  local now = M.H.now()
  if now < checked_at then return false end
  local order = M.called()
  for n = 1, #order do
    if refresh(order, n) then return true end
  end
  checked_at = now + 2
  return false
end

-- The timer's work (0.4 s): the party changed (each new trust is asked about once), and the next queued line.
function M.tick()
  if not M.H.enabled() then return end
  local order = M.called()
  local sig = {}
  for _, t in ipairs(order) do sig[#sig + 1] = t.id .. ":" .. t.job_id .. ":" .. t.level end
  sig = table.concat(sig, ",")
  if sig ~= party_sig then
    party_sig = sig
    checked_at = 0
    local seen = {}
    for _, t in ipairs(order) do
      seen[t.id] = true
      if t.level > 0 and not asked[t.id] then
        asked[t.id] = true
        enqueue(t.id .. " info", string.format("/say !trustgear %d info", t.id))
        enqueue(t.id .. " off", string.format("/say !trustuse %d info", t.id))
      end
    end
    for id in pairs(asked) do
      if not seen[id] then asked[id], info[id], built[id] = nil, nil, nil end
    end
  end
  local now = M.H.now()
  if #queue > 0 and now > send_at then
    local q = table.remove(queue, 1)
    local echo = q.line:gsub("^/say ", "")
    echoes[echo] = now + 8
    M.H.say(q.line)
    send_at = now + 1.2
  end
end

-- Your own picks changed or the sets were asked for again: everything is built and checked again.
function M.rebuild()
  for id in pairs(built) do built[id].sig = nil end
  checked_at = 0
end

-- ---- Switching a trust's actions off and on ----

function M.set_off(t, action, off)
  local i = info[t.id]
  if not i then return false end
  i.off = i.off or {}
  i.off[M.key(action)] = off and true or nil
  enqueue(t.id .. " use " .. action, string.format("/say !trustuse %d %s %s", t.id, off and "off" or "on", action))
  return true
end

-- ---- For the trust window ----

-- What a trust's sets are now: {name, key, def, when}, in order (empty until it has answered).
function M.plan_of(t)
  local b = built[t.id]
  return b and b.plan or {}
end

-- A set's pieces by slot (0..15) as they will be sent: your picks over the built ones.
function M.final_of_set(t, key)
  local b = built[t.id]
  return b and b.final[key] or {}
end

-- What you picked for a slot of a set: an item name, "remove" or nil.
function M.own_pick(t, set_name, slot_name)
  local own = saved().own[t.name]
  return own and own[set_name] and own[set_name][slot_name]
end

-- value: an item name, "remove", or nil for automatic.
function M.set_pick(t, set_name, slot_name, value)
  local s = saved()
  s.own[t.name] = s.own[t.name] or {}
  s.own[t.name][set_name] = s.own[t.name][set_name] or {}
  s.own[t.name][set_name][slot_name] = value
  if not next(s.own[t.name][set_name]) then s.own[t.name][set_name] = nil end
  M.rebuild()
end

-- Every pick of yours for a set goes back to the builder's.
function M.reset_set(t, set_name)
  local own = saved().own[t.name]
  if own then own[set_name] = nil end
  M.rebuild()
end

-- The pieces we carry that the trust's job and level may wear in a slot, the set's best first: {name, score}. The score
-- is the piece's own weighted stats for the set (caps and set bonuses need a whole set).
function M.alternatives(t, set_name, slot)
  local entry
  for _, e in ipairs(M.plan_of(t)) do
    if e.name == set_name then entry = e end
  end
  local compiled = entry and score.Compile(entry.mode)
  local who = M.who(t)
  if compiled then compiled.Who = who end
  local list, seen = {}, {}
  for _, o in ipairs(run.state.owned or {}) do
    local piece = pieces_of.of(o)
    if piece and not seen[o.name] and pieces_of.can_wear(piece, slot + 1, who, true) then
      seen[o.name] = true
      local rate = 0
      if compiled then
        for k, v in pairs(score.Vector(piece, slot + 1, compiled, { 0 })) do rate = rate + (compiled.w[k] or 0) * v end
      end
      list[#list + 1] = { name = o.name, score = rate }
    end
  end
  table.sort(list, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.name < b.name
  end)
  return list
end

-- What the server said the trust uses, with whether it is switched off: {name (the server's), kind, off}.
function M.uses_of(t)
  local i = info[t.id]
  local out = {}
  for _, u in ipairs(i and i.uses or {}) do
    out[#out + 1] = { name = u.name, kind = u.kind, off = (i.off and i.off[M.key(u.name)]) == true }
  end
  return out
end

function M.info_of(t) return info[t.id] end

-- Sends every set of every trust again.
function M.send_all()
  for _, t in ipairs(M.called()) do M.send(t, true) end
end

function M.queued() return #queue end

-- ---- /vg trusts ----

local SLOT_BY_NAME = {}
for slot, n in pairs(pick.SLOT_NAMES) do SLOT_BY_NAME[n] = slot end

local function find(word)
  if not word then return nil end
  local list = M.called()
  local id = tonumber(word)
  for _, t in ipairs(list) do
    if t.id == id then return t end
  end
  local w = word:lower()
  for _, t in ipairs(list) do
    local nm = (info[t.id] and info[t.id].name or t.name or ""):lower()
    if nm == w or nm:find(w, 1, true) == 1 then return t end
  end
end

local function say(text) M.H.print("Trust gear: " .. text) end

local function describe(t)
  local i = info[t.id]
  local b = built[t.id]
  return string.format("%s (%s/%s %d)%s%s", t.name or "?", t.job, t.sub ~= "" and t.sub or "-", t.level,
    i and "" or ", not yours or not answered yet", b and (", " .. #b.plan .. " sets") or "")
end

function M.command(args)
  local cmd = (args[1] or ""):lower()
  local s = saved()
  if cmd == "off" or cmd == "on" then
    s.disabled = cmd == "off" or nil
    say(cmd == "off" and "off: nothing is sent to the server" or "on")
    return
  end
  if cmd == "window" then
    if M.window then M.window() end
    return
  end
  if cmd == "send" then
    local n = 0
    for _, t in ipairs(M.called()) do
      M.send(t, true)
      n = n + 1
    end
    say("sending every set of " .. n .. " trust" .. (n == 1 and "" or "s") .. " again")
    return
  end
  if cmd == "rebuild" then
    M.rebuild()
    say("building the sets again")
    return
  end
  if cmd == "use" then
    local t = find(args[2])
    local state = (args[3] or ""):lower()
    local action = table.concat(args, " ", 4)
    if not t or (state ~= "on" and state ~= "off") or action == "" then
      say("/vg trusts use <trust> <on|off> <action>")
      return
    end
    say(M.set_off(t, action, state == "off") and (action .. " " .. state .. " for " .. (t.name or "?"))
      or "that trust has not answered yet")
    return
  end
  if cmd == "set" then
    -- /vg trusts set <trust> <set> <slot> <item | remove | auto>
    local t, set_name, slot, item = find(args[2]), args[3], (args[4] or ""):lower(), table.concat(args, " ", 5)
    if not t or not set_name or not SLOT_BY_NAME[slot] or item == "" then
      say("/vg trusts set <trust> <set> <slot> <item | remove | auto>")
      return
    end
    local b = built[t.id]
    local entry
    for _, e in ipairs(b and b.plan or {}) do
      if e.key == M.key(set_name) then entry = e end
    end
    if not entry then say("no set " .. set_name .. " for " .. (t.name or "?")) return end
    s.own[t.name] = s.own[t.name] or {}
    s.own[t.name][entry.name] = s.own[t.name][entry.name] or {}
    s.own[t.name][entry.name][slot] = item:lower() ~= "auto" and item or nil
    M.rebuild()
    say(entry.name .. " " .. slot .. ": " .. (item:lower() == "auto" and "automatic" or item))
    return
  end
  local t = cmd ~= "" and find(cmd)
  if t then
    -- /vg trusts <trust> [<set>]
    local b = built[t.id]
    if not b then say(describe(t)) return end
    local want = args[2] and M.key(table.concat(args, " ", 2))
    if not want then
      say(describe(t))
      for _, e in ipairs(b.plan) do say("  " .. e.name .. ": " .. e.when) end
      return
    end
    for _, e in ipairs(b.plan) do
      if e.key == want then
        say(e.name .. " for " .. (t.name or "?"))
        for slot = 0, 15 do
          say(string.format("  %-9s %s", pick.SLOT_NAMES[slot], b.final[e.key][slot] or "-"))
        end
        return
      end
    end
    say("no set " .. table.concat(args, " ", 2))
    return
  end
  -- /vg trusts: who is out
  local list = M.called()
  say(s.disabled and "off (/vg trusts on)" or "on")
  if #list == 0 then say("no trusts in the party") end
  for _, t in ipairs(list) do say(describe(t)) end
  if #queue > 0 then say(#queue .. " line" .. (#queue == 1 and "" or "s") .. " waiting to be sent") end
end

-- Off by a command, or by the setting.
local enabled = M.H.enabled
M.H.enabled = function() return enabled() and not saved().disabled end

-- Dropped answers and echoes: a chat filter (set once per VM).
function M.install()
  filters.chat(function(text)
    local r = M.filter(text)
    if r == false then return false end
  end)
end

-- Test and debug access.
M.info = info
M.built = built
M.queue = queue

return M
