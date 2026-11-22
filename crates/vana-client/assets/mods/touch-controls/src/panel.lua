-- One canvas per control cluster (move stick, cam stick, button row).
local M = {}

local LABELS = { "Accept", "Cancel", "Menu" }

local function u_scale()
  return hud.screen().ui_scale
end

function M.stick_size()
  local u = u_scale()
  local base = 64 * (settings.get("scale") or 100) / 100
  local r = math.floor(base * u)
  local pad = math.floor(6 * u)
  local side = pad + 2 * r + pad
  return u, r, side, pad
end

function M.btn_size()
  local u, r = M.stick_size()
  local btn = math.max(40, math.floor(r * 0.72))
  local gap = math.floor(8 * u)
  local pad = math.floor(6 * u)
  local tray_w = 3 * btn + 2 * gap
  local w = pad + tray_w + pad
  local h = pad + btn + pad
  return u, r, btn, gap, w, h, pad
end

function M.geo_stick()
  local u, r, side, pad = M.stick_size()
  local cx, cy = side / 2, pad + r
  return { w = side, h = side, u = u, r = r, cx = cx, cy = cy }
end

function M.geo_btns()
  local u, r, btn, gap, w, h, pad = M.btn_size()
  return { w = w, h = h, u = u, r = r, btn = btn, gap = gap, pad = pad, tray_w = w - 2 * pad,
    tray = { x = pad, y = pad } }
end

function M.hit_stick(g, x, y)
  local dx, dy = x - g.cx, y - g.cy
  if dx * dx + dy * dy <= g.r * g.r then
    return { zone = "stick", mode = "stick" }
  end
  return nil
end

function M.hit_btns(g, x, y)
  local tx, ty, btn, gap = g.tray.x, g.tray.y, g.btn, g.gap
  for i = 1, 3 do
    local x0 = tx + (i - 1) * (btn + gap)
    if x >= x0 and x < x0 + btn and y >= ty and y < ty + btn then
      return { zone = "btn", index = i }
    end
  end
  return nil
end

local function stick_cmds(st, cx, cy, r, u, tag, lite)
  local kr = math.floor(r * 0.22)
  local knob = { 220, 225, 235, 230 }
  local outline = { 150, 158, 175, 200 }
  local dim = { 18, 22, 32, 200 }
  local d = {}
  local function add(t) d[#d + 1] = t end
  local dx, dy = 0, 0
  if st.drag then dx, dy = st.kx * r, st.ky * r end
  if lite then
    add({ type = "rect", x = cx - r, y = cy - r, w = 2 * r, h = 2 * r, round = r, line = 1.5 * u, colour = outline })
  else
    add({ type = "rect", x = cx - r, y = cy - r, w = 2 * r, h = 2 * r, round = r, colour = dim, line = 1.5 })
  end
  add({ type = "rect", x = cx + dx - kr, y = cy + dy - kr, w = 2 * kr, h = 2 * kr, round = kr, colour = knob })
  add({ type = "text", x = cx, y = cy - r + math.max(5, r * 0.14), text = tag, size = math.min(0.82, r / (40 * u)),
    align = "center", colour = { 200, 205, 215 } })
  return d
end

function M.draw_move(sticks, lite)
  local g = M.geo_stick()
  return stick_cmds(sticks.move, g.cx, g.cy, g.r, g.u, "Move", lite)
end

function M.draw_cam(sticks, lite)
  local g = M.geo_stick()
  return stick_cmds(sticks.cam, g.cx, g.cy, g.r, g.u, "Cam", lite)
end

function M.draw_btns(lite)
  local u, _, btn, gap, w, _, pad = M.btn_size()
  local tx, ty = pad, pad
  local tw = w - 2 * pad
  local d = {}
  local function add(t) d[#d + 1] = t end
  local outline = { 150, 158, 175, 200 }
  if not lite then
    add({ type = "rect", x = tx - 4, y = ty - 4, w = tw + 8, h = btn + 8, round = 6, colour = { 18, 22, 32, 190 } })
  end
  for i = 1, 3 do
    local x = tx + (i - 1) * (btn + gap)
    if lite then
      add({ type = "rect", x = x, y = ty, w = btn, h = btn, round = 5, line = 1.5 * u, colour = outline })
    else
      add({ type = "rect", x = x, y = ty, w = btn, h = btn, round = 5, colour = { 32, 38, 54, 235 } })
    end
    add({ type = "text", x = x + btn / 2, y = ty + btn * 0.26, text = LABELS[i], size = btn / (54 * u),
      align = "center", colour = { 240, 238, 230 } })
  end
  return d
end

return M