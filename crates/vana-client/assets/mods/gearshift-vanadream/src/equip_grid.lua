-- 4×4 equipment grid for //vg canvases.

local M = {}

M.GRID = { { 0, 1, 2, 3 }, { 4, 9, 11, 12 }, { 5, 6, 13, 14 }, { 15, 10, 7, 8 } }
-- At scale 150% (the mod default) cell+gap match the client's Equipment screen (52 + 4).
local BASE_CELL, BASE_GAP = 35, 3

local DIM = { 0, 0, 0, 90 }
local LINE = { 160, 150, 120, 110 }
local SEL = { 240, 200, 80, 220 }

M.CELL, M.GAP, M.SIZE = BASE_CELL, BASE_GAP, 4 * BASE_CELL + 3 * BASE_GAP

function M.configure(scale)
  local s = math.max(0.8, math.min(1.65, scale or 1))
  M.scale = s
  M.CELL = math.floor(BASE_CELL * s + 0.5)
  M.GAP = math.max(2, math.floor(BASE_GAP * s + 0.5))
  M.SIZE = 4 * M.CELL + 3 * M.GAP
  return s
end

local function xy(slot)
  for r, row in ipairs(M.GRID) do
    for c, s in ipairs(row) do
      if s == slot then
        return (c - 1) * (M.CELL + M.GAP), (r - 1) * (M.CELL + M.GAP)
      end
    end
  end
end

function M.origin(slot)
  return xy(slot)
end

function M.center(slot)
  local x, y = xy(slot)
  if not x then return nil end
  return x + M.CELL / 2, y + M.CELL / 2
end

function M.hit(x, y)
  for r, row in ipairs(M.GRID) do
    for c, s in ipairs(row) do
      local px, py = (c - 1) * (M.CELL + M.GAP), (r - 1) * (M.CELL + M.GAP)
      if x >= px and x < px + M.CELL and y >= py and y < py + M.CELL then return s end
    end
  end
end

-- Horizontal offset to centre the grid in a canvas `w` wide (for click coords too).
function M.offset_x(canvas_w)
  return math.max(0, math.floor((canvas_w - M.SIZE) / 2 + 0.5))
end

local function shift(cmd, ox, oy)
  if cmd.x then cmd.x = cmd.x + ox end
  if cmd.y then cmd.y = cmd.y + oy end
  if cmd.x1 then cmd.x1, cmd.y1 = cmd.x1 + ox, cmd.y1 + oy end
  if cmd.x2 then cmd.x2, cmd.y2 = cmd.x2 + ox, cmd.y2 + oy end
  return cmd
end

function M.draw(opts, canvas_w)
  opts = opts or {}
  local ox = canvas_w and M.offset_x(canvas_w) or 0
  local out = {}
  for r, row in ipairs(M.GRID) do
    for c, s in ipairs(row) do
      local x, y = (c - 1) * (M.CELL + M.GAP), (r - 1) * (M.CELL + M.GAP)
      out[#out + 1] = { type = "rect", x = x, y = y, w = M.CELL, h = M.CELL, colour = DIM }
      local sel = opts.selected == s
      out[#out + 1] = { type = "rect", x = x, y = y, w = M.CELL, h = M.CELL, line = sel and 2 or 1,
        colour = sel and SEL or LINE }
      local id = opts.ids and opts.ids[s]
      local label = opts.labels and opts.labels[s]
      local tip = (opts.tips and opts.tips[s]) or (label and label ~= "" and { title = label, text = opts.notes and opts.notes[s] or "" })
      if tip and (tip.title or tip.text) then
        out[#out + 1] = { type = "tip", x = x, y = y, w = M.CELL, h = M.CELL,
          title = tip.title or "", text = tip.text or "" }
      end
      if id then
        out[#out + 1] = { type = "icon", kind = "item", id = id, x = x + 2, y = y + 2, size = M.CELL - 4 }
      elseif label and label ~= "" and label ~= "-" then
        local t = #label > 8 and (label:sub(1, 7) .. "…") or label
        out[#out + 1] = { type = "text", x = x + 2, y = y + M.CELL / 2 - 4, text = t, size = 1,
          colour = { 200, 200, 200, 220 } }
      end
      if opts.hand and opts.hand[s] then
        out[#out + 1] = { type = "text", x = x + 2, y = y + 2, text = "*", size = 1, colour = { 255, 220, 100, 255 } }
      end
    end
  end
  if ox ~= 0 then
    for i, cmd in ipairs(out) do out[i] = shift(cmd, ox, 0) end
  end
  return out, ox
end

M.configure(1)

return M