-- What each set values: the parts of vanagear's vg/plan.lua the trusts use, as it has them. A mode is roles.lua's
-- weights and caps (src/vg/roles.lua) with the job file's tweaks laid over it, stat by stat (data/jobs/<JOB>.lua, and
-- the band of the job's level). The player's own sets keep to the gearshift builder.

local roles = require("src.vg.roles")

local M = {}

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
  if jobs[abbr] == nil then
    local ok, job = pcall(require, "data.jobs." .. tostring(abbr))
    jobs[abbr] = ok and type(job) == "table" and job or { Fighter = true }
  end
  return jobs[abbr]
end

-- A job file's Bands are level ranges, each with its own Tweaks and Modes: { To = 30, Tweaks = {...} } in rising
-- order. The band the level falls in is laid over the job's all-level Tweaks, so a 70s character is not scored by
-- what a 99 wants.
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

return M
