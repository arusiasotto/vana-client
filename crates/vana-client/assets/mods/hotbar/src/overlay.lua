-- See-through hotbars and crossbars on the HUD. No window and no canvas: each slot is a
-- translucent rectangle with an icon, a key hint and a recast shade. Clicks, drags and
-- palette drops use hud.on. The palette and the drag ghost keep their own element ids.

local data = require("src.data")
local actions = require("src.actions")
local ghost = require("src.ghost")

local function palette() return require("src.palette") end
local chooser = require("src.chooser")
local slotview = require("src.slotview")

local M = {}

local EDGE_HELD = { 228, 192, 119, 210 }
local EDGE_OFF = { 80, 84, 96, 70 }
local EDGE = { 196, 176, 120, 110 }
local DROP = { 255, 214, 120, 220 }
local SHADE = { 0, 0, 0, 165 }
local UNUSABLE = { 6, 8, 14, 165 }
local FLASH = { 255, 236, 190, 120 }
local INK = slotview.TEXT
local GOLD = slotview.GOLD
local GOLD_OFF = { 228, 192, 119, 70 }
local DIMMED = { 140, 140, 150, 255 }

local function slot_round(u, s)
  return math.min(slotview.ROUND * u, s / 2)
end

local live = {}    -- prefix -> { id = true }
local places = {}  -- element id -> { x, y, s, key? }
local drops = {}   -- slot id -> function(lib_id)
local GLOW = { 255, 214, 120 }

function M.on()
  return settings.get("display") == "Overlay"
end

local function screen()
  local scr = hud.screen()
  return scr, scr.ui_scale or 1
end

function M.clear(prefix)
  for id in pairs(live[prefix] or {}) do
    places[id] = nil
    drops[id] = nil
    pcall(hud.off, id)
    pcall(hud.remove, id)
  end
  live[prefix] = nil
end

local function finish(prefix, seen)
  for id in pairs(live[prefix] or {}) do
    if not seen[id] then
      places[id] = nil
      drops[id] = nil
      pcall(hud.off, id)
      pcall(hud.remove, id)
    end
  end
  live[prefix] = seen
end

-- Screen-pixel hit for manager / palette drags onto overlay slots (no bars canvas).
function M.drop_at(x, y, lib_id)
  if not lib_id then return false end
  for id, p in pairs(places) do
    if x >= p.x and x < p.x + p.s and y >= p.y and y < p.y + p.s then
      local fn = drops[id]
      if fn then fn(lib_id); return true end
    end
  end
  return false
end

function M.hover_at(x, y)
  for _, p in pairs(places) do
    if x >= p.x and x < p.x + p.s and y >= p.y and y < p.y + p.s then
      return p.key
    end
  end
end

-- Window pixels for a canvas or HUD event; falls back to input.mouse().
function M.screen_xy(e)
  if e and e.sx and e.sy then return e.sx, e.sy end
  local m = input.mouse()
  if m and m.x and m.y then return m.x, m.y end
end

local function emit(seen, kind, id, spec)
  hud[kind](id, spec)
  seen[id] = true
end

-- Where a group list opens: above the slot, in window pixels.
function M.list_at(id)
  local s = places[id]
  if not s then return nil end
  local _, u = screen()
  return { x = s.x + s.s / 2 - chooser.WIDTH * u / 2, y = s.y - 6 * u, above = true }
end

local function clock_text(left)
  local secs = math.ceil(left)
  return secs >= 60 and ("%d:%02d"):format(secs // 60, secs % 60) or tostring(secs)
end

-- One slot, matching slotview.draw_slot geometry at HUD scale.
local function slot(seen, id, cell, o)
  local x, y, s, u = o.x, o.y, o.s, o.u
  local macro, act, sh = o.macro, o.act, o.shade
  local hover = o.hover
  local dropping = palette().dragging and hover
  local rnd = slot_round(u, s)
  local lw = slotview.EDGE_W * u
  local fill = hover and slotview.KEY_HOVER or (macro and slotview.KEY or slotview.EMPTY_KEY)
  local edge = dropping and DROP or o.edge or (macro and EDGE or slotview.EMPTY_EDGE)
  places[id] = { x = x, y = y, s = s, key = o.key }
  drops[id] = o.drop and function(lib_id) o.drop(cell, lib_id) end or nil
  local glow = o.glow
  if o.suggested and glow then
    local depth = s * (0.22 + 0.06 * glow)
    local rings = 10
    local step_w = depth / rings
    for k = 0, rings - 1 do
      local t = k / rings
      local inset = k * step_w
      local ir = math.max(0, rnd - inset)
      emit(seen, "rect", id .. "_sg" .. k, { x = x + inset, y = y + inset, w = s - 2 * inset, h = s - 2 * inset,
        round = ir, line = step_w + 0.5, colour = { GLOW[1], GLOW[2], GLOW[3],
        math.floor((55 + 55 * glow) * (1 - t) * (1 - t)) }, layer = 1 })
    end
    emit(seen, "rect", id .. "_sg_o", { x = x - 3 * u, y = y - 3 * u, w = s + 6 * u, h = s + 6 * u,
      round = rnd + 3 * u, line = 2 * u, colour = { GLOW[1], GLOW[2], GLOW[3], math.floor(25 + 45 * glow) }, layer = 1 })
    emit(seen, "rect", id .. "_sg_i", { x = x - 1 * u, y = y - 1 * u, w = s + 2 * u, h = s + 2 * u,
      round = rnd + 1 * u, line = 1.5 * u, colour = { GLOW[1], GLOW[2], GLOW[3], math.floor(150 + 90 * glow) }, layer = 1 })
  end
  emit(seen, "rect", id, { x = x, y = y, w = s, h = s, round = rnd, colour = fill, layer = 2,
    tip = macro and { title = data.trim(macro.name) ~= "" and macro.name or (o.fallback or ""),
      text = data.tip_text(macro) } or nil })
  emit(seen, "rect", id .. "_e", { x = x, y = y, w = s, h = s, round = rnd, line = lw, colour = edge, layer = 3 })
  if act then
    local isz = math.floor(s * slotview.ICON_FRAC)
    emit(seen, "icon", id .. "_i", { x = x + (s - isz) / 2, y = y + slotview.ICON_TOP * u, size = isz,
      kind = act.kind, id = act.id, layer = 4, colour = o.dim and { 150, 150, 150, 255 } or nil })
  end
  if macro and macro.group then
    local ax = x + s - 9 * u
    local base, tip = y + 10 * u, y + 6 * u
    if o.up then base, tip = tip, base end
    if hud.tri then
      emit(seen, "tri", id .. "_g", { x = ax, y = base, x1 = -4 * u, y1 = 0, x2 = 4 * u, y2 = 0,
        x3 = 0, y3 = tip - base, colour = GOLD, layer = 6 })
    else
      -- Clients before hud.tri: an ASCII chevron (the HUD font has no triangle glyph).
      emit(seen, "text", id .. "_g", { x = ax, y = math.min(base, tip), text = o.up and "v" or "^", size = 0.62,
        font = "bold", align = "center", colour = GOLD, layer = 6 })
    end
  end
  if sh and sh.left > 0 then
    emit(seen, "rect", id .. "_sh", { x = x, y = y, w = s, h = math.max(2, s * sh.frac), round = rnd,
      colour = SHADE, layer = 5 })
    emit(seen, "text", id .. "_cd", { x = x + s / 2, y = y + s / 2 - 11 * u, text = clock_text(sh.left),
      size = 1.45, font = "bold", align = "center", colour = { 255, 236, 180, 255 }, layer = 7 })
  elseif sh and not sh.usable then
    emit(seen, "rect", id .. "_sh", { x = x, y = y, w = s, h = s, round = rnd, colour = UNUSABLE, layer = 5 })
  end
  if macro then
    local label = data.display_label(macro)
    local ls, lh = slotview.LABEL, slotview.LABEL_LINE * u
    if act then
      emit(seen, "text", id .. "_l", { x = x + s / 2, y = y + s - lh - 2 * u,
        text = slotview.fit(label:match("^[^\n]*") or "", s / u), size = ls, align = "center", colour = INK, layer = 6 })
    else
      local lines = {}
      for line in label:gmatch("[^\n]+") do lines[#lines + 1] = line end
      local top = y + (s - #lines * lh) / 2
      for n, line in ipairs(lines) do
        emit(seen, "text", id .. "_l" .. n, { x = x + s / 2, y = top + (n - 1) * lh,
          text = slotview.fit(line, s / u), size = ls, align = "center", colour = INK, layer = 6 })
      end
    end
  end
  if o.hint then
    emit(seen, "text", id .. "_k", { x = x + slotview.HINT_PAD * u, y = y + 2 * u, text = o.hint,
      size = slotview.HINT_SIZE, colour = slotview.MUTED, layer = 6 })
  end
  if o.st and o.st.flash[o.key] and o.st.flash[o.key] > os.clock() then
    emit(seen, "rect", id .. "_f", { x = x, y = y, w = s, h = s, round = rnd, colour = FLASH, layer = 8 })
  end
  hud.on(id, function(_, e)
    if e.kind == "mouse_enter" then
      if o.st.hover ~= o.key then o.st.hover = o.key; o.redraw() end
    elseif e.kind == "mouse_leave" then
      if o.st.hover == o.key then o.st.hover = nil; o.redraw() end
    elseif e.kind == "click" then
      if e.button == "right" then
        o.menu(cell)
      else
        slotview.flash(o.st, o.key, o.redraw)
        o.fire(cell)
      end
    elseif e.kind == "drag_start" then
      if not macro then return end
      local label = data.display_label(macro)
      ghost.start(e.x, e.y, s, act, label)
    elseif e.kind == "drag" then
      if not e.window then ghost.move(e.x, e.y) end
    elseif e.kind == "drag_end" then
      ghost.stop()
      local to = o.parse(e.over)
      if to and not o.same(cell, to) then o.swap(cell, to) end
    elseif e.kind == "drop" then
      local pal = palette()
      local lib = pal.dragged_id(e.from) or pal.last
      if lib then o.drop(cell, lib) end
    end
  end)
end

local function pocket_slot(seen, id, cell, o)
  local x, y, s, u = o.x, o.y, o.s, o.u
  local hover = o.hover
  local fill = hover and slotview.KEY_HOVER or slotview.KEY
  local edge = o.edge or EDGE
  local short = o.short or "?"
  places[id] = { x = x, y = y, s = s, key = o.key }
  drops[id] = o.drop and function(lib_id) o.drop(cell, lib_id) end or nil
  emit(seen, "rect", id, { x = x, y = y, w = s, h = s, round = s / 2, colour = fill, layer = 2,
    tip = { title = short, text = o.fallback or "" } })
  emit(seen, "rect", id .. "_e", { x = x, y = y, w = s, h = s, round = s / 2, line = slotview.EDGE_W * u,
    colour = edge, layer = 3 })
  emit(seen, "text", id .. "_t", { x = x + s / 2, y = y + s / 2 - 5 * u, text = short,
    size = 0.62, align = "center", colour = o.dim and slotview.MUTED or INK, layer = 4 })
  hud.on(id, function(_, e)
    if e.kind == "mouse_enter" then
      if o.st.hover ~= o.key then o.st.hover = o.key; o.redraw() end
    elseif e.kind == "mouse_leave" then
      if o.st.hover == o.key then o.st.hover = nil; o.redraw() end
    elseif e.kind == "click" then
      if e.button == "right" then
        o.menu(cell)
      else
        slotview.flash(o.st, o.key, o.redraw)
        o.fire(cell)
      end
    end
  end)
end

-- + / - knobs: same 18px circles as the window canvas (slotview.KEY fill, gold ring).
local function knob(seen, id, o)
  local u, r = o.u, o.r
  local d = 2 * r
  local x, y = o.cx - r, o.cy - r
  local ink = not o.live and GOLD_OFF or (o.hover and INK or GOLD)
  emit(seen, "rect", id, { x = x, y = y, w = d, h = d, round = r, colour = slotview.KEY, layer = 2,
    tip = { title = "", text = o.tip } })
  emit(seen, "rect", id .. "_e", { x = x, y = y, w = d, h = d, round = r, line = slotview.EDGE_W * u,
    colour = ink, layer = 3 })
  local a = r * 0.45
  local t = math.max(1, 1.6 * u)
  local bw, bh = 2 * a, t
  emit(seen, "rect", id .. "_h", { x = o.cx - a, y = o.cy - t / 2, w = bw, h = bh, round = t / 2,
    colour = ink, layer = 4 })
  if o.plus then
    emit(seen, "rect", id .. "_v", { x = o.cx - t / 2, y = o.cy - a, w = t, h = 2 * a, round = t / 2,
      colour = ink, layer = 4 })
  end
  local function on_knob(_, e)
    if e.kind == "mouse_enter" then
      if o.st.hover ~= o.key then o.st.hover = o.key; o.redraw() end
    elseif e.kind == "mouse_leave" then
      if o.st.hover == o.key then o.st.hover = nil; o.redraw() end
    elseif e.kind == "click" and e.button ~= "right" then
      o.click()
    end
  end
  local parts = { id, id .. "_e", id .. "_h" }
  if o.plus then parts[#parts + 1] = id .. "_v" end
  for _, part in ipairs(parts) do hud.on(part, on_knob) end
end

-- Keyboard bars, centred, bar 1 nearest the bottom. `rows` is how many to draw.
function M.bars(p)
  local scr, u = screen()
  local size = math.floor(p.size * u)
  local gap = math.floor(p.gap * u)
  local rev = math.max(p.reveal or p.rows or 1, 1)
  local rows = math.min(p.bars or math.ceil(rev), math.max(1, math.ceil(rev)))
  local w = p.slots * size + math.max(0, p.slots - 1) * gap
  local x0 = math.floor((scr.width - w) / 2)
  local margin = math.floor(36 * u)
  local block_h = rev * size + math.max(0, rev - 1) * gap
  local y_base = scr.height - margin - block_h
  local seen = {}
  local function id_of(b, i) return "ovb_" .. b .. "_" .. i end
  local function parse(id)
    local b, i = id and id:match("^ovb_(%d+)_(%d+)$")
    if b then return { b = tonumber(b), i = tonumber(i) } end
  end
  for b = 1, rows do
    if b > math.ceil(rev) then break end
    local y = p.top_dock and (y_base + (b - 1) * (size + gap))
      or (y_base + block_h - size - (b - 1) * (size + gap))
    if p.top_dock then
      if y >= y_base + block_h then break end
    elseif y + size > y_base + block_h then
      break
    end
    for i = 1, p.slots do
      local key = b .. ":" .. i
      local cell = p.eff[b] and p.eff[b][i]
      local macro = cell and cell.macro
      local act = macro and actions.of(macro)
      slot(seen, id_of(b, i), { b = b, i = i }, {
        x = x0 + (i - 1) * (size + gap), y = y, s = size, u = u, up = p.top_dock,
        macro = macro, act = act, shade = p.shades[key],
        hover = p.st.hover == key, hint = p.show_keys and p.hint(b, i) or nil, fallback = p.hint(b, i),
        edge = cell and macro and p.edge[cell.from] or nil, st = p.st, key = key, redraw = p.redraw,
        fire = p.fire, menu = p.menu, swap = p.swap, drop = p.drop,
        suggested = p.suggested and macro and p.suggested(macro, act), glow = p.glow,
        parse = parse, same = function(a, b) return a.b == b.b and a.i == b.i end,
      })
    end
  end
  local pad = math.floor((p.pad or 8) * u)
  local r = math.floor((p.btn or 18) * u / 2)
  local cx = x0 + w + pad + r
  local bottom = scr.height - margin
  local plus_cy, minus_cy
  if p.top_dock then
    local top = bottom - block_h
    plus_cy = top + pad + r
    minus_cy = top + pad + 3 * r + 4 * u
  else
    plus_cy = bottom - pad - 3 * r - 4 * u
    minus_cy = bottom - pad - r
  end
  knob(seen, "ovb_plus", { cx = cx, cy = plus_cy, r = r, u = u, plus = true,
    tip = "Show another bar", live = p.shown < p.most, hover = p.st.hover == "plus", key = "plus",
    st = p.st, redraw = p.redraw, click = function() p.other("plus") end })
  knob(seen, "ovb_minus", { cx = cx, cy = minus_cy, r = r, u = u, plus = false,
    tip = "Show one bar fewer", live = p.shown > 1, hover = p.st.hover == "minus", key = "minus",
    st = p.st, redraw = p.redraw, click = function() p.other("minus") end })
  finish("ovb", seen)
end

-- Folded crossbars: one HUD button opens the manager (gamepad auto-hide, no trigger held).
function M.idle_manager(p)
  local scr, u = screen()
  local w, h = math.floor(120 * u), math.floor(24 * u)
  local x = math.floor((scr.width - w) / 2)
  local y = scr.height - math.floor(36 * u) - h
  local seen = {}
  local id = "ovp_idle"
  local fill = p.st.hover == "idle" and slotview.KEY_HOVER or slotview.KEY
  emit(seen, "rect", id, { x = x, y = y, w = w, h = h, round = math.floor(7 * u), colour = fill, layer = 2,
    tip = { title = "", text = "Open the hotbar manager" } })
  emit(seen, "rect", id .. "_e", { x = x, y = y, w = w, h = h, round = math.floor(7 * u),
    line = slotview.EDGE_W * u, colour = p.st.hover == "idle" and EDGE_HELD or EDGE, layer = 3 })
  emit(seen, "text", id .. "_t", { x = x + w / 2, y = y + math.floor(5 * u), text = "Open Manager",
    size = 0.9, align = "center", colour = p.st.hover == "idle" and GOLD or INK, layer = 4 })
  hud.on(id, function(_, e)
    if e.kind == "mouse_enter" then
      if p.st.hover ~= "idle" then p.st.hover = "idle"; p.redraw() end
    elseif e.kind == "mouse_leave" then
      if p.st.hover == "idle" then p.st.hover = nil; p.redraw() end
    elseif e.kind == "click" and e.button ~= "right" then
      p.click()
    end
  end)
  finish("ovp", seen)
end

-- Crossbar slots already laid out in canvas units. Scaled and set on the bottom centre.
function M.crossbars(p)
  local scr, u = screen()
  local x0 = math.floor((scr.width - p.width * u) / 2)
  local y0 = math.floor(scr.height - p.height * u - 36 * u)
  local seen = {}
  if p.heading then
    emit(seen, "text", "ovp_head", { x = math.floor(scr.width / 2), y = y0 - math.floor(18 * u), text = p.heading,
      size = 0.9, align = "center", colour = GOLD, layer = 4 })
  end
  local active = p.held
  local function id_of(sl) return "ovp_" .. sl.side .. "_" .. sl.button end
  local function parse(id)
    local side, button = id and id:match("^ovp_([^_]+)_(.+)$")
    if side and button ~= "idle" then return { side = side, button = button } end
  end
  for _, side in ipairs(p.sides) do
    local lit = active == nil or active == side
    local id = "ovp_name_" .. side
    emit(seen, "text", id, { x = x0 + (p.side_x[side] + p.side_w / 2) * u, y = y0 + p.side_y[side] * u,
      text = p.names[side], size = 0.9, align = "center", colour = lit and GOLD or DIMMED, layer = 4 })
  end
  for _, sl in ipairs(p.slots) do
    local key = sl.side .. ":" .. sl.button
    local macro = p.cells[key]
    local fake = p.fake and p.fake[sl.button]
    if fake then macro = { name = p.labels[sl.button], lines = {} } end
    local lit = active == nil or active == sl.side
    local edge = p.slot_edge and p.slot_edge(sl, macro, lit, active == sl.side)
      or (active == sl.side and EDGE_HELD or (not lit and EDGE_OFF) or (macro and EDGE or nil))
    local tip = fake and (sl.button == "mgr" and "Manager (Start)" or "Macro palette (Select)") or p.labels[sl.button]
    local sx, sy, su = x0 + sl.x * u, y0 + sl.y * u, math.floor(p.size * u)
    if fake and sl.pocket then
      su = math.floor(sl.pocket * u)
      local short = (p.pocket_short and p.pocket_short[sl.button]) or p.labels[sl.button]
      pocket_slot(seen, id_of(sl), { side = sl.side, button = sl.button }, {
        x = sx, y = sy, s = su, u = u, short = short, fallback = tip,
        hover = p.st.hover == key, dim = not lit, edge = edge, st = p.st, key = key, redraw = p.redraw,
        fire = p.fire, menu = p.menu,
      })
    else
      slot(seen, id_of(sl), { side = sl.side, button = sl.button }, {
        x = sx, y = sy, s = su, u = u, up = p.top_dock,
        macro = macro, act = macro and actions.of(macro), shade = p.shades[key], dim = not lit and not fake,
        hover = p.st.hover == key, hint = p.labels[sl.button], fallback = tip,
        edge = edge, st = p.st, key = key, redraw = p.redraw,
        fire = p.fire, menu = p.menu, swap = p.swap, drop = p.drop,
        parse = parse, same = function(a, b) return a.side == b.side and a.button == b.button end,
      })
    end
  end
  finish("ovp", seen)
end

return M
