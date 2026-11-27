-- Command Script: named multi-line scripts per job, run with //cs <word>.

local data = require("src.data")
local jobs = require("src.jobs")
local runner = require("src.runner")
local manager = require("src.manager")

local ok, err, bad = data.init({
  read = fs.read,
  write = fs.write,
  decode = json.decode,
  encode = function(value) return json.encode(value, { pretty = true }) end,
  log = log.warn,
})
local function read_failed(why, file)
  file = file or data.file()
  chat.add("Command Script: " .. file .. " could not be read (" .. tostring(why) .. "); a copy was kept as " .. file .. ".bad.")
end
if not ok then read_failed(err, bad) end

local function changed()
  manager.refresh()
end

manager.hooks.changed = changed
manager.hooks.run = function(word)
  if not settings.get("on") then return end
  if runner.run(word) then
    chat.add(('Command Script: running "%s".'):format(word))
  else
    chat.add('Command Script: no script "' .. tostring(word) .. '" for this job.')
  end
end

local function dispatch_cs(cmd, a, b, c)
  cmd = (cmd or ""):lower()
  if cmd == "" or cmd == "help" then
    usage()
  elseif cmd == "stop" then
    runner.stop()
  elseif cmd == "reload" then
    local loaded, why, file = data.load()
    if not loaded then read_failed(why, file) end
    changed()
  elseif cmd == "list" then
    list_scripts()
  elseif cmd == "run" and a and a ~= "" then
    manager.hooks.run(a)
  else
    manager.hooks.run(cmd)
  end
end

runner.hooks.dispatch_cs = dispatch_cs

local function usage()
  chat.add("Command Script:")
  for _, line in ipairs(commands.usage("cs")) do chat.add("  " .. line) end
  chat.add("  //cs <word>  runs a saved script")
end

local function list_scripts()
  local mj = select(1, jobs.current()) or "?"
  local rows = data.sorted(mj)
  chat.add(("Command Script (%s):"):format(mj))
  if #rows == 0 then
    chat.add("  (none)")
    return
  end
  for _, row in ipairs(rows) do
    chat.add(("  %s (%s, %d line%s)"):format(row.word, row.entry.scope, #(row.entry.lines or {}),
      #(row.entry.lines or {}) == 1 and "" or "s"))
  end
end

local function try_run(cmd)
  cmd = data.sanitize_word(cmd)
  if not cmd then return false end
  if not data.get(cmd, select(1, jobs.current())) then return false end
  manager.hooks.run(cmd)
  return true
end

commands.register("cs", function(cmd, a, b)
  if not settings.get("on") then
    chat.add("Command Script is off (Mods page).")
    return
  end
  cmd = (cmd or ""):lower()
  if cmd == "" then
    manager.toggle()
    return
  end
  if cmd == "help" then
    usage()
  elseif cmd == "stop" then
    runner.stop()
  elseif cmd == "reload" then
    dispatch_cs("reload")
  elseif cmd == "list" then
    list_scripts()
  elseif cmd == "run" then
    if a and a ~= "" then manager.hooks.run(a) else usage() end
  elseif try_run(cmd) then
    return
  else
    chat.add('Command Script: unknown //cs command or script "' .. cmd .. '".')
    usage()
  end
end)

events.on("action", function(a) runner.on_action(a) end)
events.on("buff_gain", function(id) runner.on_buff_gain(id) end)
events.on("battle_message", function(a, t, m, p1, p2) runner.on_battle_message(a, t, m, p1, p2) end)
packets.on_out(0x01A, function(p) runner.on_out_01A(p) end)
events.on("job_change", changed)
timer.every(0.05, runner.tick)

local function use_world()
  local ok, info = pcall(game.info)
  if not ok or type(info) ~= "table" then return end
  local switched, loaded, why, file = data.set_world(info.server)
  if not switched then return end
  if loaded then changed() else read_failed(why, file) end
end

timer.every(1, use_world)
use_world()