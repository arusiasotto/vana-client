-- Match s2c 0x028 actions to a command line (same rules as pending-actions).

local M = {}

local FINISH = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [11] = true, [13] = true, [14] = true,
  [15] = true }
local C2S = { [3] = "ma", [7] = "ws", [9] = "ja" }

local function low16(v)
  if type(v) ~= "number" then return nil end
  return math.floor(v) % 0x10000
end

function M.kind_from_category(cat)
  if cat == 3 or cat == 7 then return "ws" end
  if cat == 4 or cat == 8 then return "ma" end
  if cat == 6 or cat == 9 or cat == 10 or cat == 14 or cat == 15 then return "ja" end
  return nil
end

function M.is_finish(cat) return FINISH[cat] == true end

function M.is_start(cat)
  return cat == 7 or cat == 8 or cat == 9 or cat == 10 or cat == 12
end

function M.finish_wire(a)
  if not M.is_finish(a.category) then return nil end
  local kind = M.kind_from_category(a.category)
  if not kind then return nil end
  return kind, low16(a.param)
end

-- Spell id on the wire (pending-actions: finish param, or start "ca??" result value).
local function spell_id_from_results(a)
  for _, t in ipairs(a.targets or {}) do
    for _, r in ipairs(t.results or {}) do
      local v = r and r.value and low16(r.value)
      if v and v > 0 and v < 0x700 then return v end
    end
  end
end

function M.spell_wire(a)
  if a.category == 4 then
    local p = low16(a.param)
    if p and p > 0 and p < 0x700 then return p end
    return spell_id_from_results(a)
  end
  if a.category == 8 and low16(a.param) == 0x6163 then
    local t = a.targets and a.targets[1]
    local r = t and t.results and t.results[1]
    if r and r.value then return low16(r.value) end
  end
end

-- Player weapon skill id (not mob skill 11).
function M.ws_wire(a)
  if a.category == 3 or a.category == 7 then return low16(a.param) end
end

local function norm(name) return (name or ""):lower() end

-- Full spell list by lowercased name (hotbar actions.lua), not only learned spells.
local spell_by_name

local function learned(id)
  for _, sid in ipairs(game.spells() or {}) do
    if sid == id then return true end
  end
  return false
end

local function spell_index()
  if spell_by_name then return spell_by_name end
  local idx = {}
  for id = 1, 1023 do
    local s = res.spell(id)
    if s and s.name and s.name ~= "" then
      local n = norm(s.name)
      local cur = idx[n]
      if not cur or (learned(id) and not learned(cur)) or (learned(id) == learned(cur) and id > cur) then
        idx[n] = id
      end
    end
  end
  spell_by_name = idx
  return spell_by_name
end

function M.clear_spell_cache()
  spell_by_name = nil
end

local function step_of(kind, res_id, wire, name)
  return { kind = kind, res_id = res_id, wire = wire, name = name }
end

function M.lookup_ja(name)
  name = norm(name)
  for _, id in ipairs(game.abilities() or {}) do
    if id >= 0x200 and id < 0x400 then
      local r = res.ability(id)
      if r and r.name and norm(r.name) == name then
        return { kind = "ja", res_id = id, wire = id - 0x200, name = r.name }
      end
    end
  end
end

function M.lookup_ws(name)
  name = norm(name)
  for _, id in ipairs(game.abilities() or {}) do
    if id < 0x200 then
      local r = res.ability(id)
      if r and r.name and norm(r.name) == name then
        return { kind = "ws", res_id = id, wire = id, name = r.name }
      end
    end
  end
end

function M.lookup_spell(name)
  local want = norm(name)
  -- Prefer a learned spell whose name matches exactly (e.g. Enfire id 100).
  for _, sid in ipairs(game.spells() or {}) do
    local s = res.spell(sid)
    if s and s.name and norm(s.name) == want then
      return step_of("ma", sid, sid, s.name)
    end
  end
  local idx = spell_index()
  local id = idx[want]
  if id and learned(id) then
    local s = res.spell(id)
    return step_of("ma", id, id, s and s.name or name)
  end
  -- Best learned tier when the script asks for a higher roman numeral than we have.
  local base = want:match("^(.+)%s+[ivx]+$") or want
  local esc = base:gsub("(%W)", "%%%1")
  local pick
  for _, sid in ipairs(game.spells() or {}) do
    local s = res.spell(sid)
    if s and s.name then
      local n = norm(s.name)
      if n == base or n == want or n:match("^" .. esc .. "[%s_%-]") or n:match("^" .. esc .. "%s") then
        if not pick or sid > pick.id then pick = { id = sid, name = s.name } end
      end
    end
  end
  if pick then
    return step_of("ma", pick.id, pick.id, pick.name)
  end
end

function M.rewrite_line(line, step)
  if not step or not step.name then return line end
  local pre, quoted, tail = line:match('^(%S+%s+)"([^"]+)"(.*)$')
  if pre then return pre .. '"' .. step.name .. '"' .. (tail or "") end
  local pre2, word, tail2 = line:match("^(%S+%s+)(%S+)(.*)$")
  if pre2 and not word:find("<", 1, true) then
    return pre2 .. '"' .. step.name .. '"' .. (tail2 or "")
  end
  return line
end

function M.target_token(line)
  local tags = {}
  for tag in (line or ""):gmatch("(<[^>]+>)") do tags[#tags + 1] = tag end
  return tags[#tags]
end

function M.from_line(line)
  local cmd, quoted = line:match("^/(%a+)%s+\"([^\"]+)\"")
  if not cmd then
    cmd, quoted = line:match("^/(%a+)%s+(%S+)")
    if quoted and quoted:find("<", 1, true) then quoted = nil end
  end
  if not cmd then return nil end
  cmd = cmd:lower()
  if cmd == "magic" then cmd = "ma" end
  if cmd == "jobability" then cmd = "ja" end
  if cmd == "weaponskill" then cmd = "ws" end
  if cmd == "ninjutsu" or cmd == "nin" then cmd = "ma" end
  if cmd == "song" or cmd == "so" then cmd = "ma" end
  if cmd == "pet" then cmd = "ja" end
  if cmd == "ja" then return M.lookup_ja(quoted) end
  if cmd == "ws" then return M.lookup_ws(quoted) end
  if cmd == "ma" then return M.lookup_spell(quoted) end
  return nil
end

-- Category 8 / 12 spell interrupt ("sp.." on the wire as 28787).
function M.spell_interrupt(a)
  if a.category ~= 8 and a.category ~= 12 then return false end
  return a.param == 28787 or (a.param & 0xffff) == 0x7073
end

function M.same_step(step, a)
  if not step or not step.kind then return false end
  if step.kind == "ma" then
    local w = M.spell_wire(a)
    return w ~= nil and w == step.wire
  end
  if step.kind == "ws" then
    local w = M.ws_wire(a)
    return w ~= nil and w == step.wire
  end
  local kind, wire = M.finish_wire(a)
  if kind and wire == step.wire and kind == step.kind then return true end
  if not M.is_start(a.category) then return false end
  local k = M.kind_from_category(a.category)
  return k == step.kind and low16(a.param) == step.wire
end

function M.spell_instant(wire)
  local s = res.spell(wire)
  if not s then return false end
  local t = s.cast_time
  if type(t) ~= "number" then return false end
  return t <= 0.5
end

-- No cast bar: instant spells (and pending-actions) can complete on start or finish.
function M.ma_action_done(wire, a)
  local w = M.spell_wire(a)
  if not w or w ~= wire then return false end
  if a.category == 4 then return true end
  if a.category == 8 and M.spell_instant(wire) then return true end
  return false
end

-- The action packet that means this step finished (for then / burst).
function M.step_finished(step, a)
  if not M.same_step(step, a) then return false end
  if step.kind == "ma" then
    return a.category == 4 or (a.category == 8 and M.spell_instant(step.wire))
  end
  if step.kind == "ws" then return a.category == 3 end
  if step.kind == "ja" then
    return a.category == 6 or a.category == 14 or a.category == 15
  end
  return M.is_finish(a.category)
end

-- Outgoing 0x01A while a script waits for its packet (name-table id for ja).
function M.from_outgoing(cat, param)
  local kind = C2S[cat]
  if not kind then return nil end
  if kind == "ja" then
    return { kind = "ja", res_id = param + 0x200, wire = param, name = (res.ability(param + 0x200) or {}).name }
  end
  if kind == "ws" then
    return { kind = "ws", res_id = param, wire = param, name = (res.ability(param) or {}).name }
  end
  if kind == "ma" then
    return { kind = "ma", res_id = param, wire = param, name = (res.spell(param) or {}).name }
  end
end

return M