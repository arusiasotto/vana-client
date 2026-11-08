-- A small menu drawn on the HUD, so it can open above the pointer and stay on the screen (ui.menu opens below and
-- right of the pointer, off the screen for the bars at its foot). A row click picks it; the menu closes when a row is
-- picked, when the pointer has been off it for a moment, or when the HUD is rebuilt.

local M = {}

local LAYER = 30
local BG = { 12, 14, 22, 235 }
local EDGE = { 150, 140, 110, 220 }
local ROW = { 0, 0, 0, 0 }
local ROW_HOVER = { 70, 80, 120, 220 }
local LINGER = 2 -- seconds off the menu before it closes

local open_ids = nil -- element ids while open
local hovered = 0     -- rows under the pointer (enter and leave can arrive in either order)
local opened = 0      -- counts the menus opened, so a late timer leaves a newer menu alone

function M.is_open() return open_ids ~= nil end

function M.close()
  if not open_ids then return end
  for _, id in ipairs(open_ids) do
    pcall(hud.remove, id)
  end
  open_ids, hovered = nil, 0
end

-- The HUD was cleared (hud.clear): the menu is gone with it.
function M.forget()
  open_ids, hovered = nil, 0
end

-- Closes this menu after a moment unless the pointer is back on it.
local function close_later()
  local mine = opened
  timer.after(LINGER, function()
    if mine == opened and hovered == 0 then M.close() end
  end)
end

-- Opens the menu by the pointer (x, y): above it when there is room, else below, kept inside the window.
-- `handler(index)` gets the row picked.
function M.open(x, y, items, handler)
  M.close()
  local scr = hud.screen()
  local u = scr.ui_scale
  local row_h = math.floor(24 * u)
  local pad = math.floor(4 * u)
  local w = math.floor(150 * u)
  local h = #items * row_h + 2 * pad
  local top = y - h - 6 * u
  if top < 0 then top = y + 6 * u end
  top = math.max(0, math.min(top, scr.height - h))
  local left = math.max(0, math.min(x - w / 2, scr.width - w))

  open_ids = { "menu_bg", "menu_f" }
  hovered = 0
  opened = opened + 1
  -- Opened by the pointer, but not under it: it closes unless the pointer comes onto it.
  close_later()
  hud.rect("menu_f", { x = left - 1, y = top - 1, w = w + 2, h = h + 2, round = 6 * u, colour = EDGE, line = 1.2 * u,
    layer = LAYER })
  hud.rect("menu_bg", { x = left, y = top, w = w, h = h, round = 5 * u, colour = BG, layer = LAYER })
  for i, label in ipairs(items) do
    local id, tid = "menu_r" .. i, "menu_t" .. i
    local ry = top + pad + (i - 1) * row_h
    open_ids[#open_ids + 1] = id
    open_ids[#open_ids + 1] = tid
    hud.rect(id, { x = left + pad, y = ry, w = w - 2 * pad, h = row_h, round = 4 * u, colour = ROW, layer = LAYER + 1 })
    hud.text(tid, { x = left + 10 * u, y = ry + (row_h - 16 * u) / 2, text = label, size = 0.85,
      colour = { 235, 235, 240 }, outline = { 0, 0, 0, 200 }, layer = LAYER + 2 })
    hud.on(id, function(_, e)
      if e.kind == "mouse_enter" then
        hovered = hovered + 1
        pcall(hud.set, id, { colour = ROW_HOVER })
      elseif e.kind == "mouse_leave" then
        hovered = math.max(0, hovered - 1)
        pcall(hud.set, id, { colour = ROW })
        close_later()
      elseif e.kind == "click" and e.button == "left" then
        M.close()
        handler(i)
      end
    end)
  end
end
return M
