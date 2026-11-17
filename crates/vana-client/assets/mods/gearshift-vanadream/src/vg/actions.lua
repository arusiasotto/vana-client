-- Specialty action routing (BST, COR, SMN, etc.) when the engine is on.

local lists = require("src.vg.lists")
local vplan = require("src.vg.plan")
local lac_types = require("src.names").LAC.ABILITY_TYPES

local M = {}

function M.have(name, job_sets)
  return name and job_sets[name] and name or nil
end

-- Summoning magic (blood pacts): the pact's own set when plan built one, else PetMab / PetAcc / BPWard.
function M.summoning_mid(spell_name, own_mid, job_sets)
  local n = spell_name or ""
  local h = M.have
  if lists.BPMagical[n] then return h("PetMab", job_sets) or own_mid end
  if lists.BPDebuff[n] then return h("PetAcc", job_sets) or own_mid end
  if lists.BPBuff[n] then return h("BPWard", job_sets) or own_mid end
  return own_mid
end

function M.summoning_pre(job_sets)
  return M.have("BPDelay", job_sets) or M.have("Precast", job_sets)
end

-- Job abilities and similar (category 7 and 9): { precast, midcast } set names.
function M.job_ability(a, job_sets, modes)
  if not a or not a.name then return nil, nil end
  local name = a.name
  local n = vplan.WsSetName(name)
  local h = M.have
  local rtype = a.recast_id and lac_types[a.recast_id]

  if rtype == "Ready" then
    local mid = lists.MagicReady[name] and h("Ready_Magic", job_sets) or h("Ready", job_sets)
    return h("ReadyPrecast", job_sets), mid
  end

  if rtype == "Blood Pact: Ward" then
    return h("BPDelay", job_sets), h("BPWard", job_sets)
  end
  if rtype == "Blood Pact: Rage" then
    return h("BPDelay", job_sets), h("PetAtk", job_sets)
  end

  if rtype == "Corsair Roll" or name:find(" Roll") or name:find("Roll$") then
    return nil, h("PhantomRoll", job_sets)
  end

  if rtype == "Quick Draw" or name:find(" Shot$") then
    return nil, (modes.acc and h("QuickDrawAcc", job_sets)) or h("QuickDraw", job_sets)
  end

  if name == "Reward" or name == "Charm" then
    return nil, h(name, job_sets) or h(n, job_sets)
  end
  if name == "Call Beast" or name == "Bestial Loyalty" then
    return nil, h("Call", job_sets) or h(n, job_sets)
  end

  if name:find("Waltz") then return nil, h(n, job_sets) end
  if name:find("Step") then return nil, h(n, job_sets) end
  if name == "Provoke" or name == "Sentinel" or name == "Animated Flourish" then
    return nil, h("Enmity", job_sets)
  end
  if name == "Steal" or name == "Despoil" then return nil, h(n, job_sets) end

  return nil, h(n, job_sets) or h("Enmity", job_sets)
end

return M