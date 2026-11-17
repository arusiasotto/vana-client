-- //vg window: your sets and trust gear tabs.

local run = require("src.build.run")
local pick = require("src.build.pick")
local sets = require("src.build.sets")
local trust_page = require("src.trust_window")
local grid = require("src.equip_grid")

local M = {}
M.WIN = "gsvg"
local PAGE = 1
local SLOT_LABEL = { [0] = "Main", "Sub", "Range", "Ammo", "Head", "Body", "Hands", "Legs", "Feet", "Neck", "Waist",
  "L. Ear", "R. Ear", "L. Ring", "R. Ring", "Back" }
local BAG_LABEL = { [1] = "Mog Safe", [2] = "Storage", [4] = "Mog Locker", [5] = "Mog Satchel", [6] = "Mog Sack",
  [7] = "Mog Case", [9] = "Mog Safe 2" }
local GOOD, FAIR, LOW = { 240, 170, 60, 255 }, { 230, 220, 110, 255 }, { 120, 170, 230, 255 }

local view = { tab = 1, set = 1, slot = nil, job = nil }

local function preferred_set_index(list)
  local job, lvl = run.state.job, run.state.level or 99
  if job == "RDM" and lvl <= 30 then
    for i, s in ipairs(list) do
      if s == "Tp_Default" then return i end
    end
  end
  for i, s in ipairs(list) do
    if s == "Idle" then return i end
  end
  for i, s in ipairs(list) do
    if s == "Tp_Default" then return i end
  end
  return 1
end

local function sync_set_view(list)
  local job = run.state.job
  if job ~= view.job then
    view.job, view.set = job, preferred_set_index(list)
  else
    view.set = math.max(1, math.min(view.set, math.max(1, #list)))
  end
end

function M.apply_layout_scale()
  local pct = settings.get("grid_scale")
  if pct == nil then pct = 150 end
  return grid.configure(pct / 100)
end

-- Your-sets tab: centres the grid with side margin.
function M.canvas_w()
  return math.max(560, grid.SIZE + 40)
end

-- Trust tab: equipment grid on the left, Uses panel on the right (same row).
M.USES_GAP = 12
M.USES_W = 260

function M.trust_canvas_w()
  return grid.SIZE + M.USES_GAP + M.USES_W
end

local function grid_click_x()
  return grid.offset_x(M.canvas_w())
end

local function page(e)
  e.page = PAGE
  return e
end

function M.tab() return view.tab end

local function item_name(id)
  local r = id and pick.item(id)
  return r and r.name or "-"
end

local LABEL = { mab = "MAB", macc = "Mag. Acc.", acc = "Acc.", att = "Atk.", racc = "Rng. Acc.", ratt = "Rng. Atk.",
  stp = "Store TP", da = "Dbl. Atk.", ta = "Tpl. Atk.", qa = "Quad. Atk.", wsd = "WS Dmg.", fc = "Fast Cast",
  dt = "DT", pdt = "PDT", mdt = "MDT", mdb = "MDB", meva = "Mag. Eva.", haste = "Haste", crit = "Crit.",
  cure = "Cure Pot.", cure2 = "Cure Pot. II", refresh = "Refresh", regen = "Regen", enmity = "Enmity",
  mbb = "MB Dmg.", mbb2 = "MB Dmg. II", mdmg = "Mag. Dmg.", move = "Move" }
local PCT = { da = true, ta = true, qa = true, wsd = true, fc = true, dt = true, pdt = true, mdt = true, haste = true,
  crit = true, cure = true, cure2 = true, move = true }
local function summary(s, def, n)
  if not s then return "" end
  local list = {}
  for k, w in pairs(def.weights) do
    local v = k:find(".", 1, true) and 0 or (s.stats[k] or 0)
    if v ~= 0 and w * v > 0 then list[#list + 1] = { k = k, v = v, score = w * v } end
  end
  table.sort(list, function(a, b) return a.score > b.score end)
  local out = {}
  for i = 1, math.min(n or 4, #list) do
    local x = list[i]
    out[#out + 1] = (LABEL[x.k] or x.k:upper()) .. (x.v > 0 and "+" or "") .. x.v .. (PCT[x.k] and "%" or "")
  end
  return table.concat(out, " ")
end

local function job_sets()
  return run.state.job and run.job_sets(run.state.job) or {}
end

local function set_label(name)
  local def = run.set_def(name)
  return def and def.label or name
end

local function current()
  local list = job_sets()
  sync_set_view(list)
  local name = list[view.set] or list[1]
  return name, name and run.set_def(name)
end

local function held(name)
  for _, o in ipairs(run.state.owned or {}) do
    local rec = pick.item(o.id)
    if rec and rec.name == name then return true end
  end
  return false
end

local function id_of_name(name)
  local ids = run.state.names and run.state.names[name]
  return ids and ids[1]
end

local function player_grid(name, def, r)
  local hand = run.hand(run.state.job, name)
  local ids, labels, tips, hand_m = {}, {}, {}, {}
  for slot = 0, 15 do
    local o = r and r.slots[slot]
    local h = hand[pick.SLOT_NAMES[slot]]
    local title = SLOT_LABEL[slot]
    if h then
      ids[slot] = id_of_name(h.name)
      labels[slot] = h.name
      tips[slot] = { title = title, text = h.name .. (held(h.name) and "" or " (not in inventory)") }
      hand_m[slot] = true
    elseif o and o.pick and o.pick.id then
      ids[slot] = o.pick.id
      local extra = ""
      if o.share and not (r and r.engine) then
        extra = (" — %d%% of BIS"):format(math.floor(o.share * 100 + 0.5))
      end
      tips[slot] = { title = title, text = item_name(o.pick.id) .. extra }
    elseif not (sets.MAGE_JOBS[run.state.job] and not sets.MELEE_SETS[name] and not def.ws) and slot <= 2 then
      labels[slot] = "(kept)"
      tips[slot] = { title = title, text = "Your weapon — left alone for TP." }
    else
      tips[slot] = { title = title, text = "Empty" }
    end
  end
  local draw = grid.draw({ ids = ids, labels = labels, tips = tips, hand = hand_m, selected = view.slot }, M.canvas_w())
  return draw
end

local function warnings(name, def, r)
  local out = {}
  local p = run.H.player() or {}
  local me = run.H.me() or {}
  for _, e in ipairs(run.state.elsewhere or {}) do
    local rec = pick.item(e.id)
    for slot = 0, 15 do
      local o = r and r.slots[slot]
      if o and pick.fits(rec, slot, p.main_job or 0, me.race, run.state.level, p.sub_job) then
        local mine = o.pick and (o.pick.owned and run.rate(name, def, o.pick.owned, slot) or pick.score(o.pick.s, def)) or 0
        if run.rate(name, def, e, slot) > mine and #out < 3 then
          out[#out + 1] = ("%s is in your %s (%s)."):format(rec.name, BAG_LABEL[e.bag] or "bags", SLOT_LABEL[slot])
          break
        end
      end
    end
  end
  return table.concat(out, " ")
end

local function score_line(r)
  if not r then return "Reading your gear and the item list...", nil end
  if r.engine then
    return ("Set score %.1f (vanagear's engine)."):format(r.score or 0), GOOD
  end
  local reach = r.reach_score or 0
  if reach <= 0 then return ("Score %d"):format(math.floor(r.score + 0.5)), nil end
  local pct = r.score / reach * 100
  local colour = pct >= 90 and GOOD or (pct >= 70 and FAIR or LOW)
  return ("Score %d: %d%% of the best for level %d (%d); best in slot at %d: %d"):format(math.floor(r.score + 0.5),
    math.floor(pct + 0.5), run.state.level or 0, math.floor(reach + 0.5), run.cap(), math.floor(r.ref_score + 0.5)), colour
end

local function detail(name, def, r)
  if view.slot == nil then
    return "Click a slot in the grid to pick a piece or see how it compares to BIS."
  end
  if not r then return "" end
  local hand = run.hand(run.state.job, name)
  local h = hand[pick.SLOT_NAMES[view.slot]]
  if h then return SLOT_LABEL[view.slot] .. ": " .. h.name .. " (picked by hand)" end
  local o = r.slots[view.slot]
  if not o then return "" end
  local parts = { SLOT_LABEL[view.slot] .. ":" }
  if o.pick then parts[#parts + 1] = item_name(o.pick.id) .. " " .. summary(o.pick.s, def) end
  if o.ref then parts[#parts + 1] = "| best in slot " .. item_name(o.ref.id) .. " " .. summary(o.ref.s, def) end
  if o.worth then parts[#parts + 1] = "| worth getting " .. item_name(o.worth.id) .. " " .. summary(o.worth.s, def) end
  return table.concat(parts, " ")
end

local function player_elements()
  local list = job_sets()
  local name, def = current()
  local labels = {}
  for i, s in ipairs(list) do labels[i] = set_label(s) end
  local r = name and run.state.built[name]
  if name and not r then run.want_first(name) end
  local score, colour = score_line(r)
  local eng = r and r.engine
  local out = {
    page({ type = "choice", id = "active", label = "Wear These Sets", items = { "Off", "On" }, at = run.active() and 2 or 1,
      tip = "On: wears these sets around your actions and between them. Off: they are only shown." }),
    -- Looks like a dropdown; opens ui.menu, which scrolls when the job has many sets (the built-in dropdown does not).
    page({ type = "buttons", id = "set", label = "Set", items = {
      #list > 0 and ("%s (%d/%d)"):format(labels[view.set] or "-", view.set, #list) or "-" },
      tip = "The job's sets: click to open the scrollable list. Engaged melee uses Tp_Default / Tp_Acc / Tp_Hybrid; "
        .. "Tp_Proc is an empty slot you fill by hand, not the fighting set." }),
    page({ type = "text", id = "when", text = def and ("Worn " .. (def.when or "") .. ".") or "", dim = true }),
    page({ type = "text", id = "score", text = score, colour = colour or false }),
    page({ type = "canvas", id = "gear", w = M.canvas_w(), h = grid.SIZE,
      draw = name and def and player_grid(name, def, r) or {},
      tip = "Equipment layout as in the game menu. Click a cell to pick that slot." }),
    page({ type = "text", id = "detail", text = name and def and detail(name, def, r) or "", dim = true }),
  }
  if not eng then
    out[#out + 1] = page({ type = "text", id = "warn", text = name and def and warnings(name, def, r) or "", colour = FAIR })
  end
  out[#out + 1] = page({ type = "buttons", id = "actions", items = { "Rebuild", "Wear Now", "Close" } })
  return out
end

function M.draw()
  M.apply_layout_scale()
  local list = job_sets()
  sync_set_view(list)
  local title = run.state.job and ("vanagear: %s %d"):format(run.state.job, run.state.level or 0) or "vanagear"
  local els = { { type = "tabs", id = "tabs", items = { "Your sets", "Trust gear" }, at = view.tab } }
  for _, e in ipairs(player_elements()) do els[#els + 1] = e end
  for _, e in ipairs(trust_page.elements()) do els[#els + 1] = e end
  ui.window(M.WIN, {
    title = title, width = math.max(M.canvas_w(), M.trust_canvas_w() + 32),
    help = "Your sets and trust gear, built from what you carry. Grid scale is on this mod's Extras page.",
    elements = els,
  })
end

local function alternatives(name, def, slot)
  local r = run.state.built[name]
  local o = r and r.slots[slot]
  local p = run.H.player() or {}
  local me = run.H.me() or {}
  local seen, cands = {}, {}
  for _, e in ipairs(run.state.owned or {}) do
    local rec = pick.item(e.id)
    if pick.fits(rec, slot, p.main_job or 0, me.race, run.state.level, p.sub_job) and not seen[e.key] then
      seen[e.key] = true
      local s = pick.stats_of(e.id, e.augments)
      local sh = o and o.ref and (pick.share(s, o.ref.s, def)) or 0
      cands[#cands + 1] = { name = rec.name, augments = e.augments, share = sh, score = run.rate(name, def, e, slot),
        engine = r and r.engine }
    end
  end
  table.sort(cands, function(a, b)
    if a.share ~= b.share then return a.share > b.share end
    return a.score > b.score
  end)
  return cands
end

local function choose_slot(slot)
  local name, def = current()
  if not name then return end
  local cands = alternatives(name, def, slot)
  local items = { "Automatic" }
  for _, c in ipairs(cands) do
    items[#items + 1] = c.engine and ("%s (%.1f)"):format(c.name, c.score)
      or ("%s (%d%%)"):format(c.name, math.floor(c.share * 100 + 0.5))
  end
  ui.menu(items, function(i)
    if not i then return end
    local hand = run.hand(run.state.job, name)
    if i == 1 then
      hand[pick.SLOT_NAMES[slot]] = nil
    else
      local c = cands[i - 1]
      hand[pick.SLOT_NAMES[slot]] = { name = c.name, augments = c.augments }
    end
    M.draw()
  end)
end

function M.open_tab(tab)
  view.tab = tab or 1
  M.draw()
  if not ui.is_open(M.WIN) then ui.open(M.WIN) end
end

function M.toggle()
  if ui.is_open(M.WIN) then ui.close(M.WIN) return end
  view.tab = 1
  M.open_tab(1)
end

function M.redraw()
  if ui.is_open(M.WIN) then M.draw() end
end

function M.install()
  ui.on(M.WIN, function(_, e)
    local redraw = function() M.draw() end
    if e.kind == "set" and e.id == "tabs" then
      view.tab = e.index
      redraw()
    elseif e.id and e.id:sub(1, 2) == "t_" then
      trust_page.on_event(e, redraw)
    elseif e.kind == "set" and e.id == "active" then
      run.set_active(e.index == 2)
      redraw()
    elseif e.kind == "press" and e.id == "set" then
      local labels = {}
      for i, s in ipairs(job_sets()) do labels[i] = set_label(s) end
      ui.menu(labels, function(i)
        if not i then return end
        view.set, view.slot = i, nil
        redraw()
      end)
    elseif e.kind == "click" and e.id == "gear" and e.button == "left" then
      local slot = grid.hit(e.x - grid_click_x(), e.y)
      if slot then
        view.slot = slot
        redraw()
        choose_slot(slot)
      end
    elseif e.kind == "press" and e.id == "actions" then
      if e.index == 1 then
        run.rebuild()
        redraw()
      elseif e.index == 2 then
        local name = current()
        if name then run.wear_set(name) end
      else
        ui.close(M.WIN)
      end
    end
  end)
end

return M