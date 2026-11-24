-- HUD gauges, not ui.window: focus and last target share XIV Target Bar's art.
local palette = require("src.target_palette")
local X = require("src.xiv")
local built, enabled, last = false, true, nil
local preview=false
local shown=false
local cfg=require('src.hud_config').new(settings,require('src.config_schema'),{
 capture=function()return {enabled=enabled,preview=preview} end,
 preview=function(on)enabled=true;preview=on;last=nil end,
 restore=function(s)enabled=s.enabled;preview=s.preview;last=nil end,
})
local settings=cfg.settings
local move_units=1
local draggers={focus=require('src.hud_drag').new(cfg,'offset_x','offset_y',function()return move_units end),last=require('src.hud_drag').new(cfg,'last_x','last_y',function()return move_units end)}
mods.provide('busy',function()return require('src.hud_config').active() end)
local suffixes = { "track", "fill", "border", "name", "hpp", "grip" }
local kinds = { { "focus", "Focus", "focus_target" }, { "last", "Last", "last_target" } }

-- One switch per readout.
local function show_kind(k)
  if k == "focus" then return settings.get("show_focus") ~= false end
  return settings.get("show_last") ~= false
end

local function hide()
  if not built or not shown then return end
  for _, row in ipairs(kinds) do
    for _, s in ipairs(suffixes) do hud.set("xft_" .. row[1] .. "_" .. s, { visible = false }) end
  end
  shown=false
end

local function ensure()
  if built then return end
  for _, row in ipairs(kinds) do
    local id, field = "xft_" .. row[1], row[3]
    for i, part in ipairs({ { "track", "bar_track" }, { "fill", "fill_white" }, { "border", "bar_border" } }) do
      hud.image(id .. "_" .. part[1], { path = "img/" .. part[2] .. ".png", x = 0, y = 0, w = 300, h = 12, layer = 9 + i, visible = false })
    end
    for _, part in ipairs({ "name", "hpp" }) do
      hud.text(id .. "_" .. part, { x = 0, y = 0, text = "", size = 1, font = "regular",
        align = part == "hpp" and "right" or "left", outline = { 0, 0, 0, 210 }, layer = 13, visible = false })
    end
    hud.rect(id .. "_grip", { x = 0, y = 0, w = 300, h = 34, colour = { 0, 0, 0, 1 }, layer = 14, visible = false })
    hud.on(id .. "_grip", function(_, e)
      if draggers[row[1]](e) then return end
      if e.kind == "click" and (not e.button or e.button=='left') then
        local me = game.player()
        if me and me[field] then X.target(me[field]) end
      end
    end)
  end
  built = true
end

local draw_at = -1
events.on("frame", function()
  -- Settled gate: once built (`last` set), re-check at ~15 Hz; unbuilt or hidden runs every frame.
  local now = os.clock()
  if last and now - draw_at < .066 then return end
  draw_at = now
  local on = enabled and settings.get("on")
  X.native("focus", on)
  local me = on and game.player()
  if preview and on then me={focus_target=-1,last_target=-2} end
  if not me then hide(); last = nil; return end
  local rows, sig = {}, {}
  local looked,entity
  for _, row in ipairs(kinds) do
    if show_kind(row[1]) then
      local key = me[row[3]]
      if key and key~=looked and not preview then entity=game.entity(key);looked=key end
      local t = preview and {id=key,name='PREVIEW '..row[2],kind='mob',hpp=73,targetable=true} or (key and entity)
      if t and not t.hidden and t.targetable ~= false then
        local colours=palette(t)
        rows[#rows + 1] = { row = row, entity = t, colours = colours }
        sig[#sig + 1] = table.concat({ row[1], t.id, t.hpp or 0, t.name or "", table.concat(colours.fill, ",") }, ":")
      end
    end
  end
  local scr = hud.screen()
  local anchor = X.call("xiv-target-bar", "layout")
  if preview then anchor=nil end
  sig[#sig + 1] = table.concat({ scr.width, scr.height, scr.ui_scale, settings.get("width"),
    anchor and anchor.x or 0, anchor and anchor.y or 0, anchor and anchor.bottom or 0, anchor and anchor.w or 0,
    anchor and anchor.scale or 1,settings.get('scale'),settings.get('offset_x'),settings.get('offset_y'),settings.get('last_x'),settings.get('last_y'),tostring(settings.get('show_focus')),tostring(settings.get('show_last')) }, ":")
  local key = table.concat(sig, "|")
  if key == last then return end
  ensure(); hide()
   local sc = (anchor and anchor.scale or 1)*(settings.get('scale') or 100)/100
   local u = scr.ui_scale * sc
   move_units=u
  local w = math.min(settings.get("width") * u, scr.width)
  local focus_index = 0
  for _, item in ipairs(rows) do
    local t, p, row = item.entity, item.colours, item.row
    local id = "xft_" .. row[1]
    local x, y
    if row[1] == "last" then
      -- Last target is its own lower-right readout, not a centred sub-line.
      local margin = 18 * u
      local bottom = math.max(96 * u, scr.height * 0.16)
      x = X.clamp(scr.width - w - margin, 0, math.max(0, scr.width - w))
      y = math.max(30 * u, scr.height - bottom)
    else
      focus_index = focus_index + 1
      x = X.clamp(anchor and anchor.x + anchor.w - w or (scr.width - w) / 2,
        0, math.max(0, scr.width - w))
      y = (anchor and anchor.bottom or scr.height * 0.12 + 50 * u)
        + (focus_index - 1) * 46 * u + 24 * u
    end
    local dx=row[1]=='last' and settings.get('last_x') or settings.get('offset_x')
    local dy=row[1]=='last' and settings.get('last_y') or settings.get('offset_y')
    x=X.clamp(x+(dx or 0)*u,0,math.max(0,scr.width-w))
    y=X.clamp(y+(dy or 0)*u,22*u,math.max(22*u,scr.height-12*u))
    if y + 12 * u > scr.height then
      X.native("focus", false)
      break
    end
    local frac = math.max(0, math.min(1, (t.hpp or 0) / 100))
    hud.set(id .. "_track", { x = x, y = y, w = w, h = 12 * u, colour = p.track, visible = true })
    hud.set(id .. "_fill", { x = x, y = y, w = math.max(1, frac * w), h = 12 * u, colour = p.fill, visible = frac > 0 })
    hud.set(id .. "_border", { x = x, y = y, w = w, h = 12 * u, colour = p.border, visible = true })
    hud.set(id .. "_name", { x = x, y = y - 20 * u, size = sc, text = row[2] .. ": " .. (t.name or ""), colour = p.text, visible = true })
    hud.set(id .. "_hpp", { x = x + w, y = y - 20 * u, size = sc, text = tostring(t.hpp or 0) .. "%", colour = p.text, visible = true })
    hud.set(id .. "_grip", { x = x, y = y - 22 * u, w = w, h = 34 * u, visible = true })
    shown=true
  end
  last = key
end)

commands.register("xft", function(arg)
  local want = tostring(arg or ""):lower():gsub("%s+", "")
  if want == "focus" then
    -- Set the focus to the current target (one of our party, not us): /focustarget <pN>.
    local t = game.target()
    if not t or not t.id then chat.add("XIV focus: target a party member first."); return end
    local slot
    for _, m in ipairs(game.party() or {}) do if m.id == t.id then slot = m.slot end end
    if not slot or slot < 1 or slot > 5 then
      chat.add("XIV focus: your target is not a party member (slots 1-5, not you)."); return
    end
    commands.run(("/focustarget <p%d>"):format(slot))
    last = nil
    chat.add(("XIV focus: set to <p%d>."):format(slot))
    return
  elseif want == "target" then
    local me = game.player()
    if me and me.focus_target then X.target(me.focus_target) else chat.add("XIV focus: no focus target set.") end
    return
  elseif want == "last" then
    local me = game.player()
    if me and me.last_target then X.target(me.last_target) else chat.add("XIV focus: no last target.") end
    return
  end
  if want == "on" then enabled = true
  elseif want == "off" then enabled = false
  elseif want == "status" then chat.add("XIV Focus and Last Target: " .. (enabled and "on." or "off.")); return
  elseif want == "" then enabled = not enabled
  else chat.add("Usage: //xft [on|off|status|focus|target|last]"); return end
  if not enabled then hide(); X.native("focus", false) end
  last = nil
  chat.add("XIV Focus and Last Target: " .. (enabled and "on." or "off."))
end)

