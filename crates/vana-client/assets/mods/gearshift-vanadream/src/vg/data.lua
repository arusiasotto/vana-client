-- vanagear's data, as its engine asks for it (vg/data.lua): the server's mods by name, set bonuses, latents, augments,
-- weaponskills and abilities. The tables are generated (data/build.lua); each is read the first time it is asked for.
-- Tests replace M.H.

local M = {}

M.H = {
  load = function(name) return require("data." .. name) end,
}

local cache = {}
local function load(name)
  if cache[name] == nil then
    local ok, t = pcall(M.H.load, name)
    cache[name] = ok and t or false
  end
  return cache[name] or {}
end

-- A slot's bit (slots 1 to 16, Main to Back): the server's slot mask.
M.SlotBit = {}
for s = 1, 16 do M.SlotBit[s] = 1 << (s - 1) end

local ids
function M.ModId(name)
  if not ids then
    ids = {}
    for id, n in pairs(load("mods")) do ids[n] = id end
  end
  return ids[name]
end

function M.ModName(id) return load("mods")[id] end
function M.Latents() return load("latents") end
function M.GearSets() return load("gearsets") end
function M.SlotBlocks() return load("slotblocks") end
function M.Augments() return load("augments") end
function M.Weaponskills() return load("weaponskills") end
function M.Abilities() return load("abilities") end
function M.Traits() return load("traits") end
function M.Gifts() return load("gifts") end

return M
