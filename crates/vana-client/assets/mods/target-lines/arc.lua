local M = {}

-- `segments` + 1 points on a quadratic curve from `from` to `to`, its middle lifted (y points down).
function M.samples(from, to, segments)
  local dx, dz = to.x - from.x, to.z - from.z
  local lift = math.min(math.max(math.sqrt(dx * dx + dz * dz) * 0.12, 0.4), 2.5)
  local mid = { x = (from.x + to.x) * 0.5, y = (from.y + to.y) * 0.5 - lift, z = (from.z + to.z) * 0.5 }
  local out = {}
  for i = 0, segments do
    local t = i / segments
    local u = 1 - t
    out[#out + 1] = {
      x = u * u * from.x + 2 * u * t * mid.x + t * t * to.x,
      y = u * u * from.y + 2 * u * t * mid.y + t * t * to.y,
      z = u * u * from.z + 2 * u * t * mid.z + t * t * to.z,
    }
  end
  return out
end

return M
