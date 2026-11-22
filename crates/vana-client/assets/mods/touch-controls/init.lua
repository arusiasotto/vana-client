-- Three edge windows (move, cam, buttons); drag each tab to place it. Canvas input works on Android.

local keys = require("src.keys")
local panel = require("src.panel")

local CANVAS = "c"
local WINS = {
  { id = "touch_move", zone = "move", title = "Move", geo = panel.geo_stick, draw = panel.draw_move,
    hit = panel.hit_stick },
  { id = "touch_cam", zone = "cam", title = "Cam", geo = panel.geo_stick, draw = panel.draw_cam,
    hit = panel.hit_stick },
  { id = "touch_btns", zone = "btns", title = "Keys", geo = panel.geo_btns, draw = panel.draw_btns,
    hit = panel.hit_btns },
}

local sticks = {
  move = { drag = false, kx = 0, ky = 0, x = 0, y = 0 },
  cam = { drag = false, kx = 0, ky = 0, x = 0, y = 0 },
}
local stick_touch
local window_sig

local function dead()
  return (settings.get("deadzone") or 18) / 100
end

local function touch_active()
  return settings.get("on") and game.player() and game.player().name ~= ""
end

local function refresh_all()
  for _, w in ipairs(WINS) do
    if touch_active() and ui.is_open(w.id) then
      local lite = settings.get("lite")
      local draw = w.zone == "btns" and w.draw(lite) or w.draw(sticks, lite)
      ui.update(w.id, CANVAS, { draw = draw })
    end
  end
end

local function any_open()
  for _, w in ipairs(WINS) do
    if ui.is_open(w.id) and ui.bounds(w.id, CANVAS) then return true end
  end
  return false
end

local function snap_stick(zone)
  if not zone then return end
  local st = sticks[zone]
  st.drag = false
  st.kx, st.ky, st.x, st.y = 0, 0, 0, 0
end

local function snap_sticks()
  if stick_touch then snap_stick(stick_touch) end
  stick_touch = nil
  refresh_all()
end

local function clear_sticks()
  for z in pairs(sticks) do
    snap_stick(z)
  end
  stick_touch = nil
end

local function stick_zone(zone, g, x, y)
  local cx, cy, r = g.cx, g.cy, g.r
  local dx, dy = x - cx, y - cy
  local mag = math.sqrt(dx * dx + dy * dy)
  if mag > r and mag > 0 then
    dx, dy = dx * r / mag, dy * r / mag
  end
  local st = sticks[zone]
  st.kx, st.ky = dx / r, dy / r
  st.x, st.y = st.kx, st.ky
end

local function on_pointer(win, e, lx, ly)
  local g = win.geo()
  local hit = win.hit(g, lx, ly)
  local zone = win.zone

  if zone == "btns" and hit and hit.zone == "btn" and e.kind == "click" and e.button == "left" then
    local map = { keys.accept, keys.cancel, keys.menu }
    input.press(map[hit.index])
    return
  end

  if (zone == "move" or zone == "cam") and hit and hit.mode == "stick" and (e.kind == "drag_start" or e.kind == "drag") then
    if not stick_touch then
      stick_touch = zone
      sticks[zone].drag = true
    end
    stick_zone(zone, g, lx, ly)
    refresh_all()
    return
  end

  if stick_touch == zone and (e.kind == "drag" or e.kind == "drag_end") then
    stick_zone(zone, g, lx, ly)
    refresh_all()
    if e.kind == "drag_end" then snap_sticks() end
  end
end

local function refresh_one(win)
  if not touch_active() or not ui.is_open(win.id) then return end
  local lite = settings.get("lite")
  local draw = win.zone == "btns" and win.draw(lite) or win.draw(sticks, lite)
  ui.update(win.id, CANVAS, { draw = draw })
end

local function window_frame(win)
  local g = win.geo()
  return ("%s:%d:%d:%d"):format(win.id, g.w, g.h, settings.get("scale") or 100)
end

local function define_window(win)
  local g = win.geo()
  local lite = settings.get("lite") and "1" or "0"
  local key = window_frame(win) .. ":" .. lite
  if window_sig and window_sig[win.id] == key and ui.is_open(win.id) then return end
  window_sig = window_sig or {}
  window_sig[win.id] = key
  ui.window(win.id, {
    title = win.title,
    heading = win.title,
    edge = true,
    hud = true,
    grow = "up",
    width = g.w + 34,
    elements = { { type = "canvas", id = CANVAS, w = g.w, h = g.h } },
  })
  ui.open(win.id)
  refresh_one(win)
end

local function ensure_windows()
  if not touch_active() then
    for _, w in ipairs(WINS) do
      if ui.is_open(w.id) then ui.close(w.id) end
    end
    window_sig = nil
    return
  end
  for _, w in ipairs(WINS) do
    define_window(w)
  end
end

for _, win in ipairs(WINS) do
  ui.on(win.id, function(_, e)
    if e.kind == "dock" then
      refresh_all()
    elseif e.id == CANVAS then
      on_pointer(win, e, e.x, e.y)
    end
  end)
end

input.on_mouse(function(e)
  if stick_touch and e.kind == "up" and (e.button == "left" or e.button == nil) then
    snap_sticks()
  end
end)

events.on("frame", function()
  if not touch_active() then
    keys.clear_all()
    clear_sticks()
    ensure_windows()
    return
  end
  ensure_windows()
  if stick_touch then refresh_all() end
  if not any_open() or input.typing() then
    keys.clear_all()
    return
  end
  local d = dead()
  keys.apply(keys.move, sticks.move.x, sticks.move.y, d)
  keys.apply(keys.cam, sticks.cam.x, sticks.cam.y, d)
end)

events.on("settings_changed", function()
  window_sig = nil
  ensure_windows()
end)

events.on("login", function()
  window_sig = nil
end)

events.on("logout", function()
  keys.clear_all()
  clear_sticks()
  for _, w in ipairs(WINS) do ui.close(w.id) end
  window_sig = nil
end)

events.on("unload", function()
  keys.clear_all()
  for _, w in ipairs(WINS) do ui.close(w.id) end
end)