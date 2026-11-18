-- Which actions draw a line, in which colour, and the lines and AoE rings still showing.

local M = {}

local DUPLICATE_FINISH = 5.0

local SPECIAL = { [3] = true, [4] = true, [6] = true, [7] = true, [8] = true, [10] = true, [11] = true,
  [13] = true, [14] = true, [15] = true }
local REGULAR = { [1] = true, [2] = true }
local AOE = { [3] = true, [4] = true, [6] = true, [11] = true, [13] = true, [14] = true, [15] = true }
local RA = { Stone = true, Water = true, Aero = true, Fire = true, Blizz = true, Thunder = true }

local COLOURS = {
  player = 0xF040F0FF,
  friendly = 0xF088FF9A,
  enemy = 0xF0FF4A55,
  hostile_support = 0xF0FF22F0,
  npc = 0xE800E8FF,
}
local CB_COLOURS = {
  player = 0xF056B4E9,
  friendly = 0xF0F0E442,
  enemy = 0xF0D55E00,
  hostile_support = 0xF0CC79A7,
  npc = 0xE856B4E9,
}

local recent_lines = {}
local recent_rings = {}
local seen_pairs = {}
local recent_spell = {}
local recent_ability = {}
local recent_casts = {}
local line_seq = 0

function M.colour(kind)
  local tab = settings.get("color_blind") and CB_COLOURS or COLOURS
  local argb = tab[kind]
  return { (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, (argb >> 24) & 0xFF }
end

local function entity(id)
  local e = id and id ~= 0 and game.entity(id)
  if not e or not e.pos then return nil end
  if e.kind == "mob" and e.hpp ~= nil and e.hpp <= 0 then return nil end
  return e
end

-- Our party and alliance by id and index, and their pets ("pet:" id, "pi:" index).
local function party_map()
  local me = game.player()
  if not me then return { _player = 0 } end
  local map = { _player = me.id }
  local masters = { [me.index] = true }
  for _, m in ipairs(game.party() or {}) do
    map[m.id] = true
    if m.index then
      map["i:" .. m.index] = true
      masters[m.index] = true
    end
  end
  for _, e in ipairs(game.entities({ distance = 50 }) or {}) do
    if e.master and masters[e.master] then
      map["pet:" .. e.id] = true
      map["pi:" .. e.index] = true
    end
  end
  return map
end

local function in_party(e, party)
  return e.id == party._player or party[e.id] or party["i:" .. e.index]
    or party["pet:" .. e.id] or party["pi:" .. e.index]
end

local function classify(source, target, party)
  local sp, tp = in_party(source, party), in_party(target, party)
  if sp and tp then return "friendly" end
  if sp or source.kind == "player" then return "player" end
  if tp then return "enemy" end
  if target.kind ~= "player" then return "hostile_support" end
  return "npc"
end

local function source_role(source, party)
  if source.id == party._player then return "player" end
  if party["pet:" .. source.id] then return "pet" end
  if in_party(source, party) then return "party" end
  if source.kind ~= "player" then return "enemy" end
  return "player"
end

local ROLE_SETTING = { player = "player_lines", party = "party_lines", pet = "pet_lines", enemy = "enemy_lines" }

local function line_ok(source, target, party)
  if not settings.get("other_party_lines") and not in_party(source, party) and not in_party(target, party) then
    return false
  end
  return settings.get(ROLE_SETTING[source_role(source, party)]) ~= false
end

-- A started action's id is in its first result's value; a finished one's in param.
local function action_id(cat, a, tgt)
  local r = tgt and tgt.results and tgt.results[1]
  if cat == 7 or cat == 8 then return (r and r.value) or a.param or 0 end
  return a.param or (r and r.value) or 0
end

local function cast_family(cat)
  if cat == 4 or cat == 8 then return "spell" end
  if cat == 3 or cat == 7 or cat == 11 then return "ability" end
end

local function caster_centered_spell(id)
  local s = res.spell(id)
  local name = s and s.name or ""
  return name:match("^Protectra") or name:match("^Shellra") or name:match("^Bar.+ra$")
    or name:match("^Indi%-") or name:match("^Boost%-") or name:match("^Gain%-")
    or RA[name:match("^(%a+)ra") or ""] or false
end

local function aoe_center(cat, aid, source, primary)
  if not primary or source.id == primary.id then return source end
  if cat == 4 and caster_centered_spell(aid) then return source end
  if cat == 6 or cat == 11 or cat == 13 or cat == 14 or cat == 15 then return source end
  return primary
end

local function add_line(source, target, kind, special)
  if source.id == target.id then return end
  local pair = source.id .. ">" .. target.id
  local now = os.clock()
  if not special then
    local mode = settings.get("regular_attacks")
    local seen = seen_pairs[pair]
    if mode == "first" and seen then return end
    if mode == "repeat" and seen and now - seen.at < settings.get("pair_cooldown") then return end
    seen_pairs[pair] = { at = now, source = source.id, target = target.id }
  end
  line_seq = line_seq + 1
  local key = special and (pair .. "#" .. line_seq) or pair
  recent_lines[key] = {
    source = source, target = target, colour = M.colour(kind),
    created = now, timeout = settings.get("fade"), uid = line_seq,
  }
  return key
end

local function add_ring(center, targets, colour)
  local radius = 0
  for _, t in ipairs(targets) do
    local dx, dz = t.pos.x - center.pos.x, t.pos.z - center.pos.z
    radius = math.max(radius, math.sqrt(dx * dx + dz * dz))
  end
  if radius < 0.1 then return end
  line_seq = line_seq + 1
  recent_rings[center.id .. "#ring#" .. line_seq] = {
    center = center, targets = targets, radius = radius, colour = colour,
    created = os.clock(), timeout = settings.get("fade"), uid = line_seq,
  }
end

function M.on_action(a)
  if not settings.get("on") then return end
  local cat = a.category or 0
  local special = SPECIAL[cat] == true
  if special and not settings.get("special_lines") then return end
  if not special and not (REGULAR[cat] and settings.get("regular_attacks") ~= "off") then return end
  local source = entity(a.actor)
  if not source then return end
  local party = party_map()
  local targets = a.targets or {}
  local aoe = #targets > 1 and AOE[cat] == true
  local mode = settings.get("aoe_mode")
  if aoe and mode == "off" then return end

  local aid = action_id(cat, a, targets[1])
  local family = cast_family(cat)
  local now = os.clock()
  local cast_key = family and (family .. ":" .. source.id .. ":" .. aid)
  local cast = cast_key and recent_casts[cast_key]
  if cat == 7 or cat == 8 then
    cast = { created = now }
    recent_casts[cast_key] = cast
  elseif cast and now - cast.created > DUPLICATE_FINISH then
    cast = nil
  end
  if aoe and cast and cast.line_key then recent_lines[cast.line_key] = nil end

  local ring_targets, ring_colour = {}, nil
  for _, t in ipairs(targets) do
    local target = entity(t.id)
    local pair = target and source.id .. ">" .. target.id
    if target and (cat == 4 or cat == 8) then
      local sk = pair .. ":" .. action_id(cat, a, t)
      if not aoe and recent_spell[sk] and now - recent_spell[sk] <= DUPLICATE_FINISH then target = nil end
      recent_spell[sk] = now
    elseif target and not aoe and (cat == 3 or cat == 11) and recent_ability[pair]
      and now - recent_ability[pair] <= DUPLICATE_FINISH then
      target = nil
    end
    if target and line_ok(source, target, party) then
      local kind = classify(source, target, party)
      if aoe and mode ~= "fan" then
        ring_targets[#ring_targets + 1] = target
        ring_colour = ring_colour or M.colour(kind)
      else
        local key = add_line(source, target, kind, special)
        if cast and (cat == 7 or cat == 8) and key then cast.line_key = key end
      end
      if cat == 7 then recent_ability[pair] = now end
    end
  end

  if #ring_targets > 0 then
    add_ring(aoe_center(cat, aid, source, entity(targets[1].id)), ring_targets, ring_colour)
  end
  if cast_key and (cat == 3 or cat == 4 or cat == 11) then recent_casts[cast_key] = nil end
end

-- y points down: the anchor is above the feet, in the torso band.
function M.anchor(ent, which)
  local scale = settings.get(which == "source" and "source_height" or "target_height")
  local lift = math.max(0.35, (ent.height or 1.8) * 0.55 * scale)
  return { x = ent.pos.x, y = ent.pos.y - lift, z = ent.pos.z }
end

function M.count()
  local n = 0
  for _ in pairs(recent_lines) do n = n + 1 end
  return n
end

local PRUNE_SECS = 1
local pruned_at = 0

-- A pair goes once either side is gone or dead, so a respawned mob gets its first line again.
local function prune(now)
  if now - pruned_at < PRUNE_SECS then return end
  pruned_at = now
  local cooldown = settings.get("regular_attacks") == "repeat" and settings.get("pair_cooldown")
  for k, seen in pairs(seen_pairs) do
    if (cooldown and now - seen.at >= cooldown) or not entity(seen.source) or not entity(seen.target) then
      seen_pairs[k] = nil
    end
  end
  for _, t in ipairs({ recent_spell, recent_ability }) do
    for k, at in pairs(t) do
      if now - at > DUPLICATE_FINISH then t[k] = nil end
    end
  end
  for k, cast in pairs(recent_casts) do
    if now - cast.created > DUPLICATE_FINISH then recent_casts[k] = nil end
  end
end

function M.collect()
  local now = os.clock()
  prune(now)
  local lines, rings = {}, {}
  for k, line in pairs(recent_lines) do
    if now - line.created > line.timeout then recent_lines[k] = nil else lines[#lines + 1] = line end
  end
  for k, ring in pairs(recent_rings) do
    if now - ring.created > ring.timeout + 1 then recent_rings[k] = nil else rings[#rings + 1] = ring end
  end
  table.sort(lines, function(a, b) return a.created > b.created end)
  return lines, rings
end

function M.clear()
  recent_lines, recent_rings, seen_pairs = {}, {}, {}
  recent_spell, recent_ability, recent_casts = {}, {}, {}
end

return M
