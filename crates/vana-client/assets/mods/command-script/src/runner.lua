-- Runs a script's lines: wait, then / burst chains, and ordinary game commands.

local data = require("src.data")
local match = require("src.match")

local M = {}

M.LINK_GAP = 3.3
M.SPELL_GAP = 1.25
M.STEP_TIMEOUT = 8
M.OUT_TIMEOUT = 2.5

M.hooks = { say = function(msg) chat.add("Command Script: " .. msg) end, dispatch_cs = nil }

local running = nil
local MAX_WAIT = 60

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clamp_wait(text)
  local n = tonumber(text) or 0
  if n < 0 then n = 0 end
  if n > MAX_WAIT then n = MAX_WAIT end
  return n
end

local function parse_line(line)
  line = trim(line)
  if line == "" then return "skip" end
  local only = line:match("^[Ww][Aa][Ii][Tt]%s+([%d%.]+)$") or line:match("^/[Ww][Aa][Ii][Tt]%s+([%d%.]+)$")
  if only then return "wait", clamp_wait(only) end
  local body, after = line:match("^(.-)%s*<%s*[Ww][Aa][Ii][Tt]%s+([%d%.]+)%s*>%s*$")
  if body then
    body = trim(body)
    if body == "" then return "wait", clamp_wait(after) end
    return "cmd", body, clamp_wait(after)
  end
  return "cmd", line
end

M.parse_line = parse_line

local function say(msg)
  M.hooks.say(msg)
end

local function player_id()
  local p = game.player()
  return p and p.id
end

local function needs_target(line)
  return line:find("<t>", 1, true) or line:find("<st", 1, true)
end

local function self_cast_line(line)
  return line:find("<me>", 1, true) ~= nil or line:find("<stpc>", 1, true) ~= nil
end

local function link_gap(kind, wire)
  if kind == "ma" then
    local gap = M.SPELL_GAP
    if wire then
      local s = res.spell(wire)
      local t = s and s.cast_time
      if type(t) == "number" and t > 0.5 then
        gap = math.max(gap, t + 1.0)
      end
    end
    return gap
  end
  return M.LINK_GAP
end

local function cast_idle()
  local ok, c = pcall(game.cast)
  return ok and not c
end

local function target_gone(w)
  local ok, t = pcall(game.target)
  if not ok or not w.target_id then return false end
  if not t then return true end
  if t.id ~= w.target_id then return true end
  if t.hpp ~= nil and t.hpp <= 0 then return true end
  return false
end

local function watch_tick(r, now)
  local w = r.watch
  if target_gone(w) then
    say(('Script "%s": target lost, stopped.'):format(r.word))
    running = nil
    return
  end
  if w.saw_finish then
    r.watch = nil
    r.at = now + w.gap
    return
  end
  if w.kind == "ma" then
    local ok, c = pcall(game.cast)
    local cast_id = ok and c and c.spell
    if cast_id then
      if cast_id ~= w.wire then
        w.wire = cast_id
        local s = res.spell(cast_id)
        if s and s.name then w.name = s.name end
      end
      w.saw_cast = true
      w.bar_clear_at = nil
    elseif w.saw_cast then
      w.bar_clear_at = w.bar_clear_at or now
      if now - w.bar_clear_at >= 0.12 then
        w.saw_finish = true
        return
      end
    elseif w.out_ok and (w.saw_pkt or w.saw_start) and cast_idle() and now - w.sent_at > 0.15 then
      -- No cast bar (e.g. Enfire): trust 0x028 start/finish after the client accepted the cast.
      w.saw_finish = true
      return
    elseif w.saw_pkt and cast_idle() and now - w.sent_at > 0.35 then
      w.saw_finish = true
      return
    elseif w.saw_start and cast_idle() and now - w.sent_at > 0.5 then
      w.saw_finish = true
      return
    elseif w.out_ok and not w.saw_pkt and not w.saw_cast and not w.retried
        and now - w.sent_at > 2 and now - w.sent_at < 6 and cast_idle() then
      w.retried = true
      pcall(function()
        if actions and actions.cast then actions.cast(w.wire, "<me>") end
      end)
      w.out_ok = false
    end
  end
  if now - w.sent_at > M.STEP_TIMEOUT then
    local label = w.name or "?"
    local note = ""
    if w.kind == "ma" then
      note = (" (id %s, bar=%s, pkt=%s, sent=%s)"):format(
        tostring(w.wire), w.saw_cast and "yes" or "no", w.saw_pkt and "yes" or "no", w.out_ok and "yes" or "no")
    end
    say(('Script "%s": %s never finished, stopped.%s'):format(r.word, label, note))
    running = nil
  end
end

-- Spell refusals while a cast is in flight (pending-actions message ids).
local SPELL_REFUSAL = {
  [34] = true, [35] = true, [40] = true, [47] = true, [48] = true, [49] = true, [71] = true, [72] = true, [78] = true,
  [155] = true, [235] = true, [313] = true, [315] = true, [316] = true, [569] = true, [581] = true, [661] = true,
  [700] = true, [717] = true,
}

function M.on_buff_gain(_id)
  local w = running and running.watch
  if not w or w.kind ~= "ma" or not w.self_cast then return end
  local now = os.clock()
  if now - w.sent_at > M.STEP_TIMEOUT then return end
  if w.saw_finish then return end
  -- Only after we tried to send the spell (not an old buff icon before the cast).
  if w.out_ok or w.saw_cast or w.saw_start or w.saw_pkt or now - w.sent_at > 0.25 then
    w.saw_finish = true
  end
end

function M.on_battle_message(actor, target, message, p1, p2)
  if not running or actor ~= player_id() then return end
  local w = running.watch
  if not w or w.kind ~= "ma" or os.clock() - w.sent_at > 3 then return end
  if not SPELL_REFUSAL[message] then return end
  local wire = type(p1) == "number" and (math.floor(p1) % 0x10000) or nil
  local named = p1 == 0 or wire == w.wire
  if not named then return end
  local m = res.message(message, { actor = actor, target = target, values = { p1, p2 } })
  local text = m and m.text and text.strip(m.text):gsub("\n", " ") or "refused"
  say(('Script "%s": %s — %s'):format(running.word, w.name or "?", text))
  running = nil
end

function M.on_action(a)
  if not running or a.actor ~= player_id() then return end
  local r = running
  local step = r.last
  if step and not r.watch and match.step_finished(step, a) then
    r.pending_done = true
  end
  local w = r.watch
  if not w then return end
  if w.kind == "ma" and match.spell_interrupt(a) and (w.saw_cast or w.saw_start or w.saw_pkt) then
    say(('Script "%s": %s interrupted, stopped.'):format(r.word, w.name or "?"))
    running = nil
    return
  end
  if w.kind == "ma" then
    local wire = match.spell_wire(a)
    if wire and wire > 0 and wire ~= w.wire then
      w.wire = wire
      local s = res.spell(wire)
      if s and s.name then w.name = s.name end
    end
    if wire == w.wire then
      w.saw_pkt = true
      if a.category == 8 then w.saw_start = true end
      if match.ma_action_done(w.wire, a) then
        w.saw_finish = true
        return
      end
    end
  end
  if not match.same_step(w, a) then return end
  if match.step_finished(w, a) then
    w.saw_finish = true
  elseif w.kind == "ma" and a.category == 8 then
    w.saw_start = true
  elseif w.kind == "ws" and a.category == 7 then
    w.saw_start = true
  end
end

function M.on_out_01A(p)
  local r = running
  if not r then return end
  local d = p.data
  if type(d) ~= "string" or #d < 0x10 then return end
  local _, _, cat, param = string.unpack("<I4I2I2I4", d, 5)
  local step = match.from_outgoing(cat, param)
  if not step then return end
  if step.kind == "ma" and r.watch and r.watch.kind == "ma" then
    r.watch.wire = step.wire
    if step.name then r.watch.name = step.name end
    r.watch.out_ok = true
  end
  if r.await_out then
    r.last = step
    if r.last then r.last.out_ok = true end
    local ok, t = pcall(game.target)
    r.last.sent_at = os.clock()
    if needs_target(r.await_line or "") then
      r.last.target_id = (ok and t) and t.id or nil
    end
    r.await_out = nil
    r.await_line = nil
    r.await_since = nil
  end
end

local function run_cs_line(line)
  local args = {}
  for w in line:gmatch("%S+") do args[#args + 1] = (w:gsub('^"(.*)"$', "%1")) end
  local first = (args[1] or ""):lower()
  table.remove(args, 1)
  if M.hooks.dispatch_cs then
    M.hooks.dispatch_cs(first, table.unpack(args))
  end
end

local function fire_step(r, line, step, now)
  local tgt = match.target_token(line)
  local ok, err = pcall(function()
    if step.kind == "ma" and actions and actions.cast then
      actions.cast(step.wire, tgt or "<me>")
    elseif step.kind == "ws" and actions and actions.weaponskill then
      actions.weaponskill(step.wire, tgt or "<t>")
    elseif step.kind == "ja" and actions and actions.ability then
      actions.ability(step.res_id, tgt or "<me>")
    else
      commands.run(line)
      return
    end
  end)
  if not ok then
    say(('Script "%s": could not cast (%s); trying the line.'):format(r.word, tostring(err)))
    commands.run(line)
  end
end

-- Send one game command line; returns false if the script should stop.
local function dispatch_line(r, line, now)
  local kind, cmd, after = parse_line(line)
  if kind == "skip" then
    r.at = now
    return true
  end
  if kind == "wait" then
    r.at = now + cmd
    return true
  end
  line = cmd
  r.last = match.from_line(line)
  local spell_cmd = (line:match("^(%S+)") or ""):lower()
  if spell_cmd:match("^/(ma|magic|nin|ninjutsu|so|song)") and not r.last then
    local label = line:match('"([^"]+)"') or line:match("^/%S+%s+(%S+)") or line
    say(('Script "%s": unknown or unlearned spell %s, stopped.'):format(r.word, label))
    return false
  end
  if r.last and line:find('"', 1, true) then
    line = match.rewrite_line(line, r.last)
  end
  r.await_out = r.last ~= nil
  r.await_line = line
  r.await_since = r.await_out and now or nil
  if r.last and needs_target(line) then
    local ok, t = pcall(game.target)
    r.last.sent_at = now
    r.last.target_id = (ok and t) and t.id or nil
  elseif r.last then
    r.last.sent_at = now
  end
  if r.last and r.last.kind == "ma" then
    r.last.out_ok = false
    r.last.self_cast = self_cast_line(line)
  end
  if line:match("^/(cs)%s") then
    r.await_out = false
    run_cs_line(line)
    r.at = now + ((after and after > 0) and after or 0.3)
  elseif r.last then
    fire_step(r, line, r.last, now)
    r.at = now + 0.05
  else
    commands.run(line)
    r.at = now + ((after and after > 0) and after or 0.3)
  end
  return true
end

local function split_then_burst(line)
  local rest = line:match("^[Tt][Hh][Ee][Nn]%s+(.+)$")
  if rest then return rest, false end
  rest = line:match("^[Bb][Uu][Rr][Ss][Tt]%s+(.+)$")
  if rest then return rest, true end
  return nil
end

-- Arm completion watch as soon as we cast, not on the next tick's "then" line (avoids missing a short cast bar).
local function arm_watch_from_last(r, gap)
  local step = r.last
  if not step or not step.kind then return false end
  r.watch = {
    kind = step.kind,
    wire = step.wire,
    name = step.name,
    sent_at = step.sent_at or os.clock(),
    target_id = step.target_id,
    gap = gap,
    out_ok = step.out_ok,
    self_cast = step.self_cast,
  }
  if r.pending_done then
    r.watch.saw_finish = true
    r.pending_done = nil
  end
  r.last = nil
  return true
end

local function follow_then_after_dispatch(r)
  local next_line = r.lines[r.index]
  if not next_line or not r.last then return end
  local rest, burst = split_then_burst(next_line)
  if not rest then return end
  local gap = burst and 0 or link_gap(r.last.kind, r.last.wire)
  if arm_watch_from_last(r, gap) then
    r.after_watch = rest
    r.index = r.index + 1
  end
end

function M.tick()
  local r = running
  if not r or os.clock() < r.at then return end
  local now = os.clock()
  if r.await_out and r.await_since and now - r.await_since > M.OUT_TIMEOUT then
    r.await_out = false
    r.await_since = nil
  end
  if r.watch then
    watch_tick(r, now)
    return
  end

  -- Command queued after the previous step finished (then / burst), with gap already waited.
  if r.after_watch then
    if not cast_idle() then
      r.at = now + 0.05
      return
    end
    local line = r.after_watch
    r.after_watch = nil
    if not dispatch_line(r, line, now) then
      running = nil
      return
    end
    -- Queued command only; the matching "then …" line was skipped when this watch was armed.
    follow_then_after_dispatch(r)
    return
  end

  local line = r.lines[r.index]
  if not line then
    say(('Script "%s" finished.'):format(r.word))
    running = nil
    return
  end

  local rest, burst = split_then_burst(line)
  if rest then
    if r.last then
      local gap = burst and 0 or link_gap(r.last.kind, r.last.wire)
      if r.pending_done and r.last.kind ~= "ma" and r.last.kind ~= "ws" then
        r.pending_done = nil
        r.last = nil
        r.after_watch = rest
        r.at = now + gap
        return
      end
      r.pending_done = nil
      r.watch = {
        kind = r.last.kind,
        wire = r.last.wire,
        name = r.last.name,
        sent_at = r.last.sent_at,
        target_id = r.last.target_id,
        gap = gap,
        out_ok = r.last.out_ok,
        self_cast = r.last.self_cast,
      }
      r.after_watch = rest
      r.last = nil
      return
    end
    line = rest
  end

  if not dispatch_line(r, line, now) then
    running = nil
    return
  end
  r.index = r.index + 1
  follow_then_after_dispatch(r)
end

function M.run(word, lines)
  if running then
    say(('Script "%s" is still running.'):format(running.word))
    return true
  end
  lines = lines or (data.get(word, select(1, require("src.jobs").current())) or {}).lines
  if type(lines) ~= "table" or #lines == 0 then
    return false
  end
  local copy = {}
  for i, l in ipairs(lines) do copy[i] = l end
  running = { word = word, lines = copy, index = 1, at = 0 }
  return true
end

function M.stop()
  if running then
    say(('Script "%s" stopped.'):format(running.word))
    running = nil
  end
end

function M.running() return running ~= nil end

return M