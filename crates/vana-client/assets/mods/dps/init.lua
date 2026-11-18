-- /dps and the Damage Meter: the damage of us, the party (trusts included) and their pets since the first hit after a
-- reset, every damage number counted. Totals keep the damage of those who left; only the members with us get a row.

-- The colour of chat mode 0x8b, as the lines always had.
local COLOUR = {colour = 0x8b}

local by, first, last = {}, nil, nil

-- The name of us, a member of our party, or the pet of either (its master's index); nil for anyone else, and while
-- an actor is away (a dismissed trust, a despawned pet, a member gone from the party, a pet out of range).
local function current(actor)
  local me = game.player()
  if actor == me.id then
    return me.name
  end
  local members = game.party()
  for _, m in ipairs(members) do
    if m.party == 0 and m.id == actor then
      return m.name
    end
  end
  local e = game.entity(actor)
  if not e or e.master == 0 then
    return nil
  end
  if e.master == me.index then
    return e.name
  end
  for _, m in ipairs(members) do
    local pe = m.party == 0 and game.entity(m.id)
    if pe and pe.index == e.master then
      return e.name
    end
  end
  return nil
end

events.on("damage", function(actor, _, value)
  if value <= 0 then
    return
  end
  local name = current(actor)
  local e = by[actor]
  if not name and not e then
    return
  end
  local now = clock()
  first = first or now
  last = now
  e = e or {dmg = 0, hits = 0}
  e.name = name or e.name
  e.dmg = e.dmg + value
  e.hits = e.hits + 1
  by[actor] = e
end)

local function commas(n)
  local out = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

-- The rows of the members with us now, most damage first, and everyone's total.
local function rows()
  local total, out = 0, {}
  for id, v in pairs(by) do
    total = total + v.dmg
    if current(id) then
      out[#out + 1] = { name = v.name, dmg = v.dmg, hits = v.hits }
    end
  end
  table.sort(out, function(a, b) return a.dmg > b.dmg end)
  return out, total
end

-- The meter window: a row per member, its bar its share.
local function meter()
  if not settings.get("window") or not first then
    ui.close("meter")
    return
  end
  local list, total = rows()
  local secs = math.max(math.floor(last - first), 1)
  local els = {}
  for _, r in ipairs(list) do
    els[#els + 1] = { type = "gauge", style = "row", label = ("%s  %.1f/s"):format(r.name, r.dmg / secs),
      text = ("%s  %d%%"):format(commas(r.dmg), math.floor(r.dmg * 100 / math.max(total, 1) + 0.5)),
      value = r.dmg / math.max(total, 1) }
  end
  ui.window("meter", { edge = true, width = 300, title = "Damage",
    heading = ("Damage %d:%02d  %s"):format(secs // 60, secs % 60, commas(total)), elements = els })
  ui.open("meter")
end

timer.every(1, meter)
events.on("settings_changed", meter)

commands.register("dps", function(arg)
  if arg and arg:lower() == "reset" then
    by, first, last = {}, nil, nil
    chat.add("DPS: reset.", COLOUR)
    meter()
    return
  end
  if not first then
    chat.add("DPS: no damage yet.", COLOUR)
    return
  end
  local list, total = rows()
  local secs = math.max(math.floor(last - first), 1)
  chat.add(("DPS over %d:%02d: %d damage"):format(secs // 60, secs % 60, total), COLOUR)
  for _, r in ipairs(list) do
    chat.add(("  %s: %d (%.0f%%), %.1f/s, %d hits"):format(r.name, r.dmg, r.dmg * 100 / math.max(total, 1), r.dmg / secs, r.hits), COLOUR)
  end
end)
