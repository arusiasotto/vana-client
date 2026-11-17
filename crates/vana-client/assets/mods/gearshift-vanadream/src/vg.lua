-- //vg: vanagear's commands, for the ones this port has an equivalent of (vg/commands.lua in the Vanadreams launcher's
-- vanagear add-on). The words and their arguments are vanagear's; a word that is not here yet says so.
--
--   /vg                         the window
--   /vg help | commands         this list
--   /vg build                   rebuild the sets now
--   /vg status                  what is running
--   /vg dt [pdt | mdt | all | off]   damage taken gear over everything else
--   /vg tp default | hybrid | acc    which fighting set is worn
--   /vg nuke power | acc        damage or accuracy for nukes and enfeebles
--   /vg burst [on | off]        magic burst gear on nukes
--   /vg kite [on | off]         movement gear over everything else (hold the monster's attention, run it around)
--   /vg th [on | off]           treasure hunter gear over everything else
--   /vg idle auto | regen | refresh | speed   standing still
--   /vg pet tp | dt | acc       what the gear does for a pet while it fights
--   /vg lock <slot | all>, /vg unlock <slot | all>   keep a slot as it is
--   /vg weapon main | sub | range <item | none>      your weapon in every set
--   /vg why <set> <slot>, /vg upgrades, /vg set <set> <slot> <item | auto>, /vg wear <set>
--   /vg trusts [on | off | send | rebuild | <trust> [<set>] | set ... | use ...]
--   /vg mode ... , /vg file, /vg reload   Gearshift's own (kept)

local run = require("src.build.run")
local trusts = require("src.trusts")

local M = {}

local function say(text) chat.add("vanagear: " .. text) end

local function on_off(word, current)
  if word == "on" then return true end
  if word == "off" then return false end
  return not current
end

-- What /vg help lists.
M.LINES = {
  { "/vg", "open the window: your sets, the piece in each slot and why" },
  { "/vg build", "rebuild the sets now (also happens on job change, level up and new gear)" },
  { "/vg status", "what is running, and the trusts" },
  { "/vg dt [pdt | mdt | all | off]", "damage taken gear over everything else: physical, magic or both" },
  { "/vg tp default | hybrid | acc", "which fighting set you wear" },
  { "/vg nuke power | acc", "damage or accuracy for nukes and enfeebles" },
  { "/vg burst [on | off]", "magic burst gear on nukes" },
  { "/vg kite [on | off]", "movement gear over everything else: run a monster around while it holds its target" },
  { "/vg th [on | off]", "treasure hunter gear over everything else" },
  { "/vg idle auto | regen | refresh | speed", "standing still: auto puts regen on below 60% HP and refresh below 70% MP" },
  { "/vg pet tp | dt | acc", "what your gear does for your pet while it fights" },
  { "/vg lock <slot | all>, /vg unlock <slot | all>", "keep a slot as you have it: nothing equips it, saved for this job" },
  { "/vg weapon main | sub | range <item | none>", "your weapon in every set (none: leave the slot alone)" },
  { "/vg why <set> <slot>", "the piece that won and the ones behind it" },
  { "/vg upgrades", "pieces in storage that would win a slot" },
  { "/vg set <set> <slot> <item | auto>", "change one slot of a built set (auto: the builder picks again)" },
  { "/vg wear <set>", "put a built set on now" },
  { "/vg trusts on | off", "give your called trusts the stats of a set from your bags; off stops sending" },
  { "/vg trusts window", "the trust window: each trust's sets, a piece in every slot, and what it uses" },
  { "/vg trusts", "your trusts and their sets; /vg trusts <trust> [<set>] shows one" },
  { "/vg trusts send | rebuild", "send every set again / build the sets again" },
  { "/vg trusts set <trust> <set> <slot> <item | remove | auto>", "change one slot of a trust's set" },
  { "/vg trusts use <trust> on | off <action>", "switch a spell, ability or weapon skill off or on for a trust" },
  { "/gs c <word>, /gs equip <set>", "the same as /vg <word> and /vg wear <set>, so GearSwap macros keep working" },
  { "/vg mode <hybrid | acc | pdt | mdt | mb | macc | off>", "Gearshift's toggles" },
  { "/vg file, /vg reload", "which gear file is loaded / read it again" },
}

function M.help()
  say("commands:")
  for _, l in ipairs(M.LINES) do chat.add("vanagear: " .. l[1] .. "  " .. l[2]) end
end

local function status(ctx)
  local st = run.state
  local count = 0
  for _ in pairs(st.built or {}) do count = count + 1 end
  if st.job then
    say(string.format("Built %d sets for %s%d from %d pieces you carry.", count, st.job, st.level or 0,
      #(st.owned or {})))
  else
    say("No sets built yet.")
  end
  say(run.active() and "Wearing the built sets." or "Showing the built sets; Wear These Sets is off in the window.")
  local f = ctx.file()
  if f then say("Gear file: " .. f) end
  trusts.command({})
end

-- args: the words after /vg. ctx: window(), reload(), file() from init.lua.
function M.command(args, ctx)
  local cmd = (args[1] or ""):lower()
  local arg = (args[2] or ""):lower()
  local modes = run.modes()

  if cmd == "" then
    ctx.window()
  elseif cmd == "help" or cmd == "commands" then
    M.help()
  elseif cmd == "status" then
    status(ctx)
  elseif cmd == "build" then
    run.rebuild()
    trusts.rebuild()
    say("Rebuilding.")
  elseif cmd == "dt" then
    if arg == "pdt" then
      modes.pdt, modes.mdt = true, nil
    elseif arg == "mdt" then
      modes.pdt, modes.mdt = nil, true
    elseif arg == "all" or arg == "on" then
      modes.pdt, modes.mdt = true, true
    elseif arg == "off" then
      modes.pdt, modes.mdt = nil, nil
    else
      local on = not (modes.pdt or modes.mdt)
      modes.pdt, modes.mdt = on or nil, on or nil
    end
    say("Damage taken gear: " .. ((modes.pdt and modes.mdt) and "all" or (modes.pdt and "physical")
      or (modes.mdt and "magic") or "off") .. ".")
  elseif cmd == "tp" then
    local pick = ({ default = "default", normal = "default", hybrid = "hybrid", acc = "acc" })[arg]
    if not pick then
      -- No word cycles: default, hybrid, acc.
      pick = modes.hybrid and "acc" or (modes.acc and "default" or "hybrid")
    end
    modes.hybrid, modes.acc = pick == "hybrid" or nil, pick == "acc" or nil
    say("Fighting set: " .. pick .. ".")
  elseif cmd == "nuke" then
    local acc = arg == "acc" or (arg ~= "power" and not modes.macc)
    modes.macc = acc or nil
    say("Nukes and enfeebles: " .. (acc and "acc" or "power") .. ".")
  elseif cmd == "burst" then
    modes.mb = on_off(arg, modes.mb) or nil
    say("Magic burst gear " .. (modes.mb and "on" or "off") .. ".")
  elseif cmd == "kite" then
    modes.kite = on_off(arg, modes.kite) or nil
    run.rebuild()
    say("Movement gear " .. (modes.kite and "on" or "off") .. ".")
  elseif cmd == "th" then
    modes.th = on_off(arg, modes.th) or nil
    run.rebuild()
    say("Treasure hunter gear " .. (modes.th and "on" or "off") .. ".")
  elseif cmd == "idle" then
    local pick = ({ auto = "auto", regen = "regen", refresh = "refresh", speed = "speed" })[arg] or "auto"
    modes.idle = pick ~= "auto" and pick or nil
    run.rebuild()
    say("Idle: " .. pick .. ".")
  elseif cmd == "pet" then
    local pick = ({ tp = "tp", dt = "dt", acc = "acc" })[arg] or "tp"
    modes.pet = pick ~= "tp" and pick or nil
    say("Pet gear: " .. pick .. ".")
  elseif cmd == "lock" or cmd == "unlock" or cmd == "disable" or cmd == "enable" then
    local on = cmd == "lock" or cmd == "disable"
    local slot = (arg == "" or arg == "all") and "all" or run.slot_index(arg)
    if slot == nil then
      say("Usage: /vg lock <slot> (or all), for example /vg lock neck")
      return
    end
    run.lock(slot, on)
    say(((slot == "all") and "Every slot" or run.SLOT_LABEL[slot]) .. (on and " locked" or " unlocked") .. " for "
      .. (run.state.job or "this job") .. ".")
  elseif cmd == "weapon" then
    local slot = ({ main = "main", sub = "sub", range = "range" })[arg]
    local item = table.concat(args, " ", 3)
    if not slot or item == "" then
      say("Usage: /vg weapon main|sub|range <item> (or none to leave the slot alone)")
      return
    end
    local ok, name = run.set_weapon(slot, item)
    if not ok then
      say(item .. " is not in the bags you wear from.")
    else
      say(slot .. (name and (": " .. name .. ", in every set.") or " is left alone."))
    end
  elseif cmd == "why" then
    local set, slot = run.find_set(args[2]), run.slot_index(args[3])
    if not set or not slot then
      say("Usage: /vg why <set> <slot>, for example /vg why TP head")
      return
    end
    local r = run.why(set, slot)
    if not r then
      say(set .. " is not built yet; try again in a moment.")
      return
    end
    say(string.format("%s %s: %s%s.", r.def.label or set, run.SLOT_LABEL[slot], r.won or "nothing",
      r.how and (" (" .. (r.how == "bis" and "closest to the best in slot" or "highest score") .. ")") or ""))
    local shown = 0
    for _, c in ipairs(r.list) do
      if c.name ~= r.won and shown < 3 then
        shown = shown + 1
        say(string.format("  behind it: %s (%.1f)", c.name, c.score))
      end
    end
  elseif cmd == "upgrades" then
    local list = run.upgrades()
    if #list == 0 then
      say("Nothing in storage would win a slot of your sets.")
    end
    for _, u in ipairs(list) do say(string.format("%s (%s): %s %s", u.name, u.bag, u.set, u.slot)) end
  elseif cmd == "set" then
    local set, slot, item = run.find_set(args[2]), run.slot_index(args[3]), table.concat(args, " ", 4)
    if not set or not slot or item == "" then
      say("Usage: /vg set <set> <slot> <item | auto>, for example /vg set TP head Walahra Turban")
      return
    end
    local ok, name = run.set_slot(set, run.SLOT_NAME[slot], item)
    say(ok and (set .. " " .. run.SLOT_LABEL[slot] .. ": " .. (name or "automatic") .. ".")
      or (item .. " is not in the bags you wear from."))
  elseif cmd == "wear" then
    local set = run.find_set(table.concat(args, " ", 2))
    if not set then
      say("Usage: /vg wear <set>, for example /vg wear Idle")
      return
    end
    run.wear_set(set)
    say("Wearing " .. set .. ".")
  elseif cmd == "trusts" then
    local rest = {}
    for i = 2, #args do rest[#rest + 1] = args[i] end
    trusts.command(rest)
  elseif cmd == "mode" then
    say(run.toggle(arg ~= "" and arg or "off"))
  elseif cmd == "file" then
    say(ctx.file() or "no gear file for this job (ashitacast/ in its data folder): the set builder's sets")
  elseif cmd == "reload" then
    ctx.reload()
    say(ctx.file() or "no gear file for this job: the set builder's sets")
  else
    say("/vg " .. cmd .. " is not in this port yet; /vg help lists what is.")
  end
end

-- /gs, as vanagear takes it for players coming from GearSwap: `/gs c <word>` is `/vg <word>` (Mote's mode names land on
-- vanagear's), `/gs equip <set>` wears a set, `/gs reload` reads the file again; anything else is a /vg word.
function M.gs(args, ctx)
  local cmd = (args[1] or ""):lower()
  local function vg(...) M.command({ ... }, ctx) end
  if cmd == "c" then
    local rest = {}
    for i = 2, #args do rest[#rest + 1] = args[i] end
    local first = (rest[1] or ""):lower()
    local mode, value = (rest[2] or ""):lower(), rest[3]
    if first == "cycle" or first == "set" then
      if mode == "offensemode" or mode == "hybridmode" or mode == "weaponskillmode" or mode == "rangedmode" then
        vg("tp", value or "")
      elseif mode == "idlemode" then
        vg("idle", value or "")
      elseif mode == "castingmode" then
        vg("nuke", (value and value:lower() ~= "normal") and "acc" or "")
      elseif mode == "defensemode" or mode == "physicaldefensemode" or mode == "magicaldefensemode" then
        vg("dt", (value and value:lower() == "none") and "off" or "on")
      else
        M.command(rest, ctx)
      end
    elseif first == "toggle" and mode == "kiting" then
      vg("kite")
    elseif first == "reset" and mode == "defensemode" then
      vg("dt", "off")
    elseif first == "update" then
      say("Sets are current.")
    else
      M.command(rest, ctx)
    end
  elseif cmd == "equip" then
    M.command({ "wear", table.concat(args, " ", 2) }, ctx)
  elseif cmd == "reload" or cmd == "r" then
    vg("reload")
  elseif cmd == "validate" or cmd == "export" then
    say("/gs " .. cmd .. " is not in this port yet.")
  else
    M.command(args, ctx)
  end
end

return M
