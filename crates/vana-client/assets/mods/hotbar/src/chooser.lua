-- A group slot's list: pressing the slot opens its members in a list over it (under it on the top edge), the one
-- picked last under the cursor. Up / Down and Enter, a click, or a member's number (the bars' keys 1, 2, ...) run
-- one, and the gamepad's d-pad and A (src/pad.lua); Escape, B or a click elsewhere closes it. It opens and closes with a short fold.

local data = require("src.data")
local actions = require("src.actions")
local runner = require("src.runner")

local M = {}

-- Set by bar.lua: picked() after a member ran (its slot shows that one now).
M.hooks = {}

local WIN = "group"
local WIDTH = 240
M.WIDTH = WIDTH
local DIM = { 160, 152, 136, 255 }
local SUGGESTED = { 255, 214, 120, 255 }

local open_macro = nil
-- The bar whose slot opened the list: its keys pick members by number, another bar's keys act as usual.
local open_bar = nil

local function clock(secs)
  secs = math.ceil(secs)
  return secs >= 60 and ("%d:%02d"):format(secs // 60, secs % 60) or tostring(secs)
end

local function rows_of(macro, suggested)
  local recasts = game.recasts()
  local rows = {}
  for k, m in ipairs(macro.group) do
    local a = actions.of(m)
    local left = a and actions.recast(a, recasts) or 0
    local name = data.trim(m.name) ~= "" and m.name or (m.lines[1] or "")
    rows[k] = { name, left > 0 and clock(left) or "", tostring(k), icon = a and { kind = a.kind, id = a.id } or nil,
      colour = suggested and suggested(m) and SUGGESTED or (a and not actions.usable(a, game.player()) and DIM) or nil }
  end
  return rows
end

function M.is_open()
  return open_macro ~= nil and ui.is_open(WIN)
end

local function close()
  open_macro, open_bar = nil, nil
  if ui.is_open(WIN) then ui.close(WIN) end
end
M.close = close

-- The bar the open list came from (nil: none, or not opened from a bar).
function M.bar()
  return M.is_open() and open_bar or nil
end

-- Runs member k of the open group and closes the list.
function M.pick(k)
  local macro = open_macro
  local m = macro and macro.group[k]
  if not m then return end
  close()
  data.set_last_member(macro, k)
  runner.run_checked(m)
  if M.hooks.picked then M.hooks.picked() end
end

-- The controller's: the cursor one row up (-1) or down (1), wrapping; and Accept, which runs the row it is on.
function M.step(delta)
  if not M.is_open() then return end
  local n = #open_macro.group
  local at = ui.get(WIN, "m").at or 1
  ui.update(WIN, "m", { at = (at - 1 + delta) % n + 1 })
end

function M.accept()
  if not M.is_open() then return end
  M.pick(ui.get(WIN, "m").at or 1)
end

-- Opens a group's list; `at` is where on screen ({x, y, above} in window pixels), else at the pointer; members
-- `suggested(member)` names (the battle menu's suggestions) show in gold; `bar` the bar whose slot opened it.
function M.open(macro, at, suggested, bar)
  if not macro.group or #macro.group == 0 then return end
  local rows = rows_of(macro, suggested)
  ui.window(WIN, {
    title = data.trim(macro.name) ~= "" and macro.name or "Group",
    width = WIDTH,
    popup = true,
    animate = true,
    help = "Up / Down, then Enter or A. Escape or B closes.",
    elements = {
      { type = "list", id = "m", rows = rows, height = #rows, at = data.last_member(macro),
        columns = { { title = "" }, { title = "", width = 46, align = "right" },
          { title = "", width = 20, align = "right" } } },
    },
  })
  open_macro, open_bar = macro, bar
  ui.open(WIN, at)
end

ui.on(WIN, function(_, e)
  if e.kind == "select" then
    M.pick(e.index)
  elseif e.kind == "close" then
    open_macro, open_bar = nil, nil
  end
end)

return M
