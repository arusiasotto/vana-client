-- The gamepad's crossbars, Hotbars' other mode (src/mode.lua; the Mode setting and //hb mode switch it). Three sides:
-- LT held, RT held, and both held, of two diamonds each (the d-pad's four slots and the face buttons' four) between
-- the bumpers' and stick clicks' (L1 over L3 on the left, R1 over R3 on the right, as on the pad). Holding a
-- trigger, those buttons use that side's slots and the game never sees them; with a controller connected, the triggers belong to the crossbars while the mode is on, and
-- the bumpers and stick clicks are the game's again when no trigger is held. They stand in an edge window as the
-- bars do (on a screen edge, dragged along the edges, folding to its tab), shown while the mode is on. With a
-- controller answering it shrinks back to its edge until a trigger is held, then shows that side alone, and its
-- button opens the manager meanwhile; without a controller, or while the manager or palette is open, every side
-- shows so the slots can be set.
--
-- Slots hold the job's library macros (src/data.lua, "pad", per main job) and show their action's icon and recast as
-- the bars' do. A click or a button press fires a slot (a group opens its list over it: the d-pad moves the cursor
-- and A runs the member, B closes it), a right click opens its menu, a slot dragged onto another swaps them, and a library macro dragged from the palette or the manager onto a slot puts it there.

local data = require("src.data")
local runner = require("src.runner")
local jobs = require("src.jobs")
local actions = require("src.actions")
local palette = require("src.palette")
local chooser = require("src.chooser")
local mode = require("src.mode")
local bar = require("src.bar")

local M = {}

-- Set by init.lua: changed() after a slot changed, open_manager(), palette() shows the macro palette.
M.hooks = {}

local WIN = "pads"
local MENU = "padmenu"

local SIDES, BUTTONS = data.PAD_SIDES, data.PAD_BUTTONS
local LABELS = { up = "Up", right = "Right", down = "Down", left = "Left", y = "Y", b = "B", a = "A", x = "X",
  lb = "L1", rb = "R1", l3 = "L3", r3 = "R3" }
local SIDE_NAMES = { lt = "LT", rt = "RT", lr = "LT + RT" }
local SLOT = {}
for i, b in ipairs(BUTTONS) do SLOT[b] = i end
local IS_TRIGGER = { lt = true, rt = true }

-- As the bars' keys: charcoal with a bronze edge (a gold one on the side held); an empty slot fainter.
local KEY = { 10, 17, 24, 255 }
local KEY_HOVER = { 20, 33, 44, 255 }
local EMPTY_KEY = { 10, 17, 24, 150 }
local EDGE = { 184, 139, 73, 205 }
local EDGE_HELD = { 228, 192, 119, 255 }
local EMPTY_EDGE = { 184, 139, 73, 70 }
local OFF_EDGE = { 80, 84, 96, 120 }
local FLASH = { 255, 236, 190, 120 }
local SHADE = { 0, 0, 0, 165 }
local UNUSABLE = { 6, 8, 14, 165 }
local TEXT = { 236, 230, 214, 255 }
local MUTED = { 196, 188, 170, 230 }
local GOLD = { 228, 192, 119, 255 }
local DIMMED = { 140, 140, 150, 255 }
local GHOST = { 255, 255, 255, 140 }
local GHOST_BG = { 20, 24, 38, 120 }
local DROP = { 255, 214, 120, 200 }
local DRAGGED = { 0, 0, 0, 120 }
local MENU_GOLD = { 232, 210, 156 }
local MENU_DIM = { 160, 162, 172 }

local LABEL = 0.78
local LABEL_LINE = 13
local PAD = 8
local HEAD = 16 -- the sides' names over the diamonds
local IDLE_W, IDLE_H = 120, 24 -- the folded window's button

local geo = nil        -- the layout: size, slots (each { x, y, side, button }), width, height
local cells = {}       -- "side:button" -> the macro there
local main = nil
local built_sig = nil
local hover = nil      -- "side:button" under the pointer
local flash = {}       -- "side:button" -> os.clock() until its fire flash ends
local drag = nil       -- {side, button, x, y}: the slot a drag started on and where the pointer is now
local tile_at = nil    -- {x, y}: where a palette tile dragged over the crossbars is
local shades = {}      -- "side:button" -> {left, frac, usable} from the last recast tick
local top_dock = false -- docked on the top edge (the dock event): a group's list opens under the slot
local idle_hover = false -- the pointer is on the folded window's button
local drawn_held = nil -- the side held when it was last drawn
local built_view = nil -- what the window was last built to show: "all", "lt", "rt", "lr" or "none"

local function key_of(c) return type(c) == "table" and (c.side .. ":" .. c.button) or c end

-- ---------------------------------------------------------------------------
-- Using a slot
-- ---------------------------------------------------------------------------

-- Whether the crossbars answer the controller now.
function M.is_active()
  return settings.get("on") and mode.is_pad() and input.pad().connected and true or false
end

-- "lt" or "rt" while one trigger is held, "lr" while both are, else nil.
local function held()
  local p = input.pad()
  if not p.connected then return nil end
  local l, r = p.buttons.lt, p.buttons.rt
  if l and r then return "lr" end
  if l then return "lt" end
  if r then return "rt" end
  return nil
end

local function slot_of(side, button)
  for _, s in ipairs(geo and geo.slots or {}) do
    if s.side == side and s.button == button then return s end
  end
end

-- Where a group slot's list opens: over the slot (under it on the top edge), centred on it, in window pixels; nil
-- when the crossbars' place on screen is not known (the list opens at the pointer).
local function list_place(side, button)
  local at = ui.bounds and ui.bounds(WIN, "c")
  local s = slot_of(side, button)
  if not at or not s then return nil end
  local u = hud.screen().ui_scale
  local cx = at.x + (s.x + geo.size / 2) * at.scale - chooser.WIDTH * u / 2
  if top_dock then
    return { x = cx, y = at.y + (s.y + geo.size) * at.scale + 6 * u }
  end
  return { x = cx, y = at.y + s.y * at.scale - 6 * u, above = true }
end

-- Runs a slot. `by_pad`: a button press, else a click.
function M.fire(side, button, by_pad)
  local mj = jobs.current()
  if not mj then return end
  local macro = data.pad_resolve(mj, side, button)
  if not macro then return end
  if macro.group then
    chooser.open(macro, list_place(side, button), nil, nil)
  else
    runner.run_checked(macro)
  end
end

input.on_pad(function(e)
  if not M.is_active() then return nil end
  if IS_TRIGGER[e.button] then return true end
  if chooser.is_open() then
    -- A group's list is open: the d-pad moves its cursor, A runs the member, B closes it.
    local b = e.button
    if b == "up" or b == "down" or b == "a" or b == "b" then
      if e.down then
        timer.after(0, function()
          if b == "up" then chooser.step(-1)
          elseif b == "down" then chooser.step(1)
          elseif b == "a" then chooser.accept()
          else chooser.close() end
        end)
      end
      return true
    end
    if e.down and held() and SLOT[b] then chooser.close() end -- another slot: it fires as usual
  end
  local side = held()
  if not side or not SLOT[e.button] then return nil end
  if e.down then
    -- Not in the filter itself: a macro may wait, and the filter has a few milliseconds to answer.
    timer.after(0, function() M.fire(side, e.button, true) end)
  end
  return true
end)

-- ---------------------------------------------------------------------------
-- A slot's menu
-- ---------------------------------------------------------------------------

local function open_menu(side, button)
  local mj = jobs.current()
  local macro = mj and data.pad_resolve(mj, side, button)
  local act = macro and actions.of(macro)
  local list, what = {}, {}
  if macro then
    list[#list + 1] = { "Clear the slot" }
    what[#what + 1] = "clear"
  end
  list[#list + 1] = { "Open the palette" }
  what[#what + 1] = "palette"
  list[#list + 1] = { "Open the manager" }
  what[#what + 1] = "manager"
  local name = macro and (data.trim(macro.name) ~= "" and macro.name or (macro.lines[1] or "")) or "Empty slot"
  ui.window(MENU, {
    title = "Crossbar slot",
    width = 270,
    popup = true,
    elements = {
      { type = "list", id = "head", height = 1, rows = { {
        name, SIDE_NAMES[side] .. " " .. LABELS[button], icon = act and { kind = act.kind, id = act.id } or nil,
        colour = macro and MENU_GOLD or MENU_DIM } }, columns = { {}, { width = 70, align = "right" } } },
      { type = "separator" },
      { type = "list", id = "acts", rows = list, height = #list },
    },
  })
  ui.on(MENU, function(_, e)
    if e.kind ~= "select" or e.id ~= "acts" then return end
    ui.close(MENU)
    local picked = what[e.index]
    if picked == "clear" and mj then
      data.pad_clear(mj, side, button)
      M.rebuild()
      if M.hooks.changed then M.hooks.changed() end
    elseif picked == "palette" and M.hooks.palette then
      M.hooks.palette()
    elseif picked == "manager" and M.hooks.open_manager then
      M.hooks.open_manager()
    end
  end)
  ui.open(MENU)
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- A line cut to what fits a slot `w` points wide, 4 clear of each side, with an ellipsis.
local function fit(text, w)
  local n = math.max(1, math.floor((w - 8) / (6.5 * LABEL)))
  if utf8.len(text) and utf8.len(text) > n then
    return text:sub(1, utf8.offset(text, n) - 1) .. "…"
  end
  return text
end

local function hit(x, y)
  if not geo then return nil end
  for _, s in ipairs(geo.slots) do
    if x >= s.x and x < s.x + geo.size and y >= s.y and y < s.y + geo.size then
      return { side = s.side, button = s.button }
    end
  end
end

-- What shows now: every side ("all"), or with the auto-hide on and a controller answering, only the side whose
-- trigger (or both) is held ("none" while neither is). All stay for setting up: while the manager or palette is open.
local function view()
  if settings.get("pad_autohide") and M.is_active() and not (M.hooks.editing and M.hooks.editing()) then
    return held() or "none"
  end
  return "all"
end

local function draw()
  if not geo then return end
  local d = {}
  local function add(c) d[#d + 1] = c end
  local s, round = geo.size, 7
  local active = held()
  drawn_held = active
  local now = os.clock()
  for _, side in ipairs(geo.sides) do
    local lit = active == nil or active == side
    add({ type = "text", x = geo.side_x[side] + geo.side_w / 2, y = geo.side_y[side], text = SIDE_NAMES[side], size = 0.9,
      align = "center", colour = lit and GOLD or DIMMED })
  end
  for _, sl in ipairs(geo.slots) do
    local x, y = sl.x, sl.y
    local key = sl.side .. ":" .. sl.button
    local lit = active == nil or active == sl.side
    local macro = cells[key]
    local act = macro and actions.of(macro)
    add({ type = "rect", x = x, y = y, w = s, h = s, round = round,
      colour = hover == key and KEY_HOVER or (macro and KEY or EMPTY_KEY) })
    add({ type = "rect", x = x, y = y, w = s, h = s, round = round, line = 1.5,
      colour = active == sl.side and EDGE_HELD or (not lit and OFF_EDGE) or (macro and EDGE or EMPTY_EDGE) })
    if act then
      local isz = math.floor(s * 0.58)
      add({ type = "icon", x = x + (s - isz) / 2, y = y + 4, size = isz, kind = act.kind, id = act.id,
        colour = (not lit) and { 150, 150, 150, 255 } or nil })
    end
    if macro and macro.group then
      local ax = x + s - 9
      local base, tip = y + 10, y + 6
      if top_dock then base, tip = tip, base end
      add({ type = "tri", x1 = ax - 4, y1 = base, x2 = ax + 4, y2 = base, x3 = ax, y3 = tip, colour = GOLD })
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
    add({ type = "text", x = x + 4, y = y + 2, text = LABELS[sl.button], size = 0.9, colour = MUTED })
    if flash[key] and flash[key] > now then
      add({ type = "rect", x = x, y = y, w = s, h = s, round = round, colour = FLASH })
    end
    if drag and drag.x then
      if drag.side == sl.side and drag.button == sl.button then
        add({ type = "rect", x = x, y = y, w = s, h = s, round = round, colour = DRAGGED })
      elseif key_of(hit(drag.x, drag.y)) == key then
        add({ type = "rect", x = x - 1, y = y - 1, w = s + 2, h = s + 2, round = round + 1, line = 2, colour = DROP })
      end
    elseif tile_at and key_of(hit(tile_at.x, tile_at.y)) == key then
      add({ type = "rect", x = x - 1, y = y - 1, w = s + 2, h = s + 2, round = round + 1, line = 2, colour = DROP })
    end
    if macro then
      local name = data.trim(macro.name)
      local lines = macro.lines or {}
      if macro.group then
        lines = {}
        for n, m in ipairs(macro.group) do lines[n] = ("%d. %s"):format(n, m.lines[1] or m.name) end
      end
      add({ type = "tip", x = x, y = y, w = s, h = s, title = name ~= "" and name or LABELS[sl.button],
        text = table.concat(lines, "\n") })
    end
  end
  -- The dragged slot, or a palette tile dragged over the crossbars: a translucent copy under the pointer.
  local g, act, glabel = nil, nil, nil
  if drag and drag.x then
    local macro = cells[drag.side .. ":" .. drag.button]
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
  ui.update(WIN, "c", { h = geo.height, draw = d })
end

-- The trigger held changes which side shows, or is lit.
events.on("frame", function()
  if not mode.is_pad() then return end
  if view() ~= built_view then
    M.rebuild()
  elseif geo and held() ~= drawn_held then
    draw()
  end
end)

-- The recast shades and what cannot be used now, every quarter second.
function M.recasts()
  if not geo then return end
  local r = game.recasts()
  local me = game.player()
  shades = {}
  for key, macro in pairs(cells) do
    local act = actions.of(macro)
    if act then
      local left, frac = actions.recast(act, r)
      shades[key] = { left = left, frac = frac, usable = actions.usable(act, me) }
    end
  end
  draw()
end

-- The button the window shows while it is folded to its edge: it opens the manager.
local function draw_idle()
  ui.update(WIN, "c", { draw = {
    { type = "rect", x = 0, y = 0, w = IDLE_W, h = IDLE_H, round = 7, colour = idle_hover and KEY_HOVER or KEY },
    { type = "rect", x = 0, y = 0, w = IDLE_W, h = IDLE_H, round = 7, line = 1.5, colour = idle_hover and EDGE_HELD or EDGE },
    { type = "text", x = IDLE_W / 2, y = 5, text = "Open Manager", size = 0.9, align = "center",
      colour = idle_hover and GOLD or TEXT },
  } })
end

-- ---------------------------------------------------------------------------
-- The window and its events
-- ---------------------------------------------------------------------------

local function changed()
  M.rebuild()
  if M.hooks.changed then M.hooks.changed() end
end

local function on_event(_, e)
  if e.kind == "dock" then
    top_dock = e.side == "top"
    draw()
    return
  end
  if e.id ~= "c" then return end
  if not geo then
    -- Folded to the edge: the canvas is just the button that opens the manager.
    if e.kind == "click" and e.button ~= "right" then
      if M.hooks.open_manager then M.hooks.open_manager() end
    elseif e.kind == "hover" or e.kind == "leave" then
      local now = e.kind == "hover"
      if now ~= idle_hover then
        idle_hover = now
        draw_idle()
      end
    end
    return
  end
  if e.kind == "drop" then
    -- A library tile (the palette's, or the manager's): it goes on the slot.
    tile_at = nil
    local c = hit(e.x, e.y)
    local id = palette.dragged_id(e.from) or (e.from == "tiles" and palette.last)
    if type(c) ~= "table" or not id or not main or not data.get_entry(main, id) then
      draw()
      return
    end
    data.pad_assign(main, c.side, c.button, id)
    flash[key_of(c)] = os.clock() + 0.12
    timer.after(0.13, draw)
    changed()
  elseif e.kind == "hover" or e.kind == "leave" then
    local now = e.kind == "hover" and key_of(hit(e.x, e.y)) or nil
    if now ~= hover then
      hover = now
      draw()
    end
  elseif e.kind == "drag_over" or e.kind == "drag_out" then
    tile_at = e.kind == "drag_over" and palette.dragging and { x = e.x, y = e.y } or nil
    draw()
  elseif e.kind == "click" then
    local c = hit(e.x, e.y)
    if type(c) ~= "table" then return end
    if e.button == "right" then
      open_menu(c.side, c.button)
    else
      flash[key_of(c)] = os.clock() + 0.12
      draw()
      timer.after(0.13, draw)
      M.fire(c.side, c.button, false)
    end
  elseif e.kind == "drag_start" then
    local c = hit(e.x, e.y)
    drag = type(c) == "table" and cells[key_of(c)] and { side = c.side, button = c.button, x = e.x, y = e.y } or nil
    if drag then draw() end
  elseif e.kind == "drag" and drag then
    drag.x, drag.y = e.x, e.y
    draw()
  elseif e.kind == "drag_end" and drag then
    local to = hit(e.x, e.y)
    local from = drag
    drag = nil
    draw()
    if type(to) ~= "table" or (to.side == from.side and to.button == from.button) or not main then return end
    data.pad_swap(main, from.side, from.button, to.side, to.button)
    changed()
  end
end

-- Whether the crossbars' window shows now: Hotbars on and visible, in gamepad mode.
local function shown_now()
  return settings.get("on") and mode.is_pad() and settings.get("visible") and not bar.is_hidden()
end

local function signature()
  return table.concat({ tostring(jobs.current()), settings.get("pad_size"), tostring(shown_now()), view() }, ":")
end

function M.rebuild()
  built_sig = signature()
  built_view = view()
  if not shown_now() then
    geo = nil
    ui.close(WIN)
    return
  end
  main = jobs.current()
  if not main then
    built_sig = nil -- the job is not known yet; the tick tries again
    geo = nil
    return
  end
  local size = settings.get("pad_size")
  local gap = math.max(2, math.floor(size * 0.15))
  local arm = size + gap               -- a diamond's arm
  local dw = 2 * arm + size            -- a diamond's width
  local wing = size + 2 * gap          -- a column of L1 / L3 or R1 / R3 and the space before its diamond
  local side_w = 2 * wing + 2 * dw + 2 * gap
  local between = 6 * gap
  local spots = { up = { 1, 0 }, right = { 2, 1 }, down = { 1, 2 }, left = { 0, 1 } }
  local top = PAD + HEAD
  local side_h = HEAD + 2 * arm + size   -- a side: its name and the diamonds
  if built_view == "none" then
    -- No trigger held: the canvas shrinks to a small button, and the window with it, back to its edge.
    geo = nil
    ui.window(WIN, {
      title = "Crossbars", heading = main, edge = true, grow = "up", width = IDLE_W + 2 * PAD + 34,
      elements = { { type = "canvas", id = "c", w = IDLE_W, h = IDLE_H } },
    })
    ui.on(WIN, on_event)
    ui.open(WIN)
    draw_idle()
    return
  end
  idle_hover = false
  local sides = built_view == "all" and SIDES or { built_view }
  -- Two sides to a row: LT and RT, then LT + RT centred under them.
  local cols, rows = math.min(#sides, 2), math.ceil(#sides / 2)
  geo = { size = size, slots = {}, side_x = {}, side_y = {}, side_w = side_w, sides = sides,
    width = 2 * PAD + cols * side_w + (cols - 1) * between, height = rows * (side_h + PAD) + PAD }
  cells = {}
  local function add_slot(side, b, x, y)
    geo.slots[#geo.slots + 1] = { x = x, y = y, side = side, button = b }
    cells[side .. ":" .. b] = data.pad_resolve(main, side, b)
  end
  for si, side in ipairs(sides) do
    local sx = PAD + ((si - 1) % 2) * (side_w + between)
    if si == #sides and si % 2 == 1 and cols == 2 then
      sx = PAD + (side_w + between) / 2   -- the last one alone on its row (LT + RT): centred under the pair
    end
    local oy = math.floor((si - 1) / 2) * (side_h + PAD)   -- this side's row
    geo.side_x[side], geo.side_y[side] = sx, PAD + oy
    for di = 1, 2 do
      local dx = sx + wing + (di - 1) * (dw + 2 * gap)
      for k = 1, 4 do
        local pos = spots[BUTTONS[k]]
        add_slot(side, BUTTONS[(di - 1) * 4 + k], dx + pos[1] * arm, oy + top + pos[2] * arm)
      end
    end
    -- The shoulder buttons and stick clicks flank the diamonds as on the pad: L1 over L3 to the left, R1 over R3 to
    -- the right, centred on the diamonds' height.
    local wy = oy + top + arm / 2
    add_slot(side, "lb", sx, wy)
    add_slot(side, "l3", sx, wy + arm)
    add_slot(side, "rb", sx + side_w - size, wy)
    add_slot(side, "r3", sx + side_w - size, wy + arm)
  end
  ui.window(WIN, {
    title = "Crossbars",
    heading = main,
    edge = true,
    grow = "up",
    -- The canvas plus the edge frame's margins (16 + 18 at most), so it never overflows.
    width = geo.width + 34,
    elements = { { type = "canvas", id = "c", w = geo.width, h = geo.height } },
  })
  ui.on(WIN, on_event)
  ui.open(WIN)
  M.recasts()
end

-- After a slot, the library or the job changed.
M.invalidate = M.rebuild

-- Once a second: rebuilds when the job, the size or the mode changed.
function M.tick()
  if signature() ~= built_sig then M.rebuild() end
end

-- A palette tile's drag ended (dropped or not): its copy over the crossbars goes.
function M.tile_drag_ended()
  if tile_at then
    tile_at = nil
    draw()
  end
end

return M
