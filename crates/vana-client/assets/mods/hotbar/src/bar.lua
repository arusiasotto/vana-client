-- The hotbars in an edge window, as the Timers and the training regime are: on a screen edge, dragged along the edges,
-- folding to its tab. Its canvas grows a bar at a time from the edge that stays put: + and - show more or fewer bars,
-- easing the window's height. On the top edge the window keeps its top: bar 1 is the top row, the next ones below it,
-- + and - at the top right. Anywhere else it keeps its bottom: bar 1 is the bottom row, the next ones above it, + and -
-- at the bottom right. The buttons never move. A slot shows its action's icon (or its label), its hotkey, a shade
-- with the seconds left while the action recasts, and its macro in a tip; one whose action cannot be used now is
-- dimmed, and one the battle menu suggests glows. A click fires it, a right click opens its menu, and a slot dragged
-- onto another swaps them; a palette tile dropped on a slot puts that library macro there. Slots the main job's set
-- fills have a gold edge, the sub job's set's a blue one.

local data = require("src.data")
local runner = require("src.runner")
local jobs = require("src.jobs")
local keys = require("src.keys")
local actions = require("src.actions")
local palette = require("src.palette")

local M = {}

-- Set by init.lua: open_manager(), slot_menu(bar, slot, from), changed()
M.hooks = {}

local WIN = "bars"

-- As the modern macro palette's keys: a plain charcoal key, surface under the pointer, a bronze edge (the sub job's
-- set's slots a blue one); an empty slot fainter.
local KEY = { 10, 17, 24, 255 }
local KEY_HOVER = { 20, 33, 44, 255 }
local EMPTY_KEY = { 10, 17, 24, 150 }
local EMPTY_EDGE = { 184, 139, 73, 70 }
local EDGE = { main = { 184, 139, 73, 205 }, sub = { 104, 164, 232, 205 } }
local FLASH = { 255, 236, 190, 120 }
local SHADE = { 0, 0, 0, 165 }
local UNUSABLE = { 6, 8, 14, 165 }
local TEXT = { 236, 230, 214, 255 }
local MUTED = { 196, 188, 170, 230 }
local GLOW = { 255, 214, 120 }
local GHOST = { 255, 255, 255, 140 }
local GHOST_BG = { 20, 24, 38, 120 }
local DROP = { 255, 214, 120, 200 }
local DRAGGED = { 0, 0, 0, 120 }
-- + / -: round knobs as the edge window's fold button, charcoal ringed in gold (the text colour under the pointer).
local GOLD = { 228, 192, 119, 255 }
local GOLD_OFF = { 228, 192, 119, 70 }
local INK = { 236, 230, 214, 255 }

-- A slot's label's text size (of the flyouts' text) and its lines' height.
local LABEL = 0.78
local LABEL_LINE = 13

-- Bars per second while the window grows or shrinks.
local SPEED = 4.5
local PAD = 8

local hidden = false   -- //hb show | hide
local built_sig = nil  -- what the window was made for
local reveal = nil     -- the bars shown now, eased toward wanted()
local geo = nil        -- the layout: size, gap, slots, bars, width, button size
local eff, main, sub = nil, nil, nil
local hover = nil      -- "b:i", "plus" or "minus" under the pointer
local flash = {}       -- "b:i" -> os.clock() until its fire flash ends
local drag = nil       -- {b, i, x, y}: the slot a drag started on and where the pointer is now
local tile_at = nil    -- {x, y}: where a palette tile dragged over the bars is
local suggested = {}   -- "spell:<id>" / "ability:<id>" the battle menu suggests now
local shades = {}      -- "b:i" -> {left, frac, usable} from the last recast tick
local top_dock = false -- docked on the top edge (the dock event): grows down, the buttons at the top

local function opts()
  return {
    bars = math.min(settings.get("bars"), data.MAX_BARS),
    slots = math.min(settings.get("slots"), data.MAX_SLOTS),
    size = settings.get("size"),
    gap = settings.get("gap"),
    show_keys = settings.get("show_keys"),
  }
end

-- How many bars show (1 .. the Bars setting), kept per character.
local function wanted()
  local most = math.min(settings.get("bars"), data.MAX_BARS)
  return math.max(1, math.min(most, tonumber(storage.character.hb_shown) or 1))
end

local function signature()
  local mj, sj = jobs.current()
  local o = opts()
  return table.concat({ tostring(mj), tostring(sj), o.bars, o.slots, o.size, o.gap, tostring(o.show_keys) }, ":")
end

-- Runs the macro in a slot for the current jobs.
function M.fire(bar, slot)
  local mj, sj = jobs.current()
  if not mj then return end
  local macro = data.resolve(mj, sj, bar, slot)
  if macro then runner.run_checked(macro) end
end

local function eased(r)
  local whole = math.floor(r)
  local f = r - whole
  return whole + f * f * (3 - 2 * f)
end

local function height(r)
  local rows = math.max(eased(r), 1)
  return rows * geo.size + (rows - 1) * geo.gap + 2 * PAD
end

-- Bar 1 stands on the edge that stays put; each next bar is further from it (coming into view as the canvas grows).
local function slot_xy(b, i)
  local x = PAD + (i - 1) * (geo.size + geo.gap)
  if top_dock then return x, PAD + (b - 1) * (geo.size + geo.gap) end
  return x, height(reveal or 1) - PAD - geo.size - (b - 1) * (geo.size + geo.gap)
end

-- Whether a slot at y is in view (not into the padding on the growing side).
local function in_view(y, h)
  if top_dock then return y < h - PAD end
  return y + geo.size > PAD
end

-- The + and - knobs' centres: on the edge that stays put.
local function knobs(h)
  local r = geo.btn / 2
  local cx = geo.width - PAD - r
  if top_dock then return cx, PAD + r, PAD + 3 * r + 4 end
  return cx, h - PAD - 3 * r - 4, h - PAD - r
end

-- What is at (x, y) in the canvas: {b, i}, "plus", "minus" or nil.
local function hit(x, y)
  if not geo then return nil end
  local h = height(reveal or 1)
  local r = geo.btn / 2
  local cx, plus_y, minus_y = knobs(h)
  local function on(cy) return (x - cx) ^ 2 + (y - cy) ^ 2 <= (r + 1) ^ 2 end
  if on(minus_y) then return "minus" end
  if on(plus_y) then return "plus" end
  for b = 1, geo.bars do
    for i = 1, geo.slots do
      local sx, sy = slot_xy(b, i)
      if x >= sx and x < sx + geo.size and y >= sy and y < sy + geo.size and sy >= 0 and sy + geo.size <= h then
        return { b = b, i = i }
      end
    end
  end
end

-- A line cut to what fits a slot `w` points wide, 4 clear of each side, at the label's text size (about 6.5 a
-- character at the flyouts' size), with an ellipsis.
local function fit(text, w)
  local n = math.max(1, math.floor((w - 8) / (6.5 * LABEL)))
  if utf8.len(text) and utf8.len(text) > n then
    return text:sub(1, utf8.offset(text, n) - 1) .. "…"
  end
  return text
end

local function key_of(c) return type(c) == "table" and (c.b .. ":" .. c.i) or c end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function draw()
  if not geo or not eff then return end
  local d = {}
  local function add(c) d[#d + 1] = c end
  local s, round = geo.size, 7
  local h = height(reveal or 1)
  local glow = 0.5 + 0.5 * math.sin(os.clock() * 3.2)
  local now = os.clock()
  for b = 1, geo.bars do
    for i = 1, geo.slots do
      local x, y = slot_xy(b, i)
      -- Only where it reaches past the padding on the growing side: a hidden bar's edge never peeks in.
      if in_view(y, h) then
        local key = b .. ":" .. i
        local cell = eff[b] and eff[b][i]
        local macro = cell and cell.macro
        local act = macro and actions.of(macro)
        add({ type = "rect", x = x, y = y, w = s, h = s, round = round,
          colour = hover == key and KEY_HOVER or (macro and KEY or EMPTY_KEY) })
        add({ type = "rect", x = x, y = y, w = s, h = s, round = round, line = 1.5,
          colour = macro and EDGE[cell.from] or EMPTY_EDGE })
        if act then
          local isz = math.floor(s * 0.58)
          add({ type = "icon", x = x + (s - isz) / 2, y = y + 4, size = isz, kind = act.kind, id = act.id })
        end
        local sh = shades[key]
        if sh and sh.left > 0 then
          add({ type = "rect", x = x, y = y, w = s, h = math.max(2, s * sh.frac), round = round, colour = SHADE })
        elseif sh and not sh.usable then
          add({ type = "rect", x = x, y = y, w = s, h = s, round = round, colour = UNUSABLE })
        end
        if macro then
          local label = data.display_label(macro)
          if act then
            add({ type = "text", x = x + s / 2, y = y + s - LABEL_LINE - 2, text = fit(label:match("^[^\n]*"), s),
              size = LABEL, align = "center", colour = TEXT })
          else
            local lines = {}
            for l in label:gmatch("[^\n]+") do lines[#lines + 1] = l end
            local top = y + (s - #lines * LABEL_LINE) / 2
            for n, l in ipairs(lines) do
              add({ type = "text", x = x + s / 2, y = top + (n - 1) * LABEL_LINE, text = fit(l, s), size = LABEL,
                align = "center", colour = TEXT })
            end
          end
        end
        if sh and sh.left > 0 then
          local secs = math.ceil(sh.left)
          local t = secs >= 60 and ("%d:%02d"):format(secs // 60, secs % 60) or tostring(secs)
          add({ type = "text", x = x + s / 2, y = y + s / 2 - 11, text = t, size = 1.45, font = "bold",
            align = "center", colour = { 255, 236, 180, 255 } })
        end
        if geo.show_keys then
          local hint = keys.hint(b, i)
          add({ type = "text", x = x + 4, y = y + 2, text = hint, size = 0.9, colour = MUTED })
        end
        if act and suggested[act.kind .. ":" .. act.id] then
          add({ type = "rect", x = x - 3, y = y - 3, w = s + 6, h = s + 6, round = round + 3, line = 3,
            colour = { GLOW[1], GLOW[2], GLOW[3], math.floor(25 + 45 * glow) } })
          add({ type = "rect", x = x - 1, y = y - 1, w = s + 2, h = s + 2, round = round + 1, line = 1.5,
            colour = { GLOW[1], GLOW[2], GLOW[3], math.floor(150 + 90 * glow) } })
        end
        if flash[key] and flash[key] > now then
          add({ type = "rect", x = x, y = y, w = s, h = s, round = round, colour = FLASH })
        end
        if drag and drag.x then
          if drag.b == b and drag.i == i then
            add({ type = "rect", x = x, y = y, w = s, h = s, round = round, colour = DRAGGED })
          elseif key_of(hit(drag.x, drag.y)) == key then
            add({ type = "rect", x = x - 1, y = y - 1, w = s + 2, h = s + 2, round = round + 1, line = 2, colour = DROP })
          end
        elseif tile_at and key_of(hit(tile_at.x, tile_at.y)) == key then
          add({ type = "rect", x = x - 1, y = y - 1, w = s + 2, h = s + 2, round = round + 1, line = 2, colour = DROP })
        end
        if macro then
          local name = data.trim(macro.name)
          add({ type = "tip", x = x, y = y, w = s, h = s, title = name ~= "" and name or keys.hint(b, i),
            text = table.concat(macro.lines or {}, "\n") })
        end
      end
    end
  end
  -- + over -, round knobs on the edge that stays put.
  local n, most = wanted(), geo.bars
  local r = geo.btn / 2
  local cx, plus_y, minus_y = knobs(h)
  local buttons = {
    { "plus", plus_y, n < most, "Show another bar" },
    { "minus", minus_y, n > 1, "Show one bar fewer" },
  }
  for _, btn in ipairs(buttons) do
    local name, cy, live, tip = btn[1], btn[2], btn[3], btn[4]
    local ink = not live and GOLD_OFF or (hover == name and INK or GOLD)
    add({ type = "circle", x = cx, y = cy, r = r, colour = KEY })
    add({ type = "circle", x = cx, y = cy, r = r - 0.75, line = 1.5, colour = ink })
    local a = r * 0.45
    add({ type = "line", x1 = cx - a, y1 = cy, x2 = cx + a, y2 = cy, width = 1.6, colour = ink })
    if name == "plus" then
      add({ type = "line", x1 = cx, y1 = cy - a, x2 = cx, y2 = cy + a, width = 1.6, colour = ink })
    end
    add({ type = "tip", x = cx - r, y = cy - r, w = 2 * r, h = 2 * r, title = "", text = tip })
  end
  -- The dragged slot, or a palette tile dragged over the bars: a translucent copy under the pointer.
  local g, act, glabel = nil, nil, nil
  if drag and drag.x then
    local cell = eff[drag.b] and eff[drag.b][drag.i]
    local macro = cell and cell.macro
    g, act, glabel = drag, macro and actions.of(macro), macro and data.display_label(macro)
  elseif tile_at and palette.dragging then
    g, act, glabel = tile_at, palette.dragging.act, palette.dragging.label
  end
  if g then
    local gx, gy = g.x - s / 2, g.y - s / 2
    add({ type = "rect", x = gx, y = gy, w = s, h = s, round = round, colour = GHOST_BG })
    if act then
      local isz = math.floor(s * 0.58)
      add({ type = "icon", x = gx + (s - isz) / 2, y = gy + 4, size = isz, kind = act.kind, id = act.id,
        colour = GHOST })
    elseif glabel then
      add({ type = "text", x = gx + s / 2, y = gy + s / 2 - LABEL_LINE / 2, text = fit(glabel:match("^[^\n]*"), s),
        size = LABEL, align = "center", colour = GHOST })
    end
  end
  ui.update(WIN, "c", { h = h, draw = d })
end

-- ---------------------------------------------------------------------------
-- Animation: the height easing, the suggestion glow breathing
-- ---------------------------------------------------------------------------

local anim, last = nil, nil

local function busy()
  return reveal ~= wanted() or next(suggested) ~= nil
end

local function step()
  local now = os.clock()
  local dt = math.min(0.05, math.max(0, now - (last or now)))
  last = now
  local target = wanted()
  reveal = reveal or target
  if reveal < target then
    reveal = math.min(target, reveal + dt * SPEED)
  elseif reveal > target then
    reveal = math.max(target, reveal - dt * SPEED)
  end
  draw()
  if not busy() and anim then
    events.off(anim)
    anim, last = nil, nil
  end
end

local function animate()
  if not anim and busy() then
    last = os.clock()
    anim = events.on("frame", step)
  end
end

-- + shows one bar more, - one fewer (1 .. the Bars setting).
function M.grow(d)
  local n = wanted()
  local most = math.min(settings.get("bars"), data.MAX_BARS)
  local to = math.max(1, math.min(most, n + d))
  if to == n then return end
  storage.character.hb_shown = to
  storage.save()
  animate()
  draw()
end

-- ---------------------------------------------------------------------------
-- The window and its events
-- ---------------------------------------------------------------------------

local function on_event(_, e)
  if e.kind == "dock" then
    top_dock = e.side == "top"
    draw()
    return
  end
  if e.id ~= "c" then return end
  if e.kind == "drop" then
    -- A palette tile: its library macro goes into the set the slot shows (the sub job's when it shows that one).
    tile_at = nil
    local c = hit(e.x, e.y)
    local id = palette.dragged_id(e.from)
    if type(c) ~= "table" or not id or not main then return end
    local _, from = data.resolve(main, sub, c.b, c.i)
    data.assign(main, from == "sub" and sub or nil, c.b, c.i, id)
    flash[c.b .. ":" .. c.i] = os.clock() + 0.12
    timer.after(0.13, draw)
    M.rebuild()
    if M.hooks.changed then M.hooks.changed() end
  elseif e.kind == "hover" or e.kind == "leave" then
    local now = e.kind == "hover" and key_of(hit(e.x, e.y)) or nil
    local was_tile = tile_at ~= nil
    tile_at = e.kind == "hover" and palette.dragging and { x = e.x, y = e.y } or nil
    if now ~= hover or tile_at or was_tile then
      hover = now
      draw()
    end
  elseif e.kind == "click" then
    local c = hit(e.x, e.y)
    if c == "plus" then
      M.grow(1)
    elseif c == "minus" then
      M.grow(-1)
    elseif type(c) == "table" then
      if e.button == "right" then
        local _, from = data.resolve(main, sub, c.b, c.i)
        M.hooks.slot_menu(c.b, c.i, from)
      else
        flash[c.b .. ":" .. c.i] = os.clock() + 0.12
        draw()
        timer.after(0.13, draw)
        M.fire(c.b, c.i)
      end
    end
  elseif e.kind == "drag_start" then
    local c = hit(e.x, e.y)
    local cell = type(c) == "table" and eff[c.b] and eff[c.b][c.i]
    drag = cell and cell.macro and { b = c.b, i = c.i, x = e.x, y = e.y } or nil
    if drag then draw() end
  elseif e.kind == "drag" and drag then
    drag.x, drag.y = e.x, e.y
    draw()
  elseif e.kind == "drag_end" and drag then
    local to = hit(e.x, e.y)
    local from = drag
    drag = nil
    draw()
    if type(to) ~= "table" or (to.b == from.b and to.i == from.i) or not main then return end
    local _, a = data.resolve(main, sub, from.b, from.i)
    local _, b = data.resolve(main, sub, to.b, to.i)
    data.swap(main, (a == "sub" or b == "sub") and sub or nil, from.b, from.i, to.b, to.i)
    M.rebuild()
    if M.hooks.changed then M.hooks.changed() end
  end
end

function M.rebuild()
  built_sig = signature()
  if hidden or not settings.get("on") or not settings.get("visible") then
    ui.close(WIN)
    return
  end
  main, sub = jobs.current()
  if not main then
    built_sig = nil -- jobs not known yet; the tick tries again
    return
  end
  local o = opts()
  local btn = 18 -- the fold knob's size (radius 9)
  geo = { size = o.size, gap = o.gap, slots = o.slots, bars = o.bars, show_keys = o.show_keys, btn = btn,
    width = PAD + o.slots * o.size + (o.slots - 1) * o.gap + PAD + btn + PAD }
  eff = data.effective(main, sub)
  reveal = math.min(reveal or wanted(), o.bars)
  ui.window(WIN, {
    title = "Hotbars",
    heading = main .. "/" .. (sub or "-"),
    edge = true,
    grow = "up",
    -- The canvas plus the edge frame's margins (16 + 18 at most), so it never overflows.
    width = geo.width + 34,
    elements = { { type = "canvas", id = "c", w = geo.width, h = height(reveal) } },
  })
  ui.on(WIN, on_event)
  ui.open(WIN)
  M.recasts()
  animate()
end

-- The recast shades and what cannot be used now, every quarter second.
function M.recasts()
  if not geo or not eff then return end
  local r = game.recasts()
  local me = game.player()
  shades = {}
  for b = 1, geo.bars do
    for i = 1, geo.slots do
      local cell = eff[b] and eff[b][i]
      local act = cell and cell.macro and actions.of(cell.macro)
      if act then
        local left, frac = actions.recast(act, r)
        shades[b .. ":" .. i] = { left = left, frac = frac, usable = actions.usable(act, me) }
      end
    end
  end
  draw()
end

-- The battle menu's suggestions (while it is open): their slots glow, breathing gently.
events.on("suggestions", function(rows)
  suggested = {}
  for _, r in ipairs(rows or {}) do
    if r.kind and r.id then suggested[r.kind .. ":" .. r.id] = true end
    for _, g in ipairs(r.group or {}) do suggested["spell:" .. g] = true end
  end
  animate()
  draw()
end)

function M.rebind()
  if not settings.get("on") then
    keys.bind_all(0, 0, M.fire)
    return
  end
  local o = opts()
  keys.bind_all(o.bars, o.slots, M.fire)
end

-- Once a second: rebuilds when the jobs or the layout settings changed.
function M.tick()
  if signature() ~= built_sig then M.rebuild() end
end

function M.set_hidden(value)
  hidden = value
  M.rebuild()
end

function M.is_hidden() return hidden end

-- A palette tile's drag ended (dropped or not): its copy over the bars goes.
function M.tile_drag_ended()
  if tile_at then
    tile_at = nil
    draw()
  end
end

return M
