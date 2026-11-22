-- Hat keys the joysticks hold (movement: numpad hat; camera: arrow hat).
local M = {
  move = { up = "numpad8", down = "numpad2", left = "numpad4", right = "numpad6" },
  cam = { up = "up", down = "down", left = "left", right = "right" },
  accept = "enter",
  cancel = "escape",
  menu = "numpad-",
}

local all_move = {}
local all_cam = {}
for _, k in pairs(M.move) do all_move[#all_move + 1] = k end
for _, k in pairs(M.cam) do all_cam[#all_cam + 1] = k end

function M.clear_move()
  for _, k in ipairs(all_move) do input.send(k, false) end
end

function M.clear_cam()
  for _, k in ipairs(all_cam) do input.send(k, false) end
end

function M.clear_all()
  M.clear_move()
  M.clear_cam()
end

local function active(hat, x, y, dead)
  local mag = math.sqrt(x * x + y * y)
  if mag <= dead then
    return { up = false, down = false, left = false, right = false }
  end
  local nx, ny = x / mag, y / mag
  local t = 0.38
  return {
    up = ny < -t,
    down = ny > t,
    left = nx < -t,
    right = nx > t,
  }
end

-- Joystick deflection (x right, y down) in -1..1; dead is 0..1 fraction of radius past which a direction fires.
function M.active(hat, x, y, dead)
  return active(hat, x, y, dead)
end

function M.apply(hat, x, y, dead)
  local on = active(hat, x, y, dead)
  input.send(hat.up, on.up)
  input.send(hat.down, on.down)
  input.send(hat.left, on.left)
  input.send(hat.right, on.right)
end

return M