-- Trust gear tab (//vg page 2).

local run = require("src.build.run")
local trusts = require("src.trusts")
local pick = require("src.build.pick")
local grid = require("src.equip_grid")

local M = {}
local PAGE = 2
local view = { trust = 1, set = 1, slot = nil, uses_top = 0 }

local GOOD, FAIR = { 240, 170, 60, 255 }, { 230, 220, 110, 255 }
local OFF = { 150, 150, 150, 255 }
local MUTED = { 140, 140, 140, 255 }
local DIVIDER = { 100, 95, 85, 140 }

local ROW_H = 17
local USES_HEAD = 36

local use_hits = {}

local function page(e)
  e.page = PAGE
  return e
end

local function win_mod()
  return require("src.build.window")
end

local function uses_x0()
  return grid.SIZE + win_mod().USES_GAP
end

local function uses_visible_rows()
  return math.max(1, math.floor((grid.SIZE - USES_HEAD - 10) / ROW_H))
end

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

local function id_of_name(name)
  if not name or name == "-" then return nil end
  local ids = run.state and run.state.names and run.state.names[name]
  return ids and ids[1]
end

local function trust_grid(t, entry)
  local final = trusts.final_of_set(t, entry.key)
  local ids, labels, tips, hand = {}, {}, {}, {}
  for slot = 0, 15 do
    local piece = final[slot]
    local mine = trusts.own_pick(t, entry.name, pick.SLOT_NAMES[slot])
    local title = run.SLOT_LABEL[slot]
    if piece and piece ~= "-" then
      ids[slot] = id_of_name(piece)
      labels[slot] = piece
      local note = mine == "remove" and "Slot left empty by you." or (mine and "Picked by you." or "")
      tips[slot] = { title = title, text = piece .. (note ~= "" and (" — " .. note) or "") }
      if mine then hand[slot] = true end
    else
      tips[slot] = { title = title, text = mine == "remove" and "Empty by your choice." or "Empty" }
    end
  end
  return grid.draw({ ids = ids, labels = labels, tips = tips, hand = hand, selected = view.slot }, grid.SIZE)
end

local function draw_uses_panel(t, out)
  local x0, panel_w = uses_x0(), win_mod().USES_W
  local uses = trusts.uses_of(t)
  local vis = uses_visible_rows()
  local max_top = math.max(0, #uses - vis)
  view.uses_top = math.max(0, math.min(view.uses_top or 0, max_top))

  use_hits = {}

  out[#out + 1] = { type = "line", x1 = x0 - 6, y1 = 4, x2 = x0 - 6, y2 = grid.SIZE - 4, width = 1, colour = DIVIDER }
  out[#out + 1] = { type = "text", x = x0, y = 4, text = "Uses", size = 1, colour = { 220, 220, 220, 255 } }
  out[#out + 1] = { type = "text", x = x0, y = 18, text = "Click to toggle (grey = off)", size = 1, colour = MUTED }

  if #uses == 0 then
    out[#out + 1] = { type = "text", x = x0, y = USES_HEAD, text = "Waiting for the server…", size = 1, colour = MUTED }
    return
  end

  if view.uses_top > 0 then
    local uy = USES_HEAD - 14
    out[#out + 1] = { type = "tip", x = x0 + panel_w - 26, y = uy, w = 24, h = 14, title = "", text = "Scroll up" }
    out[#out + 1] = { type = "text", x = x0 + panel_w - 20, y = uy + 1, text = "^", size = 1, colour = { 200, 200, 200, 255 } }
    use_hits[#use_hits + 1] = { scroll = -1, x = x0 + panel_w - 28, y = uy, w = 28, h = 14 }
  end

  for row = 1, vis do
    local idx = view.uses_top + row
    local u = uses[idx]
    if not u then break end
    local y = USES_HEAD + (row - 1) * ROW_H
    local ink = u.off and OFF or { 220, 220, 220, 255 }
    local label = trusts.pretty(u.name)
    local tip = (u.off and "Off — click to turn on." or "On — click to turn off.") .. "  " .. (u.kind or "")
    out[#out + 1] = { type = "tip", x = x0, y = y, w = panel_w, h = ROW_H - 2, title = label, text = tip }
    out[#out + 1] = { type = "text", x = x0 + 2, y = y + 2, text = label, size = 1, colour = ink }
    if u.kind and u.kind ~= "" then
      out[#out + 1] = { type = "text", x = x0 + panel_w - 6, y = y + 2, text = u.kind, size = 1, align = "right",
        colour = MUTED }
    end
    use_hits[#use_hits + 1] = { index = idx, x = x0, y = y, w = panel_w, h = ROW_H - 2 }
  end

  if view.uses_top < max_top then
    local by = USES_HEAD + vis * ROW_H
    out[#out + 1] = { type = "tip", x = x0 + panel_w - 26, y = by, w = 24, h = 14, title = "", text = "Scroll down" }
    out[#out + 1] = { type = "text", x = x0 + panel_w - 20, y = by + 1, text = "v", size = 1, colour = { 200, 200, 200, 255 } }
    use_hits[#use_hits + 1] = { scroll = 1, x = x0 + panel_w - 28, y = by, w = 28, h = 14 }
  end
end

local function trust_body(t, entry)
  if not entry then return {} end
  local out = trust_grid(t, entry)
  draw_uses_panel(t, out)
  return out
end

local function slot_detail(t, entry)
  if view.slot == nil then return "Click a slot in the grid to pick a piece for this trust's set." end
  if not entry then return "" end
  local final = trusts.final_of_set(t, entry.key)
  local piece = final[view.slot] or "-"
  local mine = trusts.own_pick(t, entry.name, pick.SLOT_NAMES[view.slot])
  local note = mine == "remove" and " (empty by your choice)" or (mine and " (picked by you)" or "")
  return run.SLOT_LABEL[view.slot] .. ": " .. piece .. note
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

local function hit_uses(x, y)
  for _, h in ipairs(use_hits) do
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then return h end
  end
end

function M.elements()
  local t, list = current()
  if #list == 0 then
    return { page({ type = "text", id = "t_none", text = "No trusts in the party. Call one and its sets appear here." }) }
  end
  local names = {}
  for i, u in ipairs(list) do names[i] = string.format("%s (%s%d)", u.name, u.job, u.level) end
  local entry, plan = set_entry(t)
  local labels = {}
  for i, e in ipairs(plan) do labels[i] = e.name end
  local info_text, info_colour = describe(t)
  local b_queue = trusts.queued()
  local body_w = win_mod().trust_canvas_w()
  return {
    page({ type = "dropdown", id = "t_trust", label = "Trust", items = names, at = view.trust }),
    page({ type = "text", id = "t_info", text = info_text, colour = info_colour or false }),
    page({ type = "dropdown", id = "t_set", label = "Set", items = #labels > 0 and labels or { "-" }, at = view.set,
      tip = "A set goes on over Engaged while its action goes off: a spell's kind, a weapon skill or a job ability." }),
    page({ type = "text", id = "t_when", text = entry and ("Worn for " .. entry.when .. ".") or
      "Waiting for the server's answer.", dim = true }),
    page({ type = "canvas", id = "t_gear", w = body_w, h = grid.SIZE,
      draw = entry and trust_body(t, entry) or {},
      tip = "Equipment grid on the left; Uses on the right. Click a slot or an action." }),
    page({ type = "text", id = "t_slot_detail", text = entry and slot_detail(t, entry) or "", dim = true }),
    page({ type = "text", id = "t_status", text = b_queue > 0 and (b_queue .. " line" .. (b_queue == 1 and "" or "s")
      .. " waiting to go to the server.") or "Everything has been sent.", colour = b_queue > 0 and FAIR or GOOD }),
    page({ type = "buttons", id = "t_actions", items = { "Send all again", "Rebuild trusts", "Reset set" } }),
  }
end

local function choose_slot(slot, redraw)
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
    redraw()
  end)
end

function M.on_event(e, redraw)
  if e.kind == "set" and e.id == "t_trust" then
    view.trust, view.set, view.slot, view.uses_top = e.index, 1, nil, 0
    redraw()
  elseif e.kind == "set" and e.id == "t_set" then
    view.set, view.slot = e.index, nil
    redraw()
  elseif e.kind == "click" and e.id == "t_gear" and e.button == "left" then
    local x0 = uses_x0()
    if e.x >= x0 - 8 then
      local h = hit_uses(e.x, e.y)
      if h and h.scroll then
        view.uses_top = math.max(0, (view.uses_top or 0) + h.scroll)
        redraw()
      elseif h and h.index then
        local t = current()
        local u = t and trusts.uses_of(t)[h.index]
        if u then trusts.set_off(t, u.name, not u.off) end
        redraw()
      end
    else
      local slot = grid.hit(e.x, e.y)
      if slot then
        view.slot = slot
        redraw()
        choose_slot(slot, redraw)
      end
    end
  elseif e.kind == "press" and e.id == "t_actions" then
    local t = current()
    local entry = t and set_entry(t)
    if e.index == 1 then
      trusts.send_all()
      redraw()
    elseif e.index == 2 then
      trusts.rebuild()
      redraw()
    elseif e.index == 3 and entry then
      trusts.reset_set(t, entry.name)
      redraw()
    end
  end
end

function M.draw()
  local w = require("src.build.window")
  w.open_tab(2)
end

function M.toggle()
  local w = require("src.build.window")
  if ui.is_open(w.WIN) then
    if w.tab() == 2 then ui.close(w.WIN) else w.open_tab(2) end
  else
    w.open_tab(2)
  end
end

function M.redraw()
  if ui.is_open(require("src.build.window").WIN) then require("src.build.window").draw() end
end

return M