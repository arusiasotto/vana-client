-- Gearshift's set builder reads stats from every armour and weapon description in the game's files: at least 99%
-- of them with no phrase it does not know (the rest are listed when it fails).

local items = TEST.game_items()
if not items then return end -- the game's files are not installed here
local S = require("src.build.stats")
local clean, unknown = 0, {}
for _, it in ipairs(items) do
  local r = S.parse(it.description)
  if next(r.unknown) == nil then clean = clean + 1 end
  for k, n in pairs(r.unknown) do unknown[k] = (unknown[k] or 0) + n end
end
local list = {}
for k, n in pairs(unknown) do list[#list + 1] = n .. " " .. k end
table.sort(list)
assert(#items > 15000, #items .. " equipment records")
assert(clean * 100 >= #items * 99, clean .. " of " .. #items .. " read fully; unknown:\n" .. table.concat(list, "\n"))
