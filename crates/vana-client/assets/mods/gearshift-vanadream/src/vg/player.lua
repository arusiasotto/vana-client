-- Your own sets, built by vanagear's plan.For and score engine. Each set is a roles.lua mode (job tweaks and the band
-- of your level, caps lowered by traits and gifts), scored over every piece you carry. Weapons and ammo are never
-- chosen by scoring: swapping them resets TP; only hand picks and /vg weapon fill those slots.

local vplan = require("src.vg.plan")
local score = require("src.vg.score")
local pieces_of = require("src.vg.pieces")
local pick = require("src.build.pick")
local core = require("src.core")

local M = {}

M.H = {
  zone = function()
    local ok, info = pcall(function() return game.info() end)
    return ok and info and info.zone or 0
  end,
  job_points = function(job_id)
    local ok, t = pcall(function() return game.job_points() end)
    local j = ok and t and t[job_id]
    return j and j.spent or 0
  end,
}

-- The plan for the player right now: list of { Name, Mode, Slots, ... }, cached until the signature changes.
local cache = { sig = nil, list = nil, by = nil }

local function equipment()
  local worn = core.worn()
  local out = {}
  for slot, name in pairs({ [0] = "Main", [1] = "Sub", [2] = "Range", [3] = "Ammo" }) do
    local w = worn[slot]
    if w and w.id then out[name] = { Id = w.id } end
  end
  return out
end

local function who_of(ctx)
  local p = ctx.player or {}
  return {
    Job = ctx.job_id, JobName = ctx.job, Level = ctx.level,
    Sub = ctx.sub_id or 0, SubName = (ctx.sub_id and ctx.sub_id > 0 and (res.job(ctx.sub_id) or "")) or "",
    SubLevel = p.sub_level or 0, Race = ctx.race or 0,
    JobPoints = M.H.job_points(ctx.job_id), Zone = M.H.zone(),
  }
end

local function signature(ctx)
  local eq = equipment()
  local locks = {}
  for slot in pairs(ctx.locked or {}) do locks[#locks + 1] = slot end
  table.sort(locks)
  return table.concat({
    ctx.job or "", ctx.job_id or 0, ctx.level or 0, ctx.sub_id or 0, (ctx.player and ctx.player.sub_level) or 0,
    eq.Main and eq.Main.Id or 0, eq.Sub and eq.Sub.Id or 0, eq.Range and eq.Range.Id or 0,
    table.concat(locks, ","),
  }, "|")
end

-- The sets plan.For builds for you right now, and a lookup by name.
function M.plan(ctx)
  local sig = signature(ctx)
  if cache.sig == sig and cache.list then return cache.list, cache.by end
  local locked = {}
  for slot in pairs(ctx.locked or {}) do locked[slot + 1] = true end   -- plan.For uses 1..16
  local list = vplan.For(who_of(ctx), equipment(), { Locked = locked })
  local by = {}
  for _, o in ipairs(list) do by[o.Name] = o end
  cache = { sig = sig, list = list, by = by }
  return list, by
end

function M.forget()
  cache = { sig = nil, list = nil, by = nil }
end

-- The names of the sets to build, in plan.For's order.
function M.names(ctx)
  local list = M.plan(ctx)
  local out = {}
  for _, o in ipairs(list) do out[#out + 1] = o.Name end
  return out
end

function M.has(name, ctx)
  local _, by = M.plan(ctx)
  return by[name] ~= nil
end

-- Builds one set. Returns the builder's result shape: {slots, score, engine, mode}, or nil when plan.For has no set
-- by that name (or the set is empty-by-design).
function M.build(name, ctx)
  local _, by = M.plan(ctx)
  local entry = by[name]
  if not entry or not entry.Mode or entry.Empty then return nil end
  if not entry.Mode.Stats or next(entry.Mode.Stats) == nil then
    -- A scored set needs weights; an empty Stats table means nothing to dress for.
    if not entry.Mode.Pet then return { slots = {}, score = 0, engine = true, mode = entry.Mode } end
  end
  local pieces = {}
  for _, o in ipairs(ctx.owned) do
    local piece = pieces_of.of(o)
    if piece then pieces[#pieces + 1] = piece end
  end
  local set, _, total = score.Build(score.Compile(entry.Mode), pieces, who_of(ctx), entry.Slots, { 0 }, true)
  local out = { slots = {}, score = total, engine = true, mode = entry.Mode }
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

-- What one piece is worth in a slot of a set (0 to 15) by the engine's weights.
local rated = {}
function M.rate(name, ctx, o, slot)
  local key = table.concat({ name, signature(ctx) }, "|")
  local compiled = rated[key]
  if compiled == nil then
    local _, by = M.plan(ctx)
    local entry = by[name]
    compiled = entry and entry.Mode and score.Compile(entry.Mode) or false
    if compiled then compiled.Who = who_of(ctx) end
    rated = { [key] = compiled }
  end
  if not compiled then return nil end
  local piece = pieces_of.of(o)
  if not piece then return 0 end
  local rate = 0
  for k, v in pairs(score.Vector(piece, slot + 1, compiled, { 0 })) do rate = rate + (compiled.w[k] or 0) * v end
  return rate
end

-- A catalogue-shaped def for the window (label / when), from a plan entry.
function M.def(name, ctx)
  local _, by = M.plan(ctx)
  local entry = by[name]
  if not entry then return nil end
  local when = entry.Ability and ("ability: " .. entry.Ability)
    or entry.Weaponskill and ("weapon skill: " .. entry.Weaponskill)
    or entry.Spell and ("spell: " .. entry.Spell)
    or entry.Empty and "yours to fill"
    or "vanagear's " .. name
  return { label = name, when = when, weights = {}, engine = true }
end

return M
