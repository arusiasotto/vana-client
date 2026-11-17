-- Pet and specialty job actions: engine routing picks the vanagear set names.

local vact = require("src.vg.actions")

local sets = { Reward = true, Charm = true, ReadyPrecast = true, Ready = true, Ready_Magic = true,
  PhantomRoll = true, QuickDraw = true, QuickDrawAcc = true, BPDelay = true, BPWard = true, PetMab = true,
  PetAcc = true, Call = true, Enmity = true }

local _, mid
_, mid = vact.job_ability({ name = "Reward", recast_id = 0 }, sets, {})
assert(mid == "Reward")
_, mid = vact.job_ability({ name = "Charm", recast_id = 0 }, sets, {})
assert(mid == "Charm")
_, mid = vact.job_ability({ name = "Call Beast", recast_id = 0 }, sets, {})
assert(mid == "Call")

local pre, mid = vact.job_ability({ name = "Foot Kick", recast_id = 102 }, sets, {})
assert(pre == "ReadyPrecast" and mid == "Ready", ("ready phys: %s %s"):format(tostring(pre), tostring(mid)))

pre, mid = vact.job_ability({ name = "Fireball", recast_id = 102 }, sets, {})
assert(pre == "ReadyPrecast" and mid == "Ready_Magic", ("ready mag: %s %s"):format(tostring(pre), tostring(mid)))

_, mid = vact.job_ability({ name = "Fighter's Roll", recast_id = 193 }, sets, {})
assert(mid == "PhantomRoll")

_, mid = vact.job_ability({ name = "Fire Shot", recast_id = 195 }, sets, { acc = false })
assert(mid == "QuickDraw")
_, mid = vact.job_ability({ name = "Fire Shot", recast_id = 195 }, sets, { acc = true })
assert(mid == "QuickDrawAcc")

assert(vact.summoning_mid("Fire II", "FireII", sets) == "PetMab")
assert(vact.summoning_mid("Sleepga", "Sleepga", sets) == "PetAcc")
assert(vact.summoning_mid("Shining Ruby", "ShiningRuby", sets) == "BPWard")
assert(vact.summoning_mid("Unknown Pact", "UnknownPact", sets) == "UnknownPact")

assert(vact.summoning_pre(sets) == "BPDelay")
assert(vact.summoning_pre({ Precast = true }) == "Precast")