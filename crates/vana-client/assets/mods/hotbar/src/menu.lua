-- A slot's right-click menu (a pop-up at the pointer): clear the slot, or open the manager (where macros are built
-- and dragged onto the bars).

local data = require("src.data")
local jobs = require("src.jobs")
local keys = require("src.keys")
local actions = require("src.actions")

local M = {}

-- Set by init.lua: open_manager(), changed()
M.hooks = {}

local MENU = "slotmenu"
local GOLD = { 232, 210, 156 }
local DIM = { 160, 162, 172 }

local ITEMS = {
  { "Clear the slot", "clear" },
  { "Open the manager", "manager" },
}

function M.open(bar, slot, from)
  local main, sub = jobs.current()
  local macro = main and data.resolve(main, sub, bar, slot)
  local act = macro and actions.of(macro)
  local list, what = {}, {}
  for _, it in ipairs(ITEMS) do
    if it[2] ~= "clear" or macro then
      list[#list + 1] = { it[1] }
      what[#what + 1] = it[2]
    end
  end
  ui.window(MENU, {
    title = ("Bar %d, Slot %d"):format(bar, slot),
    width = 250,
    popup = true,
    elements = {
      { type = "list", id = "head", height = 1, rows = { {
        macro and (data.trim(macro.name) ~= "" and macro.name or (macro.lines[1] or "")) or "Empty slot",
        keys.hint(bar, slot), icon = act and { kind = act.kind, id = act.id } or nil,
        colour = macro and GOLD or DIM } }, columns = { {}, { width = 60, align = "right" } } },
      { type = "separator" },
      { type = "list", id = "acts", rows = list, height = #list },
    },
  })
  ui.on(MENU, function(_, e)
    if e.kind ~= "select" or e.id ~= "acts" then return end
    ui.close(MENU)
    if what[e.index] == "clear" and main then
      data.clear(main, from == "sub" and sub or nil, bar, slot)
      if M.hooks.changed then M.hooks.changed() end
    elseif what[e.index] == "manager" then
      M.hooks.open_manager()
    end
  end)
  ui.open(MENU)
end

return M
