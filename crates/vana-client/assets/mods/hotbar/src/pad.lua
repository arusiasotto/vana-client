-- The gamepad's crossbars, Hotbars' other mode (src/mode.lua): three sets (LT, RT, both held) of the d-pad's and the
-- face buttons' slots, flanked by L1 / L3 and R1 / R3, in an edge window that shows the set held and folds to its edge.
-- Slots hold the job's library macros (src/data.lua "pad"); src/slotview.lua draws them as the bars' are.

local data = require("src.data")
local runner = require("src.runner")
local jobs = require("src.jobs")
local actions = require("src.actions")
local palette = require("src.palette")
local chooser = require("src.chooser")
local mode = require("src.mode")
local bar = require("src.bar")
local slotview = require("src.slotview")

local M = {}

-- Set by init.lua: changed() after a slot changed, open_manager(), palette() shows the macro palette, editing().
M.hooks = {}

local WIN = "pads"
local MENU = "padmenu"

local SIDES, BUTTONS = data.PAD_SIDES, data.PAD_BUTTONS
local LABELS = { up = "Up", right = "Right", down = "Down", left = "Left", y = "Y", b = "B", a = "A", x = "X",
  lb = "L1", rb = "R1", l3 = "L3", r3 = "R3" }
local SIDE_NAMES = { lt = "LT", rt = "RT", lr = "LT + RT" }
local SLOT = {}
for _, b in ipairs(BUTTONS) do SLOT[b] = true end
local IS_TRIGGER = { lt = true, rt = true }

-- The side held has a gold edge; the others dim.
local EDGE = { 184, 139, 73, 205 }
local EDGE_HELD = { 228, 192, 119, 255 }
local OFF_EDGE = { 80, 84, 96, 120 }
local KEY, KEY_HOVER, TEXT, GOLD = slotview.KEY, slotview.KEY_HOVER, slotview.TEXT, slotview.GOLD
local DIMMED = { 140, 140, 150, 255 }
local MENU_GOLD = { 232, 210, 156 }
local MENU_DIM = { 160, 162, 172 }

local PAD = 8
local HEAD = 16 -- the sets' names over the diamonds
local IDLE_W, IDLE_H = 120, 24 -- the folded window's button

local st = slotview.state()
local geo = nil          -- the layout shown: size, slots (each { x, y, side, button }), sides, width, height
local layouts = {}       -- "view:size" -> a layout
local cells = {}         -- "side:button" -> the macro there
local main = nil
local shades = {}        -- "side:button" -> {left, frac, usable} from the last recast tick
local built_sig = nil
local built_view = nil   -- what the window was built to show: "all", "lt", "rt", "lr" or "none"
local built_at = nil     -- when it was last defined
local window_key = nil   -- what the window is defined for: view, size and job
local drawn_held = nil   -- the set held when it was last drawn
local top_dock = false   -- docked on the top edge: a group's list opens under the slot
local idle_hover = false -- the pointer is on the folded window's button

local function key_of(c) return type(c) == "table" and (c.side .. ":" .. c.button) or c end

-- ---------------------------------------------------------------------------
-- Using a slot
-- ---------------------------------------------------------------------------

-- Whether the crossbars answer the controller now.
function M.is_active()
  return settings.get("on") and mode.is_pad() and input.pad().connected and true or false
end

-- A game list (magic, items, shops...) has the keys: the pad is the game's then, for its paging and bag switch.
local function game_menu()
  local list = ui.native and ui.native.list
  if not list or chooser.is_open() then return false end
  local ok, open = pcall(list)
  return ok and open ~= nil
end

-- "lt" or "rt" while one trigger is held, "lr" while both are, else nil.
local function held()
  local p = input.pad()
  if not p.connected or game_menu() then return nil end
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

-- Opens a group's list over its slot. Just after the window was rebuilt for a trigger pull its canvas is drawn a
-- frame later: until the bounds are the new ones, wait.
local function open_group(macro, side, button, tries)
  local at = ui.bounds and ui.bounds(WIN, "c")
  local s = slot_of(side, button)
  local fresh = at and s and math.abs(at.w - geo.width * at.scale) < 2 and math.abs(at.h - geo.height * at.scale) < 2
  if not fresh and built_at and os.clock() - built_at < 0.3 and tries < 8 then
    timer.after(0.03, function() open_group(macro, side, button, tries + 1) end)
    return
  end
  local place = fresh and slotview.list_place(at, s.x, s.y, geo.size, top_dock) or nil
  chooser.open(macro, place, nil, nil)
end

-- Runs a slot; a group opens its list.
function M.fire(side, button)
  local mj = jobs.current()
  if not mj then return end
  local macro = data.pad_resolve(mj, side, button)
  if not macro then return end
  if macro.group then
    open_group(macro, side, button, 0)
  else
    runner.run_checked(macro)
  end
end

-- Takes the triggers, the d-pad and the buttons a slot answers, and the list's cursor keys. A press is taken on its
-- press only: the host keeps the button taken until it comes up.
input.on_pad(function(e)
  if not mode.is_pad() then return nil end
  if IS_TRIGGER[e.button] then timer.after(0, M.sync) end
  if e.blocked or not M.is_active() then return nil end
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
      return e.down or nil
    end
    if e.down and held() and SLOT[b] then chooser.close() end -- another slot: it fires as usual
  end
  if game_menu() then return nil end
  if IS_TRIGGER[e.button] then return e.down or nil end
  local side = held()
  if not side or not SLOT[e.button] then return nil end
  if e.down then
    -- Not in the filter itself: a macro may wait, and the filter has a few milliseconds to answer.
    timer.after(0, function() M.fire(side, e.button) end)
    return true
  end
  return nil
end)

-- ---------------------------------------------------------------------------
-- A slot's menu
-- ---------------------------------------------------------------------------

local function changed()
  M.rebuild()
  if M.hooks.changed then M.hooks.changed() end
end

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
      changed()
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

-- What at (x, y) in the canvas: a slot ({x, y, side, button}) or nil.
local function hit(x, y)
  if not geo then return nil end
  for _, sl in ipairs(geo.slots) do
    if x >= sl.x and x < sl.x + geo.size and y >= sl.y and y < sl.y + geo.size then return sl end
  end
end

-- What shows now: every set ("all"), or with the auto-hide on and a controller answering, only the set held ("none"
-- while no trigger is). All of them show for setting up: while the manager or palette is open.
local function view()
  if settings.get("pad_autohide") and M.is_active() and not (M.hooks.editing and M.hooks.editing()) then
    return held() or "none"
  end
  return "all"
end

local function macro_of(c) return cells[key_of(c)] end

local function draw()
  if not geo then return end
  local d = {}
  local function add(c) d[#d + 1] = c end
  local s = geo.size
  local active = held()
  drawn_held = active
  for _, side in ipairs(geo.sides) do
    local lit = active == nil or active == side
    add({ type = "text", x = geo.side_x[side] + geo.side_w / 2, y = geo.side_y[side], text = SIDE_NAMES[side],
      size = 0.9, align = "center", colour = lit and GOLD or DIMMED })
  end
  for _, sl in ipairs(geo.slots) do
    local key = key_of(sl)
    local macro = cells[key]
    local lit = active == nil or active == sl.side
    slotview.draw_slot(add, {
      x = sl.x, y = sl.y, s = s, macro = macro, act = macro and actions.of(macro), shade = shades[key],
      up = top_dock, hover = st.hover == key, dim = not lit,
      edge = active == sl.side and EDGE_HELD or (not lit and OFF_EDGE) or (macro and EDGE or slotview.EMPTY_EDGE),
      hint = LABELS[sl.button], fallback = LABELS[sl.button],
      st = st, key = key, source = st.drag and st.drag.cell == sl,
      hit_key = function(px, py) return key_of(hit(px, py)) end,
    })
  end
  slotview.draw_ghost(add, st, s, macro_of)
  ui.update(WIN, "c", { h = geo.height, draw = d })
end

-- The button the window shows while it is folded to its edge: it opens the manager.
local function draw_idle()
  ui.update(WIN, "c", { draw = {
    { type = "rect", x = 0, y = 0, w = IDLE_W, h = IDLE_H, round = 7, colour = idle_hover and KEY_HOVER or KEY },
    { type = "rect", x = 0, y = 0, w = IDLE_W, h = IDLE_H, round = 7, line = 1.5,
      colour = idle_hover and EDGE_HELD or EDGE },
    { type = "text", x = IDLE_W / 2, y = 5, text = "Open Manager", size = 0.9, align = "center",
      colour = idle_hover and GOLD or TEXT },
  } })
end

local function refresh_cells()
  cells = {}
  for _, sl in ipairs(geo.slots) do cells[key_of(sl)] = data.pad_resolve(main, sl.side, sl.button) end
end

-- The recast shades and what cannot be used now, every quarter second.
function M.recasts()
  if not geo then return end
  local r = game.recasts()
  local me = game.player()
  shades = {}
  for key, macro in pairs(cells) do shades[key] = slotview.shade(macro, r, me) end
  draw()
end

-- A group's member was picked: its slot shows that one now.
function M.redraw()
  if not geo or not main then return end
  refresh_cells()
  draw()
end

-- A palette tile's drag ended (dropped or not): its copy over the crossbars goes.
function M.tile_drag_ended()
  if st.tile_at then
    st.tile_at = nil
    draw()
  end
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
  slotview.handle(e, {
    st = st, hit = hit, key_of = key_of, draw = draw, macro_of = macro_of,
    same = function(a, b) return a.side == b.side and a.button == b.button end,
    drop = function(c, id)
      if not main or not data.get_entry(main, id) then
        draw()
        return
      end
      data.pad_assign(main, c.side, c.button, id)
      slotview.flash(st, key_of(c), draw)
      changed()
    end,
    fire = function(c) M.fire(c.side, c.button) end,
    menu = function(c) open_menu(c.side, c.button) end,
    swap = function(from, to)
      if not main then return end
      data.pad_swap(main, from.side, from.button, to.side, to.button)
      changed()
    end,
  })
end

-- Whether the crossbars' window shows now: Hotbars on and visible, in gamepad mode.
local function shown_now()
  return settings.get("on") and mode.is_pad() and settings.get("visible") and not bar.is_hidden()
end

local function signature()
  return table.concat({ tostring(jobs.current()), settings.get("pad_size"), tostring(shown_now()), view() }, ":")
end

-- The layout of a view at a slot size: two sets to a row (LT and RT, then LT + RT centred under them); each set has
-- its name over the diamonds, L1 over L3 on their left and R1 over R3 on their right.
local function layout(v, size)
  local key = v .. ":" .. size
  if layouts[key] then return layouts[key] end
  local gap = math.max(2, math.floor(size * 0.15))
  local arm = size + gap               -- a diamond's arm
  local dw = 2 * arm + size            -- a diamond's width
  local wing = size + 2 * gap          -- a column of L1 / L3 or R1 / R3 and the space before its diamond
  local side_w = 2 * wing + 2 * dw + 2 * gap
  local between = 6 * gap
  local spots = { up = { 1, 0 }, right = { 2, 1 }, down = { 1, 2 }, left = { 0, 1 } }
  local top = PAD + HEAD
  local side_h = HEAD + 2 * arm + size
  local sides = v == "all" and SIDES or { v }
  local cols, rows = math.min(#sides, 2), math.ceil(#sides / 2)
  local g = { size = size, slots = {}, side_x = {}, side_y = {}, side_w = side_w, sides = sides,
    width = 2 * PAD + cols * side_w + (cols - 1) * between, height = rows * (side_h + PAD) + PAD }
  local function add_slot(side, b, x, y)
    g.slots[#g.slots + 1] = { x = x, y = y, side = side, button = b }
  end
  for si, side in ipairs(sides) do
    local sx = PAD + ((si - 1) % 2) * (side_w + between)
    if si == #sides and si % 2 == 1 and cols == 2 then sx = PAD + (side_w + between) / 2 end
    local oy = math.floor((si - 1) / 2) * (side_h + PAD)
    g.side_x[side], g.side_y[side] = sx, PAD + oy
    for di = 1, 2 do
      local dx = sx + wing + (di - 1) * (dw + 2 * gap)
      for k = 1, 4 do
        local pos = spots[BUTTONS[k]]
        add_slot(side, BUTTONS[(di - 1) * 4 + k], dx + pos[1] * arm, oy + top + pos[2] * arm)
      end
    end
    local wy = oy + top + arm / 2
    add_slot(side, "lb", sx, wy)
    add_slot(side, "l3", sx, wy + arm)
    add_slot(side, "rb", sx + side_w - size, wy)
    add_slot(side, "r3", sx + side_w - size, wy + arm)
  end
  layouts[key] = g
  return g
end

-- Defines and opens the window when what it is for changed; its canvas is `w` by `h`.
local function define(key, w, h, width)
  if key == window_key and ui.is_open(WIN) then return end
  window_key = key
  built_at = os.clock()
  ui.window(WIN, {
    title = "Crossbars",
    heading = main,
    edge = true,
    grow = "up",
    -- The canvas plus the edge frame's margins (16 + 18 at most), so it never overflows.
    width = width,
    elements = { { type = "canvas", id = "c", w = w, h = h } },
  })
  ui.on(WIN, on_event)
  ui.open(WIN)
end

function M.rebuild()
  built_sig = signature()
  built_view = view()
  if not shown_now() then
    geo, window_key = nil, nil
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
  local key = table.concat({ built_view, size, main }, ":")
  if built_view == "none" then
    -- No trigger held: the window shrinks to a small button, back to its edge.
    geo = nil
    slotview.reset(st)
    define(key, IDLE_W, IDLE_H, IDLE_W + 2 * PAD + 34)
    draw_idle()
    return
  end
  idle_hover = false
  geo = layout(built_view, size)
  refresh_cells()
  define(key, geo.width, geo.height, geo.width + 34)
  M.recasts()
end

-- After a slot, the library or the job changed.
M.invalidate = M.rebuild

-- Shows the set held: rebuilds when the view changed, else redraws when the trigger did.
function M.sync()
  if not mode.is_pad() then return end
  if view() ~= built_view then
    M.rebuild()
  elseif geo and held() ~= drawn_held then
    draw()
  end
end

-- Once a second: rebuilds when the job, the size or the mode changed.
function M.tick()
  if signature() ~= built_sig then M.rebuild() end
end

return M
