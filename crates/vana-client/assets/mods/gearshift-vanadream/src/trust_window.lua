-- The trust window (/vg trusts window): a trust of the party at a time, who it is and what the server says it uses,
-- its sets with the piece in every slot (pick one yourself, or let the builder), and a row per spell, ability and
-- weapon skill it uses, switched off or on by a click (!trustuse).

local run = require("src.build.run")
local trusts = require("src.trusts")
local pick = require("src.build.pick")

local M = {}
local WIN = "gstrusts"
local view = { trust = 1, set = 1, slot = nil }

local GOOD, FAIR = { 240, 170, 60, 255 }, { 230, 220, 110, 255 }

local function current()
  local list = trusts.called()
  if #list == 0 then return nil, list end
  view.trust = math.max(1, math.min(view.trust, #list))
  return list[view.trust], list
end

local function set_entry(t)
  local plan = trusts.plan_of(t)
  if #plan == 0 then return nil, plan end
  view.set = math.max(1, math.min(view.set, #plan))
  return plan[view.set], plan
end

local function slot_rows(t, entry)
  local final = trusts.final_of_set(t, entry.key)
  local rows = {}
  for slot = 0, 15 do
    local mine = trusts.own_pick(t, entry.name, pick.SLOT_NAMES[slot])
    local note = mine == "remove" and "yours: empty" or (mine and "yours" or "")
    rows[#rows + 1] = { run.SLOT_LABEL[slot], final[slot] or "-", note }
  end
  return rows
end

local function use_rows(t)
  local rows = {}
  for _, u in ipairs(trusts.uses_of(t)) do
    rows[#rows + 1] = { trusts.pretty(u.name), u.kind, u.off and "Off" or "On" }
  end
  return rows
end

local function describe(t)
  local i = trusts.info_of(t)
  if not i then
    return "The server has not answered for this trust (it answers only for your own trusts).", FAIR
  end
  local n = #trusts.uses_of(t)
  return string.format("%s: %s%d / %s, %d actions it uses.", i.name ~= "" and i.name or t.name, t.job, t.level,
    t.sub ~= "" and t.sub or "no support job", n), nil
end

function M.draw()
  local t, list = current()
  local names = {}
  for i, u in ipairs(list) do names[i] = string.format("%s (%s%d)", u.name, u.job, u.level) end
  if not t then
    ui.window(WIN, {
      title = "Trust gear", width = 640,
      help = "Gear for the trusts you call: the sets the server wears for them, built from the pieces in your bags.",
      elements = {
        { type = "text", text = "No trusts in the party. Call one and its sets appear here." },
        { type = "buttons", id = "actions", items = { "Close" } },
      },
    })
    return
  end
  local entry, plan = set_entry(t)
  local labels = {}
  for i, e in ipairs(plan) do labels[i] = e.name end
  local info_text, info_colour = describe(t)
  local b_queue = trusts.queued()
  ui.window(WIN, {
    title = "Trust gear", width = 640,
    help = "Gear for the trusts you call: the sets the server wears for them, built from the pieces in your bags.",
    elements = {
      { type = "dropdown", id = "trust", label = "Trust", items = names, at = view.trust },
      { type = "text", id = "info", text = info_text, colour = info_colour or false },
      { type = "dropdown", id = "set", label = "Set", items = #labels > 0 and labels or { "-" }, at = view.set,
        tip = "A set goes on over Engaged while its action goes off: a spell's kind, a weapon skill or a job ability." },
      { type = "text", id = "when", text = entry and ("Worn for " .. entry.when .. ".") or "Waiting for the server's answer.",
        dim = true },
      { type = "list", id = "slots", rows = entry and slot_rows(t, entry) or {}, height = 16,
        at = view.slot and (view.slot + 1) or nil,
        columns = { { title = "Slot", width = 110 }, { title = "Piece", width = 300 }, { title = "", width = 160 } },
        tip = "Pick a slot to choose its piece yourself or give it back to the builder." },
      { type = "text", id = "uses_head", text = "Uses (click one to switch it off or on for this trust)", dim = true },
      { type = "list", id = "uses", rows = use_rows(t), height = 8,
        columns = { { title = "Action", width = 300 }, { title = "Kind", width = 160 },
          { title = "State", width = 80, align = "right" } } },
      { type = "text", id = "status", text = b_queue > 0 and (b_queue .. " line" .. (b_queue == 1 and "" or "s")
        .. " waiting to go to the server.") or "Everything has been sent.", colour = b_queue > 0 and FAIR or GOOD },
      { type = "buttons", id = "actions", items = { "Send all again", "Rebuild", "Reset set", "Close" } },
    },
  })
end

-- The pieces for a slot, as a menu: automatic, empty, then what we carry that the trust may wear.
local function choose_slot(slot)
  local t = current()
  local entry = t and set_entry(t)
  if not entry then return end
  local cands = trusts.alternatives(t, entry.name, slot)
  local items = { "Automatic", "Empty" }
  for _, c in ipairs(cands) do items[#items + 1] = c.name end
  ui.menu(items, function(i)
    if not i then return end
    local slot_name = pick.SLOT_NAMES[slot]
    if i == 1 then
      trusts.set_pick(t, entry.name, slot_name, nil)
    elseif i == 2 then
      trusts.set_pick(t, entry.name, slot_name, "remove")
    else
      trusts.set_pick(t, entry.name, slot_name, cands[i - 2].name)
    end
    M.draw()
  end)
end

function M.toggle()
  if ui.is_open(WIN) then ui.close(WIN) return end
  M.draw()
  ui.open(WIN)
end

function M.redraw()
  if ui.is_open(WIN) then M.draw() end
end

function M.install()
  ui.on(WIN, function(_, e)
    if e.kind == "set" and e.id == "trust" then
      view.trust, view.set, view.slot = e.index, 1, nil
      M.draw()
    elseif e.kind == "set" and e.id == "set" then
      view.set, view.slot = e.index, nil
      M.draw()
    elseif e.kind == "select" and e.id == "slots" then
      view.slot = e.index - 1
      M.draw()
      choose_slot(view.slot)
    elseif e.kind == "select" and e.id == "uses" then
      local t = current()
      local u = t and trusts.uses_of(t)[e.index]
      if u then trusts.set_off(t, u.name, not u.off) end
      M.draw()
    elseif e.kind == "press" and e.id == "actions" then
      local t = current()
      local entry = t and set_entry(t)
      if not t then
        ui.close(WIN)
      elseif e.index == 1 then
        trusts.send_all()
        M.draw()
      elseif e.index == 2 then
        trusts.rebuild()
        M.draw()
      elseif e.index == 3 then
        if entry then trusts.reset_set(t, entry.name) end
        M.draw()
      else
        ui.close(WIN)
      end
    end
  end)
end

return M
