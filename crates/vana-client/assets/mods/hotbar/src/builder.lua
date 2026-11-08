-- What the macro builder offers: the actions of each type you can use now, found by name, and the targets (or, to
-- equip, the slots) a built line can name.

local M = {}

-- Builder types, in the order the editor offers them; `kind` is the action's (nil: a macro of typed lines only).
M.TYPES = {
  { kind = "ma", label = "Spell", search = "Search your spells", column = "Spell" },
  { kind = "ja", label = "Job ability", search = "Search your job abilities", column = "Ability" },
  { kind = "ws", label = "Weapon skill", search = "Search your weapon skills", column = "Weapon skill" },
  { kind = "pet", label = "Pet command", search = "Search your pet commands", column = "Command" },
  { kind = "item", label = "Item", search = "Search your usable items", column = "Item" },
  { kind = "equip", label = "Equip", search = "Search your equipment", column = "Equipment" },
  { kind = "cmd", label = "Command", search = "Search the commands", column = "Command" },
  { kind = nil, label = "Macro", search = "(not used for a macro: type its lines)", column = "" },
}

-- Game icons that stand in for the commands: an item's, a status effect's or a spell's.
local ITEM_ICON = function(id) return { kind = "item", id = id } end
local STATUS_ICON = function(id) return { kind = "status", id = id } end

-- The common system commands, as typed (arguments included), with the target each starts on (nil: it takes none)
-- and the icon a slot shows for it (none for some).
M.COMMANDS = {
  { line = "/attack", title = "Attack", target = "t", does = "Engage the target, or switch to it",
    icon = ITEM_ICON(16535) },                                          -- Bronze Sword
  { line = "/attackoff", title = "Disengage", does = "Stop attacking", icon = ITEM_ICON(12289) }, -- Lauan Shield
  { line = "/ra", title = "Ranged attack", target = "t", does = "Shoot or throw at the target",
    icon = ITEM_ICON(17152) },                                          -- Shortbow
  { line = "/assist", title = "Assist", target = "t", does = "Target what they are targeting",
    icon = ITEM_ICON(515) },                                            -- Linkpearl
  { line = "/target", title = "Target", target = "stnpc", does = "Pick a target", icon = STATUS_ICON(58) }, -- Aggressor
  { line = "/targetbnpc", title = "Nearest enemy", does = "Target the nearest enemy", icon = STATUS_ICON(58) },
  { line = "/targetnpc", title = "Nearest NPC", does = "Target the nearest NPC" },
  { line = "/lockon", title = "Lock on", does = "Lock on to the target, or let go", icon = STATUS_ICON(11) }, -- Bind
  { line = "/check", title = "Check", target = "t", does = "Check the target", icon = STATUS_ICON(59) }, -- Focus
  { line = "/follow", title = "Follow", target = "t", does = "Follow the target", icon = STATUS_ICON(71) }, -- Sneak
  { line = "/heal", title = "Heal", does = "Rest, or stop resting", icon = STATUS_ICON(42) },     -- Regen
  { line = "/sit", title = "Sit", does = "Sit down, or stand" },
  { line = "/dismount", title = "Dismount", does = "Get off your mount", icon = ITEM_ICON(15533) }, -- Chocobo Whistle
  { line = "/refa all", title = "Release trusts", does = "Release all your trusts",
    icon = { kind = "spell", id = 896 } },                              -- a trust's (Shantotto)
  { line = "/lockstyle on", title = "Lockstyle", does = "Lock your look to what you wear" },
  { line = "/wait 1", title = "Wait", does = "Wait a second before the next line" },
}

local NO_TARGET = { { "", "(none)" } }

-- A command of M.COMMANDS by its line.
function M.command(line)
  for _, c in ipairs(M.COMMANDS) do
    if c.line == line then return c end
  end
  return nil
end

M.TYPE_LABELS = {}
for i, t in ipairs(M.TYPES) do
  M.TYPE_LABELS[i] = t.label
end

function M.type_index(kind)
  for i, t in ipairs(M.TYPES) do
    if t.kind == kind then return i end
  end
  return #M.TYPES
end

M.TARGETS = {
  { "t", "<t> Current target" },
  { "me", "<me> Yourself" },
  { "bt", "<bt> Battle target" },
  { "stpc", "<stpc> Pick a player" },
  { "stpt", "<stpt> Pick a party member" },
  { "stal", "<stal> Pick an alliance member" },
  { "stnpc", "<stnpc> Pick an NPC or enemy" },
  { "st", "<st> Pick anyone" },
  { "lastst", "<lastst> Last picked" },
  { "p1", "<p1> Party member 2" },
  { "p2", "<p2> Party member 3" },
  { "p3", "<p3> Party member 4" },
  { "p4", "<p4> Party member 5" },
  { "p5", "<p5> Party member 6" },
}

-- Equipment slots by bit (res.item's `slots`), with the names /equip takes.
M.EQUIP_SLOTS = {
  { "main", "Main" }, { "sub", "Sub" }, { "range", "Range" }, { "ammo", "Ammo" }, { "head", "Head" },
  { "body", "Body" }, { "hands", "Hands" }, { "legs", "Legs" }, { "feet", "Feet" }, { "neck", "Neck" },
  { "waist", "Waist" }, { "ear1", "Left ear" }, { "ear2", "Right ear" }, { "ring1", "Left ring" },
  { "ring2", "Right ring" }, { "back", "Back" },
}

-- The choices of the target menu for an action kind (and, for a command, the one picked): { {value, label}, ... }.
-- A command that takes no target has only "(none)" (value "").
function M.targets_for(kind, name)
  if kind == "equip" then return M.EQUIP_SLOTS end
  if kind == "cmd" then
    local c = name and M.command(name)
    if c and not c.target then return NO_TARGET end
  end
  return M.TARGETS
end

-- The label of a target value for an action kind.
function M.target_label(kind, value, name)
  for _, t in ipairs(M.targets_for(kind, name)) do
    if t[1] == value then return t[2] end
  end
  return value and value ~= "" and ("<" .. value .. ">") or "(none)"
end

local SPELL_KINDS = { "White", "Black", "Summoning", "Ninjutsu", "Song", "Blue", "Geomancy", "Trust" }

-- A target from valid-target bits (spells and items): an enemy for one that can hit enemies, yourself for one that
-- only takes you, else a player.
function M.default_target(targets)
  local t = targets or 0
  if t & 0x20 ~= 0 then return "t" end
  if t & ~1 == 0 then return "me" end
  return "stpc"
end

-- The first slot an item fits, by its `slots` bits.
local function first_slot(bits)
  for n = 0, 15 do
    if bits & (1 << n) ~= 0 then return M.EQUIP_SLOTS[n + 1][1] end
  end
  return "main"
end

local ABILITY_KIND = { ja = 1, pet = 2, ws = 3 }
local DEFAULT_TARGET = { ja = "me", pet = "t", ws = "t" }

-- Every choice of an action kind: { { name, cells = {...}, icon = {kind, id}, target, title? }, ... } where `target`
-- is the one a new pick starts on and `title` the macro name it suggests (else `name`).
local function all_of(kind)
  local out = {}
  if kind == "cmd" then
    -- In the list's order, not by name: the common ones first.
    for _, c in ipairs(M.COMMANDS) do
      out[#out + 1] = { name = c.line, title = c.title, target = c.target or "", icon = c.icon,
        cells = { c.target and ("<" .. c.target .. ">") or "", c.does }, search = c.title .. " " .. c.does }
    end
    return out
  elseif kind == "ma" then
    for _, id in ipairs(game.spells()) do
      local s = res.spell(id)
      if s and s.name and s.name ~= "" then
        out[#out + 1] = { name = s.name, cells = { tostring(s.mp or 0), SPELL_KINDS[s.kind] or "" },
          icon = { kind = "spell", id = id }, target = M.default_target(s.targets) }
      end
    end
  elseif ABILITY_KIND[kind] then
    local seen = {}
    for _, id in ipairs(game.abilities()) do
      local a = res.ability(id)
      if a and a.kind == ABILITY_KIND[kind] and a.name and a.name ~= "" and not seen[a.name] then
        seen[a.name] = true
        local cost = (a.cost or 0) > 0 and tostring(a.cost) or ""
        local recast = a.recast and ("%ds"):format(a.recast) or ""
        out[#out + 1] = { name = a.name, cells = { cost, recast }, icon = { kind = "ability", id = id },
          target = DEFAULT_TARGET[kind] }
      end
    end
  elseif kind == "item" or kind == "equip" then
    -- Usable items from the inventory and the temporary items; equipment from the inventory and the wardrobes.
    local bags = kind == "item" and { 0, 3 } or { 0, 8, 10, 11, 12, 13, 14, 15, 16 }
    local by_id = {}
    for _, bag in ipairs(bags) do
      for _, it in ipairs(game.items(bag)) do
        local r = it.id and res.item(it.id)
        local fits = r and (kind == "equip" and (r.slots or 0) ~= 0 or kind == "item" and r.kind == "usable")
        if fits and r.name and r.name ~= "" then
          local e = by_id[it.id]
          if not e then
            e = { name = r.name, count = 0, icon = { kind = "item", id = it.id },
              target = kind == "equip" and first_slot(r.slots) or M.default_target(r.targets) }
            by_id[it.id] = e
            out[#out + 1] = e
          end
          e.count = e.count + (it.count or 1)
        end
      end
    end
    for _, e in ipairs(out) do
      e.cells = { tostring(e.count), kind == "equip" and M.target_label("equip", e.target) or "" }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

M.MAX_RESULTS = 150

-- The choices of an action kind whose names hold `query` (any case), by name; `more` is true when there were more
-- than MAX_RESULTS.
function M.find(kind, query)
  local q = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local found = {}
  for _, e in ipairs(all_of(kind)) do
    if q == "" or e.name:lower():find(q, 1, true) or (e.search and e.search:lower():find(q, 1, true)) then
      found[#found + 1] = e
    end
  end
  local more = #found > M.MAX_RESULTS
  while #found > M.MAX_RESULTS do
    found[#found] = nil
  end
  return found, more
end

-- The column headings of the results list for an action kind.
function M.columns(kind)
  local t = M.TYPES[M.type_index(kind)]
  local second, third = "", ""
  if kind == "ma" then
    second, third = "MP", "Type"
  elseif ABILITY_KIND[kind] then
    second, third = "Cost", "Recast"
  elseif kind == "item" then
    second = "Held"
  elseif kind == "equip" then
    second, third = "Held", "Slot"
  elseif kind == "cmd" then
    return { { title = t.column }, { title = "Target", width = 60 }, { title = "What it does", width = 230 } }
  end
  return { { title = t.column }, { title = second, width = 50, align = "right" }, { title = third, width = 90 } }
end

return M
