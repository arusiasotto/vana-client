-- The palette: the main job's library as tiles over the bars. Drag a tile onto a slot to put that macro there; click
-- one to edit it. //hb palette (or the manager's Palette button) shows and hides it for the session.

local data = require("src.data")
local actions = require("src.actions")
local ghost = require("src.ghost")

local M = {}

-- Set by init.lua: edit(id) opens the builder on an entry, redraw() rebuilds the HUD.
M.hooks = {}

local ROWS = 2
local open = false
local page = 1

local TILE_BG = { 22, 26, 40, 225 }
local TILE_DIM = { 22, 26, 40, 90 }
local TILE_EDGE = { 150, 140, 110, 200 }
local PANEL_BG = { 0, 0, 0, 150 }

function M.is_open() return open end

function M.toggle()
  open = not open
  M.hooks.redraw()
end

-- The library id a dragged element stands for, or nil.
function M.dragged_id(element_id)
  return element_id and element_id:match("^p_(.+)$")
end

local function button(id, spec, fn)
  hud.text(id, spec)
  hud.on(id, function(_, e)
    if e.kind == "click" then fn() end
  end)
end

-- Draws the palette with its bottom edge at `bottom`, over x0..x0+w. `size` is a bar slot's size, `u` the UI scale.
function M.draw(main, x0, w, bottom, size, gap, u)
  if not open then return end
  local items = data.library(main)
  local tile = math.floor(size * 0.8)
  local cols = math.max(4, math.floor((w + gap) / (tile + gap)))
  local per = cols * ROWS
  local pages = math.max(1, math.ceil(#items / per))
  page = math.min(page, pages)
  local line_h = 16 * u
  local height = ROWS * (tile + gap) + line_h + 10 * u
  local top = bottom - height

  hud.rect("pal_bg", { x = x0 - 6 * u, y = top, w = w + 12 * u, h = height, round = 6 * u, colour = PANEL_BG, layer = 0 })
  local title = #items == 0 and ("%s palette: no macros yet (//hb, Library, New)"):format(main)
    or ("%s palette: drag a macro onto a slot"):format(main)
  hud.text("pal_title", { x = x0, y = top + 3 * u, text = title, size = 0.75, colour = { 230, 215, 170 },
    outline = { 0, 0, 0, 230 }, layer = 2 })
  local right = x0 + w
  button("pal_close", { x = right, y = top + 3 * u, text = "x", size = 0.8, align = "right", colour = { 240, 200, 190 },
    outline = { 0, 0, 0, 230 }, layer = 2, tip = "Hide the palette" }, M.toggle)
  if pages > 1 then
    button("pal_next", { x = right - 24 * u, y = top + 3 * u, text = ">", size = 0.8, align = "right", layer = 2,
      colour = { 255, 255, 255 }, outline = { 0, 0, 0, 230 } }, function()
      page = page % pages + 1
      M.hooks.redraw()
    end)
    hud.text("pal_page", { x = right - 40 * u, y = top + 3 * u, text = ("%d/%d"):format(page, pages), size = 0.75,
      align = "right", colour = { 220, 220, 225 }, outline = { 0, 0, 0, 230 }, layer = 2 })
    button("pal_prev", { x = right - 80 * u, y = top + 3 * u, text = "<", size = 0.8, align = "right", layer = 2,
      colour = { 255, 255, 255 }, outline = { 0, 0, 0, 230 } }, function()
      page = (page - 2) % pages + 1
      M.hooks.redraw()
    end)
  end

  local k = tile / (52 * u)
  local first = (page - 1) * per
  for n = 1, math.min(per, #items - first) do
    local it = items[first + n]
    local col, row = (n - 1) % cols, (n - 1) // cols
    local x = x0 + col * (tile + gap)
    local y = top + line_h + 6 * u + row * (tile + gap)
    local id = "p_" .. it.id
    local lines = data.entry_lines(it.entry)
    local name = it.entry.name or ""
    hud.rect(id, { x = x, y = y, w = tile, h = tile, round = 5 * u, colour = TILE_BG, layer = 1,
      tip = { title = name, text = table.concat(lines, "\n") .. "\n\nDrag onto a slot; click to edit." } })
    hud.rect(id .. "_f", { x = x - 1, y = y - 1, w = tile + 2, h = tile + 2, round = 6 * u, colour = TILE_EDGE,
      line = 1.2 * u, layer = 0 })
    local act = actions.of({ lines = lines })
    hud.on(id, function(_, e)
      if e.kind == "click" and e.button == "left" then
        M.hooks.edit(it.id)
      else
        ghost.follow(e, id, TILE_BG, TILE_DIM, function()
          return size, act, data.display_label(it.entry)
        end)
      end
    end)
    if act then
      local isz = math.floor(tile * 0.68)
      hud.icon(id .. "_i", { x = x + (tile - isz) / 2, y = y + tile * 0.06, size = isz, kind = act.kind, id = act.id,
        layer = 2 })
    end
    hud.text(id .. "_t", { x = x + tile / 2, y = act and (y + tile - line_h * 0.65 * k - 2 * u) or (y + tile / 2 - 6 * u),
      text = data.display_label(it.entry):match("^[^\n]*"), size = 0.65 * k, align = "center",
      colour = { 240, 240, 245 }, outline = { 0, 0, 0, 230 }, layer = 4 })
  end
  return top
end

return M
