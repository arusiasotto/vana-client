-- Macro storage.
--
-- macros.json (in the mod's data folder) is nested by main job:
--
--   {
--     "RDM": {
--       "library": { "<id>": <entry> },               -- the job's macros
--       "main": { "<bar>": { "<slot>": <slot> } }      -- the bars while RDM is your main job
--     }
--   }
--
-- A slot is { ref = "<id>" }, the library entry of that id, or a macro of its own (from before the library):
-- { name = "Cure", label = "Cure" (optional), lines = { "/ma \"Cure\" <t>", ... } }.
--
-- A library entry is a macro whose first line can be built from an action:
-- { name, label?, icon?, action = { kind = "ma", name = "Cure", target = "t" }?, lines = { <lines after it> } }.
-- An equip action's target is the equipment slot: { kind = "equip", name = "Warp Ring", target = "ring1" }.
-- Editing an entry changes every slot that refers to it.
--
-- Bars and slots are stored as text keys ("1", "2", ...) because JSON object keys are text. Sets kept under a job's
-- "sub" by earlier versions stay in the file unused.

local M = {}

M.MAX_BARS = 3
M.MAX_SLOTS = 12

local FILE = "macros.json"

local deps = nil
local db = {}

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

local function trim(s)
  s = tostring(s or "")
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end
M.trim = trim

-- "a | b | c" -> { "a", "b", "c" } (empty pieces dropped).
function M.split_lines(text)
  local out = {}
  for piece in tostring(text or ""):gmatch("[^|]+") do
    piece = trim(piece)
    if piece ~= "" then
      out[#out + 1] = piece
    end
  end
  return out
end

function M.join_lines(lines)
  return table.concat(lines or {}, " | ")
end

-- Fit text on a slot: up to 7 characters on one line, otherwise two short lines.
local function wrap(text)
  text = trim(text)
  if #text <= 7 then
    return text
  end
  local a, b = text:match("^(%S+)%s+(.+)$")
  if a then
    return a:sub(1, 7) .. "\n" .. b:sub(1, 7)
  end
  return text:sub(1, 7)
end

function M.display_label(macro)
  if type(macro) ~= "table" then
    return ""
  end
  local label = trim(macro.label)
  if label == "" then
    label = tostring(macro.name or "")
  end
  return wrap(label)
end

-- ---------------------------------------------------------------------------
-- Load and save
-- ---------------------------------------------------------------------------

-- deps = { read, write, decode, encode, log? }
function M.init(d)
  deps = d
  return M.load()
end

function M.load()
  db = {}
  local raw = deps.read(FILE)
  if not raw or raw:match("^%s*$") then
    return true
  end
  local ok, parsed = pcall(deps.decode, raw)
  if not ok or type(parsed) ~= "table" then
    -- Keep what the player wrote so a typo in a hand edit is never lost.
    pcall(deps.write, FILE .. ".bad", raw)
    return false, tostring(parsed)
  end
  db = parsed
  return true
end

function M.save()
  local ok, err = pcall(function()
    deps.write(FILE, deps.encode(db))
  end)
  if not ok and deps.log then
    deps.log("could not save " .. FILE .. ": " .. tostring(err))
  end
  return ok, err
end

-- ---------------------------------------------------------------------------
-- Jobs
-- ---------------------------------------------------------------------------

local function key(n)
  return tostring(n)
end

local function is_table(v)
  return type(v) == "table"
end

-- The job's table, and its `field` table inside it; created when `create`.
local function job_table(main, field, create)
  if not main then
    return nil
  end
  local job = db[main]
  if not is_table(job) then
    if not create then return nil end
    job = {}
    db[main] = job
  end
  if not is_table(job[field]) then
    if not create then return nil end
    job[field] = {}
  end
  return job[field]
end

local function bars(main, create)
  return job_table(main, "main", create)
end

local function library(main, create)
  return job_table(main, "library", create)
end

local function raw_slot(main, bar, slot)
  local set = bars(main, false)
  local b = set and set[key(bar)]
  if not is_table(b) then
    return nil
  end
  return b[key(slot)]
end

-- ---------------------------------------------------------------------------
-- Library
-- ---------------------------------------------------------------------------

-- A system command's action (kind "cmd") names the command itself.
local COMMAND = { ma = "/ma", ja = "/ja", ws = "/ws", pet = "/pet", item = "/item", equip = "/equip", cmd = "" }
M.ACTION_KINDS = COMMAND

-- The line an action builds: { kind = "ma", name = "Cure", target = "t" } -> /ma "Cure" <t>;
-- { kind = "equip", name = "Warp Ring", target = "ring1" } -> /equip ring1 "Warp Ring";
-- { kind = "cmd", name = "/attack", target = "t" } -> /attack <t>; { kind = "cmd", name = "/heal" } -> /heal.
function M.command(action)
  if not is_table(action) or not COMMAND[action.kind] or trim(action.name) == "" then
    return nil
  end
  local target = trim(action.target)
  if action.kind == "equip" then
    if target == "" then return nil end
    return ('/equip %s "%s"'):format(target, trim(action.name))
  end
  if action.kind == "cmd" then
    return target ~= "" and ("%s <%s>"):format(trim(action.name), target) or trim(action.name)
  end
  local line = ('%s "%s"'):format(COMMAND[action.kind], trim(action.name))
  if target ~= "" then
    line = line .. " <" .. target .. ">"
  end
  return line
end

-- An entry's lines as they run: its action's line, then its own.
function M.entry_lines(entry)
  local out = {}
  local first = M.command(entry.action)
  if first then
    out[1] = first
  end
  for _, l in ipairs(entry.lines or {}) do
    out[#out + 1] = tostring(l)
  end
  return out
end

-- One runnable macro per entry table, so a macro that is still running ignores a second press. A saved entry is a
-- new table, so its old expansion is dropped with it.
local expanded = setmetatable({}, { __mode = "k" })

local function expand(entry, id)
  local m = expanded[entry]
  if not m then
    m = { name = entry.name or "", label = entry.label, icon = entry.icon, lines = M.entry_lines(entry), ref = id }
    expanded[entry] = m
  end
  return m
end

-- The macro a slot value stands for: its library entry for a ref (nil when that entry is gone), else itself.
local function deref(main, v)
  if not is_table(v) then
    return nil
  end
  if v.ref ~= nil then
    local lib = library(main, false)
    local entry = lib and lib[tostring(v.ref)]
    return is_table(entry) and expand(entry, tostring(v.ref)) or nil
  end
  return v
end

local function entry_id_order(a, b)
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then return na < nb end
  return tostring(a) < tostring(b)
end

-- The job's entries, oldest first: { { id = "1", entry = {...} }, ... }.
function M.library(main)
  local lib = library(main, false)
  local ids = {}
  for id, entry in pairs(lib or {}) do
    if is_table(entry) then ids[#ids + 1] = id end
  end
  table.sort(ids, entry_id_order)
  local out = {}
  for _, id in ipairs(ids) do
    out[#out + 1] = { id = id, entry = lib[id] }
  end
  return out
end

function M.get_entry(main, id)
  local lib = library(main, false)
  local entry = lib and id ~= nil and lib[tostring(id)]
  return is_table(entry) and entry or nil
end

local function clean_entry(e)
  local lines = {}
  for _, l in ipairs(e.lines or {}) do
    l = trim(l)
    if l ~= "" then lines[#lines + 1] = l end
  end
  local out = { name = trim(e.name), lines = lines }
  if trim(e.label) ~= "" then out.label = trim(e.label) end
  if trim(e.icon) ~= "" then out.icon = trim(e.icon) end
  if is_table(e.action) and COMMAND[e.action.kind] and trim(e.action.name) ~= "" then
    out.action = { kind = e.action.kind, name = trim(e.action.name), target = trim(e.action.target) }
  end
  return out
end

-- Saves an entry under `id`, or under a new id when `id` is nil. Returns the id.
function M.save_entry(main, id, entry)
  local lib = library(main, true)
  if id == nil then
    local n = 0
    for k in pairs(lib) do
      n = math.max(n, tonumber(k) or 0)
    end
    id = n + 1
  end
  id = tostring(id)
  lib[id] = clean_entry(entry)
  M.save()
  return id
end

local function refers(v, id)
  return is_table(v) and v.ref ~= nil and tostring(v.ref) == id
end

-- How many slots of the job's bars refer to the entry.
function M.uses(main, id)
  id = tostring(id)
  local n = 0
  for _, bar in pairs(bars(main, false) or {}) do
    if is_table(bar) then
      for _, v in pairs(bar) do
        if refers(v, id) then n = n + 1 end
      end
    end
  end
  return n
end

-- Removes an entry and empties every slot that refers to it.
function M.delete_entry(main, id)
  id = tostring(id)
  local lib = library(main, false)
  if lib then lib[id] = nil end
  local set = bars(main, false) or {}
  for bk, bar in pairs(set) do
    if is_table(bar) then
      for sk, v in pairs(bar) do
        if refers(v, id) then bar[sk] = nil end
      end
      if next(bar) == nil then set[bk] = nil end
    end
  end
  M.save()
end

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------

-- What a slot runs while `main` is your main job, or nil when it is empty.
function M.resolve(main, bar, slot)
  return deref(main, raw_slot(main, bar, slot))
end

-- Every filled slot: eff[bar][slot] = macro.
function M.effective(main)
  local eff = {}
  for bk, bar in pairs(bars(main, false) or {}) do
    local b = tonumber(bk)
    if b and is_table(bar) then
      for sk, v in pairs(bar) do
        local s = tonumber(sk)
        local macro = s and deref(main, v)
        if macro then
          eff[b] = eff[b] or {}
          eff[b][s] = macro
        end
      end
    end
  end
  return eff
end

local function put_raw(main, bar, slot, v)
  local set = bars(main, true)
  local bk = key(bar)
  if not is_table(set[bk]) then
    set[bk] = {}
  end
  set[bk][key(slot)] = v
end

-- Puts a macro of its own on a slot.
function M.set_macro(main, bar, slot, macro)
  local lines = {}
  for _, l in ipairs(macro.lines or {}) do
    lines[#lines + 1] = tostring(l)
  end
  local m = { name = trim(macro.name), lines = lines }
  local label = trim(macro.label)
  if label ~= "" then
    m.label = label
  end
  put_raw(main, bar, slot, m)
  M.save()
end

-- Puts a library entry on a slot.
function M.assign(main, bar, slot, id)
  put_raw(main, bar, slot, { ref = tostring(id) })
  M.save()
end

-- The library entry a slot refers to, or nil.
function M.ref_of(main, bar, slot)
  local m = M.resolve(main, bar, slot)
  return m and m.ref or nil
end

-- Empties a slot.
function M.clear(main, bar, slot)
  local set = bars(main, false)
  local bk = key(bar)
  if set and is_table(set[bk]) then
    set[bk][key(slot)] = nil
    if next(set[bk]) == nil then
      set[bk] = nil
    end
  end
  M.save()
end

-- Swaps two slots; one that refers to the library stays a reference.
function M.swap(main, b1, s1, b2, s2)
  local v1, v2 = raw_slot(main, b1, s1), raw_slot(main, b2, s2)
  local function put(b, s, v)
    if is_table(v) then
      put_raw(main, b, s, v)
    else
      local set = bars(main, false)
      if set and is_table(set[key(b)]) then set[key(b)][key(s)] = nil end
    end
  end
  put(b1, s1, v2)
  put(b2, s2, v1)
  M.save()
end

return M
