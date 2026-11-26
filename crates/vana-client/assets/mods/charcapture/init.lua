-- Character snapshot for porting to Vanadreams (vanadreams-launcher addons/charcapture).
-- //capture writes shared/charcapture/<Name>.json (mod-data/.shared/charcapture/).

local VERSION = "0.1.10"
local currencies = require("data.currencies")
local JOB_COUNT = 22
local PUP_JOB = 18
local CONTAINERS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
local STORAGE_NAME = {
  [0] = "Inventory", [1] = "Mog Safe", [2] = "Storage", [3] = "Temporary Items", [4] = "Mog Locker",
  [5] = "Mog Satchel", [6] = "Mog Sack", [7] = "Mog Case", [8] = "Mog Wardrobe", [9] = "Mog Safe 2",
  [10] = "Mog Wardrobe 2", [11] = "Mog Wardrobe 3", [12] = "Mog Wardrobe 4", [13] = "Mog Wardrobe 5",
  [14] = "Mog Wardrobe 6", [15] = "Mog Wardrobe 7", [16] = "Mog Wardrobe 8",
}
local EQUIP_SLOTS = 16

local last_summary = nil
local seen = {
  chocobo = nil, chocobo_at = nil,
  merits = {}, merits_at = nil,
  job_points = {}, job_points_at = nil,
  logs = {}, logs_at = nil,
  currencies = {},
  currencies1_at = nil, currencies2_at = nil,
  skills_by_job = {}, skills_due = nil,
  automaton = nil, automaton_at = nil,
}
currencies._store = seen

local function hex(s)
  if not s or s == "" then return "" end
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function say(msg)
  chat.add("[Character Capture] " .. msg, { colour = 0x8b })
end

local function my_id()
  local me = game.player()
  return me and me.id or 0
end

local function server_name()
  local ok, info = pcall(game.info)
  if ok and type(info) == "table" and info.server and info.server ~= "" then
    return info.server
  end
  return "retail"
end

local function ashita_skill_index(id, kind)
  if kind == "craft" then return id - 48 end
  if kind == "magic" then return id end
  return id - 1
end

local function snapshot_skills()
  local sk = game.skills()
  if not sk then return nil end
  local me = game.player()
  if not me or not me.main_job or me.main_job == 0 then return nil end
  local combat = {}
  for id, s in pairs(sk.combat or {}) do
    local k = ashita_skill_index(tonumber(id), "combat")
    combat[tostring(k)] = { skill = s.level, capped = s.capped }
  end
  for id, s in pairs(sk.magic or {}) do
    local k = ashita_skill_index(tonumber(id), "magic")
    combat[tostring(k)] = { skill = s.level, capped = s.capped }
  end
  return {
    main = me.main_job,
    main_level = me.main_level,
    sub = me.sub_job or 0,
    sub_level = me.sub_level or 0,
    combat = combat,
  }
end

local function remember_skills()
  local r = snapshot_skills()
  if not r then return end
  local key = ("%d/%d"):format(r.main, r.sub or 0)
  seen.skills_by_job[key] = r
end

local function read_log(data)
  if #data < 0x28 then return end
  local port = string.unpack("<I2", data, 0x25)
  seen.logs[string.format("%04x", port)] = hex(data:sub(5, 36))
  seen.logs_at = os.time()
end

local function read_merits(data)
  local count = string.unpack("<I2", data, 0x05)
  if not count or count > 61 then return end
  for i = 0, count - 1 do
    local base = 0x09 + i * 4
    local id, _, upgrades = string.unpack("<I2BB", data, base)
    if id and id > 0 and upgrades and upgrades > 0 then
      seen.merits[tostring(id)] = upgrades
    end
  end
  seen.merits_at = os.time()
end

local function read_job_points_packet(data)
  for i = 0, 63 do
    local base = 0x05 + i * 4
    local a, b = string.unpack("<I2", data, base), string.unpack("<I2", data, base + 2)
    if not a or a == 0 then break end
    local index, job = a & 0x1F, a >> 5
    local level = b >> 10
    if job > 0 and level > 0 then
      local jk = tostring(job)
      seen.job_points[jk] = seen.job_points[jk] or {}
      seen.job_points[jk][tostring(index)] = level
    end
  end
  seen.job_points_at = os.time()
end

local function read_chocobo_sync(data)
  if #data < 0x1C or data:byte(0x05) ~= 0x02 then return end
  if string.unpack("<I4", data, 0x09) ~= my_id() then return end
  local props = string.unpack("<I4", data, 0x19)
  if props and props ~= 0 then
    seen.chocobo = props
    seen.chocobo_at = os.time()
  end
end

local function read_chocobo_update(data)
  if #data < 0x38 or string.unpack("<I4", data, 0x05) ~= my_id() then return end
  if ((data:byte(0x21) >> 5) & 0x07) ~= 2 then return end
  local props = string.unpack("<I4", data, 0x35)
  if props and props ~= 0 then
    seen.chocobo = props
    seen.chocobo_at = os.time()
  end
end

local function read_automaton(data)
  if #data < 0x68 then return end
  if data:byte(0x05) ~= PUP_JOB then return end
  local a = {
    head = data:byte(0x09),
    frame = data:byte(0x0A),
    attachments = {},
    unlocked_attachments = {},
  }
  for i = 0, 11 do a.attachments[#a.attachments + 1] = data:byte(0x0B + i) end
  a.unlocked_heads = string.unpack("<I4", data, 0x19)
  a.unlocked_frames = string.unpack("<I4", data, 0x1D)
  for i = 0, 7 do a.unlocked_attachments[#a.unlocked_attachments + 1] = string.unpack("<I4", data, 0x39 + i * 4) end
  a.name = (data:sub(0x59, 0x68):gsub("%z.*", ""))
  seen.automaton = a
  seen.automaton_at = os.time()
end

packets.on_in(0x056, function(p) pcall(read_log, p.data) end)
packets.on_in(0x067, function(p) pcall(read_chocobo_sync, p.data) end)
packets.on_in(0x00D, function(p) pcall(read_chocobo_update, p.data) end)
packets.on_in(0x044, function(p) pcall(read_automaton, p.data) end)
packets.on_in(0x08C, function(p) pcall(read_merits, p.data) end)
packets.on_in(0x08D, function(p) pcall(read_job_points_packet, p.data) end)
packets.on_in(0x113, function(p) pcall(currencies.read_currencies_1, p.data) end)
packets.on_in(0x118, function(p) pcall(currencies.read_currencies_2, p.data) end)
packets.on_in(0x062, function()
  seen.skills_due = clock() + 2
end)

events.on("job_change", remember_skills)
events.on("login", function()
  timer.after(2, remember_skills)
end)
timer.every(0.5, function()
  if seen.skills_due and clock() >= seen.skills_due then
    seen.skills_due = nil
    remember_skills()
  end
end)

local function merit_upgrades_from_game()
  local merits = game.merits()
  if not merits then return nil end
  local out = {}
  local any = false
  for id, m in pairs(merits) do
    if m.level and m.level > 0 then
      out[tostring(id)] = m.level
      any = true
    end
  end
  return any and out or nil
end

local function job_point_upgrades_from_game()
  local jps = game.job_points()
  if not jps then return nil end
  local out = {}
  local any = false
  for job, row in pairs(jps) do
    if type(row) == "table" and row.upgrades then
      local j = {}
      for eid, level in pairs(row.upgrades) do
        local index = tonumber(eid) & 0x1F
        if level and level > 0 then
          j[tostring(index)] = level
          any = true
        end
      end
      if next(j) then out[tostring(job)] = j end
    end
  end
  return any and out or nil
end

local function known_abilities()
  local spells, abilities, weaponskills, traits = {}, {}, {}, {}
  for _, id in ipairs(game.spells()) do spells[#spells + 1] = id end
  for _, id in ipairs(game.abilities()) do
    local a = res.ability(id)
    local kind = type(a) == "table" and a.kind
    if kind == 3 then
      weaponskills[#weaponskills + 1] = id
    elseif kind == 4 then
      traits[#traits + 1] = id
    elseif kind == 2 or id >= 0x400 then
      abilities[#abilities + 1] = id
    elseif id < 0x200 then
      weaponskills[#weaponskills + 1] = id
    else
      abilities[#abilities + 1] = id
    end
  end
  table.sort(spells)
  table.sort(abilities)
  table.sort(weaponskills)
  table.sort(traits)
  return spells, abilities, weaponskills, traits
end

local function skills_for_snapshot()
  local sk = game.skills()
  local combat, craft = {}, {}
  if sk then
    for id, s in pairs(sk.combat or {}) do
      local k = ashita_skill_index(tonumber(id), "combat")
      combat[tostring(k)] = { skill = s.level, rank = 0, capped = s.capped }
    end
    for id, s in pairs(sk.magic or {}) do
      local k = ashita_skill_index(tonumber(id), "magic")
      combat[tostring(k)] = { skill = s.level, rank = 0, capped = s.capped }
    end
    for id, s in pairs(sk.crafts or {}) do
      local k = ashita_skill_index(tonumber(id), "craft")
      craft[tostring(k)] = { skill = s.level, rank = s.rank, capped = s.capped }
    end
  end
  local by_job = {}
  for k, v in pairs(seen.skills_by_job) do by_job[k] = v end
  return { combat = combat, craft = craft, by_job = by_job }
end

local function read_container(bag)
  local max = game.bag_size(bag) or 0
  local list = {}
  for _, it in ipairs(game.items(bag)) do
    if it.id and it.id ~= 0 and it.id ~= 65535 and it.count and it.count > 0 then
      list[#list + 1] = {
        slot = it.slot,
        id = it.id,
        count = it.count,
        flags = it.locked or 0,
        price = it.price or 0,
        extra = hex(it.extdata or ""),
      }
    end
  end
  return list, max
end

local function capture()
  local me = game.player()
  if not me or not me.name or me.name == "" then
    say("log in first")
    return nil
  end
  local stats = game.stats()
  local jobs = game.jobs()
  local ent = game.entity(me.id) or game.player()
  local look = (ent and ent.look) or {}
  local face = (look and look.face) or 0

  local merit_up = seen.merits_at and seen.merits or merit_upgrades_from_game()
  local jp_up = seen.job_points_at and seen.job_points or job_point_upgrades_from_game()

  local snap = {
    schema = 1,
    addon = "charcapture",
    addon_version = VERSION,
    captured_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    captured_on = server_name(),
    character = {
      name = me.name,
      server_id = me.id,
      race = ent.race or 0,
      face = face,
      size = 0,
      nation = stats and stats.nation or 0,
      rank = stats and stats.rank or 0,
      rank_points = stats and stats.rank_points or 0,
      title = stats and stats.title or 0,
      homepoint = stats and stats.home_point or 0,
      residence = 0,
    },
    jobs = {
      main = me.main_job or 0,
      main_level = me.main_level or 0,
      sub = me.sub_job or 0,
      sub_level = me.sub_level or 0,
      levels = {},
      master_levels = {},
      job_points = {},
      merits = {
        points = stats and stats.merit_points or 0,
        max = stats and stats.merit_max or 0,
      },
      limit_points = stats and stats.limit_points or 0,
      exp = {
        current = stats and stats.exp or 0,
        needed = stats and stats.exp_next or 0,
      },
    },
    skills = skills_for_snapshot(),
    gil = game.gil(),
    inventory = {},
    equipment = {},
    look = {
      hair = face,
      head = look.head or 0,
      body = look.body or 0,
      hands = look.hands or 0,
      legs = look.legs or 0,
      feet = look.feet or 0,
      main = look.main or 0,
      sub = look.sub or 0,
      ranged = look.range or 0,
    },
    merit_upgrades = merit_up,
    job_point_upgrades = jp_up,
    quest_mission_packets = seen.logs_at and seen.logs or nil,
    currencies = (seen.currencies1_at or seen.currencies2_at) and seen.currencies or nil,
    personal_chocobo = seen.chocobo_at and { properties = seen.chocobo } or nil,
    automaton = seen.automaton_at and seen.automaton or nil,
    mastery = {
      job = 0,
      level = stats and stats.master_level or 0,
      exp = stats and stats.exemplar or 0,
      needed = stats and stats.exemplar_next or 0,
    },
    not_captured = { "fame (the game never sends the number)", "linkshells", "mog house layout" },
  }

  local spells, abilities, weaponskills, traits = known_abilities()
  snap.spells = spells
  snap.abilities = abilities
  snap.weaponskills = weaponskills
  snap.traits = traits
  snap.key_items = game.key_items()

  if not merit_up then
    snap.not_captured[#snap.not_captured + 1] =
      "merit upgrades (open the Merit Points menu, then //capture again)"
  end
  if not jp_up then
    snap.not_captured[#snap.not_captured + 1] =
      "job point upgrades (open the Job Points menu, then //capture again)"
  end
  if not seen.logs_at then
    snap.not_captured[#snap.not_captured + 1] =
      "quests and missions (zone once with Character Capture loaded, then //capture again)"
  end
  if not seen.currencies1_at then
    snap.not_captured[#snap.not_captured + 1] =
      "currencies, first tab (open Profile > Currencies, then //capture again)"
  end
  if not seen.currencies2_at then
    snap.not_captured[#snap.not_captured + 1] =
      "currencies, second tab (open the Currencies 2 tab of the same menu, then //capture again)"
  end
  local pup_lv = jobs and jobs.levels and (jobs.levels[PUP_JOB] or jobs.levels[tostring(PUP_JOB)])
  if not seen.automaton_at and pup_lv and pup_lv > 1 then
    snap.not_captured[#snap.not_captured + 1] =
      "your automaton (switch to Puppetmaster once, main or sub, then //capture again)"
  end
  if not seen.chocobo_at then
    snap.not_captured[#snap.not_captured + 1] =
      "your own chocobo (call it with the Chocobo Whistle and ride it, then //capture again; skip if you have none)"
  end

  for job = 1, JOB_COUNT do
    local lv = jobs and jobs.levels and jobs.levels[job]
    snap.jobs.levels[tostring(job)] = lv or 0
    local ml = jobs and jobs.master and jobs.master[job]
    snap.jobs.master_levels[tostring(job)] = ml or 0
    local jp = game.job_points() and game.job_points()[job]
    snap.jobs.job_points[tostring(job)] = {
      points = jp and jp.points or 0,
      spent = jp and jp.spent or 0,
      capacity = jp and jp.capacity or 0,
    }
  end

  local item_count = 0
  local container_unsynced = {}
  local container_locked = {}
  for _, c in ipairs(CONTAINERS) do
    local list, max = read_container(c)
    if max == 0 then
      if #list == 0 then container_unsynced[c] = true else container_locked[#container_locked + 1] = c end
    end
    item_count = item_count + #list
    snap.inventory[tostring(c)] = list
  end
  if #container_locked > 0 then
    local names = {}
    for _, c in ipairs(container_locked) do names[#names + 1] = STORAGE_NAME[c] or ("storage " .. c) end
    snap.not_captured[#snap.not_captured + 1] = ("%s reads as locked by the game (size 0) but its items were captured: check they are all there")
      :format(table.concat(names, ", "))
  end

  local unsynced_worn = {}
  local unsynced_seen = {}
  local eq = game.equipment()
  for slot = 0, EQUIP_SLOTS - 1 do
    local e = eq and eq[slot]
    if e and e.bag and e.slot then
      snap.equipment[tostring(slot)] = { container = e.bag, slot = e.slot, id = e.id or 0 }
      if container_unsynced[e.bag] and not unsynced_seen[e.bag] then
        unsynced_seen[e.bag] = true
        unsynced_worn[#unsynced_worn + 1] = e.bag
      end
    end
  end
  if #unsynced_worn > 0 then
    local names = {}
    for _, c in ipairs(unsynced_worn) do names[#names + 1] = STORAGE_NAME[c] or ("storage " .. c) end
    snap.not_captured[#snap.not_captured + 1] = ("gear worn from %s (open it from the main menu once, even if the wardrobe is unpaid: it still shows its gear; then //capture again)")
      :format(table.concat(names, ", "))
  end

  fs.mkdir("shared/charcapture")
  local safe = me.name:gsub("[^%w]", "")
  local path = ("shared/charcapture/%s.json"):format(safe)
  fs.write(path, json.encode(snap))

  local job = res.job(me.main_job) or tostring(me.main_job)
  last_summary = ("%s, %s%d, %d items across all bags, %d gil, %d spells, %d key items -> %s"):format(
    me.name, job, me.main_level or 0, item_count, snap.gil, #snap.spells, #snap.key_items, path)
  say(last_summary)
  if #unsynced_worn > 0 then
    local names = {}
    for _, c in ipairs(unsynced_worn) do names[#names + 1] = STORAGE_NAME[c] or ("storage " .. c) end
    say(("Open %s once from the main menu (wardrobes you have not opened this session can leave worn gear blank), then //capture again.")
      :format(table.concat(names, ", ")))
  end
  say("Snapshots are under mod-data/.shared/charcapture/ — send them from the Vanadreams Launcher (Capture > Send to Vanadreams).")
  return path
end

commands.register("capture", function(arg)
  if (arg or ""):lower() == "show" then
    say(last_summary or "nothing captured yet; //capture to take a snapshot")
    return
  end
  capture()
end)

events.on("load", function()
  say("Loaded. Zone once, open Merit Points, Job Points and both Currencies tabs, then //capture writes your snapshot. Switch jobs in your Mog House so every job's skills are kept.")
end)