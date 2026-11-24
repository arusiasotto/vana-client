-- M18 bundled sources; generated from stage sources. Do not edit.
return {
["src.xiv"]=[[
-- Shared, vendored HUD primitives. No cross-mod file reads or automatic saves.
local X = { version = 7 }
X.text_colour = { 240, 255, 255, 255 }
X.stroke = { 6, 45, 84, 210 }
local roles = { war = "tank", pld = "tank", run = "tank", pup = "tank", whm = "healer", sch = "healer",
  cor = "support", geo = "support" }
local colours = { tank = { 48, 58, 124, 255 }, healer = { 64, 101, 45, 255 },
  support = { 218, 178, 0, 255 }, dps = { 106, 45, 43, 255 } }
function X.role(code) return code and colours[roles[code] or "dps"] or { 128, 128, 128, 255 } end
function X.clamp(v, lo, hi) return math.max(lo, math.min(hi, tonumber(v) or lo)) end
-- The game and XivUI show 59, 1m, 1h rather than raw seconds once a minute has passed.
function X.fmt_time(seconds)
  local n = tonumber(seconds)
  if not n or n < 0 then return nil end
  if n >= 3600 then return math.floor(n / 3600) .. "h"
  elseif n > 60 then return math.floor(n / 60) .. "m"
  else return tostring(math.floor(n)) end
end
function X.id(v) return type(v) == "number" and v >= 0 and v < 65535 and v % 1 == 0 end
local function hud_config_active()
  local req = X._module_require
  if type(req) == "function" then
    local m = req("src.hud_config")
    if type(m) == "table" and type(m.active) == "function" then return m.active() end
  end
  local ok, m = pcall(require, "src.hud_config")
  return ok and type(m) == "table" and type(m.active) == "function" and m.active()
end
function X.target(id)
  if hud_config_active() then return false end
  if type(id)~='number' or id<=0 or id>4294967295 or id%1~=0 then return false end
  local entity=game.entity(id)
  if not entity or entity.id~=id or entity.hidden or entity.targetable==false then return false end
  local ok=pcall(actions.target,id)
  if not ok and not X.target_warning then chat.add('XIV HUD: targeting unavailable; review this mod actions permission.');X.target_warning=true end
  return ok
end
function X.short(s, n)
  s = tostring(s or "")
  local ok, at = pcall(utf8.offset, s, n + 1)
  return ok and at and s:sub(1, at - 1) .. "..." or s
end
function X.call(mod, method, ...)
  if not mods or not mods.call then return nil end
  local ok, value = pcall(mods.call, mod, method, ...)
  return ok and value or nil
end
local files = {}
local warnings = {}
local native_state={}
for _,event in ipairs({'zone_change','settings_changed'}) do events.on(event,function()native_state={} end) end
function X.native(piece, hidden)
  if hidden and X.active_renderer and X.active_renderer.incomplete then hidden=false end
  local old=native_state[piece]
  if old and old.hidden==hidden and clock()-old.at<1 then return old.ok end
  local ok = pcall(function() ui.native.hide(piece, hidden) end)
  native_state[piece]={hidden=hidden,at=clock(),ok=ok}
  if ok then warnings[piece] = nil
  elseif not warnings[piece] then
    chat.add("XIV HUD: native " .. piece .. " replacement unavailable; check ui.native permission/client support.")
    warnings[piece] = true
  end
  return ok
end
function X.exists(path)
  if files[path] == nil then files[path] = fs.exists(path) end
  return files[path]
end
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local function copy(a)
  if type(a) ~= "table" then return a end
  local b = {}; for k, v in pairs(a) do b[k] = copy(v) end; return b
end
local R = {}; R.__index = R
function X.renderer() return setmetatable({ state = {}, seen = {}, waiting = {}, handlers = {} }, R) end
-- A native PNG/resource call cannot be interrupted from Lua. Stop issuing more
-- once this draw has spent 4 ms; the next fresh draw retries uncommitted specs.
-- Nothing stale is queued across targets/zones. Native fallbacks remain visible.
function R:begin()
  self.seen={};self.work_at=clock();self.incomplete=false;self.calls=0;self.heavy=0;X.active_renderer=self
  self.retry=self.waiting or {};self.waiting={}
end
function R:allow(id)
  if (self.retry and next(self.retry) and not self.retry[id]) or (self.calls or 0)>=8 or
      ((self.calls or 0)>0 and self.work_at and clock()-self.work_at>=0.004) then
    self.waiting=self.waiting or {};self.waiting[id]=true;self.incomplete=true;return false
  end
  if self.retry then self.retry[id]=nil end
  self.calls=(self.calls or 0)+1
  return true
end
function R:create(id)
  return self:allow(id)
end
function R:ready() return not self.incomplete end
function R:put(kind, id, spec)
  self.seen[id] = true
  spec.visible = spec.visible ~= false
  local old = self.state[id]
  if not old then
    -- Image creation is the slow native call (PNG load + upload, ~1-2 ms). Admit at most
    -- one slow creation per draw; the rest wait for the next draw like any budget miss.
    if kind=='image' and (self.heavy or 0)>=1 then self.waiting=self.waiting or {};self.waiting[id]=true;self.incomplete=true;return end
    if not self:create(id) then return end
    local t0=clock();hud[kind](id, spec); self.state[id] = copy(spec)
    if kind=='image' and clock()-t0>=.0006 then self.heavy=(self.heavy or 0)+1 end
    return
  end
  local delta = {}
  for k, v in pairs(spec) do if not same(v, old[k]) then delta[k] = v end end
  -- hud.set adopts the new PNG's native size when path changes. Reassert the
  -- intended size so swapping a debuff/buff/job picture cannot enlarge it.
  if kind == "image" and old.path ~= spec.path and spec.w and spec.h then
    delta.w, delta.h = spec.w, spec.h
  end
  if next(delta) then if not self:allow(id) then return end;hud.set(id, delta); for k, v in pairs(delta) do old[k] = copy(v) end elseif self.retry then self.retry[id]=nil end
end
function R:finish()
  for id, s in pairs(self.state) do
    if not self.seen[id] and s.visible then if self:allow(id) then hud.set(id, { visible = false }); s.visible = false end end
  end
  for id in pairs(self.waiting or {}) do
    local state=self.state[id]
    if not self.seen[id] and not (state and state.visible) then self.waiting[id]=nil end
  end
  if self.incomplete then
    for piece,entry in pairs(native_state) do if entry.hidden then X.native(piece,false) end end
  end
end
function R:hide() self:begin(); self:finish() end
function R:image(id, path, x, y, w, h, layer, colour, tip)
  self:put("image", id, { path = path, x = x, y = y, w = math.max(1, w), h = math.max(1, h),
    layer = layer, colour = colour or false, tip = tip or false })
end
function R:text(id, text, x, y, px, scale, layer, colour, align, bold)
  local size = px / 14 * scale
  self:put("text", id, { text = tostring(text or ""), x = x, y = y, size = size,
    font = bold and "bold" or "regular", colour = colour or X.text_colour, align = align or "left",
    outline = X.stroke, outline_width = scale / math.max(1, size), layer = layer })
end
function R:grip(id, x, y, w, h, layer, handler, tip)
  self:put("rect", id, { x = x, y = y, w = w, h = h, colour = { 0, 0, 0, 1 },
    layer = layer, tip = tip or false })
  if self.state[id] and not self.handlers[id] and self:allow(id) then
    hud.on(id,function(element,e)if self.incomplete then return end;if self.drag and self.drag(e) then return end;return handler(element,e) end)
    self.handlers[id]=true
  end
end
local replacement = { poison = "poison", paralysis = "paralyze", paralyze = "paralyze", blindness = "blind",
  blind = "blind", silence = "silence", mute = "silence", slow = "slow", bind = "bind", weight = "heavy",
  sleep = "sleep", petrification = "petrify", stun = "stun", doom = "doom", curse = "doom", amnesia = "amnesia",
  addle = "addle", dia = "dia", bio = "miasma", plague = "miasma", disease = "disease", terror = "petrify",
  charm = "hysteria", burn = "burn", frost = "frostbite", choke = "windburn", rasp = "sludge",
  shock = "electrocution", drown = "dropsy", ["accuracy down"] = "accuracy_down",
  ["defense down"] = "damage_down", ["magic defense down"] = "mag_vuln", weakness = "weakness" }
local status_names,status_info={},{}
function X.status_name(id)
  local value=status_names[id]
  if not value then value=res.status(id);if value then status_names[id]=value end end
  return value
end
function X.status_info(id)
  local value=status_info[id]
  if not value and res.status_info then value=res.status_info(id);if value then status_info[id]=value end end
  return value
end
function X.debuff(id, name)
  return id <= 20 or replacement[tostring(name):lower():gsub("%s+%d+$", "")] ~= nil
    or tostring(name):lower():find("down$", 1) ~= nil or tostring(name):lower():find("daze", 1, true) ~= nil
end
function X.statuses(list, hidden, priority)
  if type(list) ~= "table" then list = {} end
  if type(hidden) ~= "table" then hidden = nil end
  if type(priority) ~= "table" then priority = {} end
  local out, seen, rank = {}, {}, {}
  for i, id in ipairs(priority or {}) do if X.id(tonumber(id)) then rank[tonumber(id)] = i end end
  for _, e in ipairs(list or {}) do
    if type(e) == "number" then e = { id = e } end
    if type(e) ~= "table" then e = {} end
    local id = e.id or e.status
    if X.id(id) and not seen[id] and not (hidden and hidden[tostring(id)]) then
      local left = e.left or e.remaining
      if left == nil or left > 0 then
        local status_name = X.status_name(id) or ("Status " .. id)
        local name = e.name or status_name
        local info = X.status_info(id)
        out[#out + 1] = { id = id, name = name, status_name = status_name, left = left, total = e.secs or e.total,
          untimed = info and info.untimed or false,
          debuff = X.debuff(id, status_name), source = e.source or (left and "Tracked duration (estimated)" or "Observed; duration unknown") }
        seen[id] = true
      end
    end
  end
  table.sort(out, function(a, b)
    local ar, br = rank[a.id] or 999, rank[b.id] or 999
    if ar ~= br then return ar < br end
    if a.debuff ~= b.debuff then return a.debuff end
    return a.id < b.id
  end)
  return out
end
function R:status(id, row, x, y, size, scale, layer, enemy, show_time)
  local name = (row.status_name or X.status_name(row.id) or row.name):lower():gsub("%s+%d+$", "")
  local stem = enemy and replacement[name]
  local path = stem and ("img/debuff_icons/" .. stem .. ".png") or ("img/buffs/" .. row.id .. ".png")
  local info = X.status_info(row.id)
  local tip = { title = row.name, text = (info and info.description or "") .. "\n" .. row.source }
  if X.exists(path) then self:image(id .. "_pic", path, x, y, size, size, layer, nil, tip)
  elseif not X.status_name(row.id) and X.exists("img/debuff_icons/icon_bg.png") then
    self:image(id .. "_unknown", "img/debuff_icons/icon_bg.png", x, y, size, size, layer, nil, tip)
    self:text(id .. "_mark", "?", x + size / 2, y, 10, scale, layer + 1, nil, "center")
  else self:put("icon", id .. "_native", { kind = "status", id = row.id, x = x, y = y, size = size, layer = layer, tip = tip }) end
  local label = show_time~=false and not row.untimed and X.fmt_time(row.left)
  if label then self:text(id .. "_time", label, x + size, y + size - 5 * scale,
    8, scale, layer + 1, nil, "right", true) end
end
return X
]],
["src.requests"]=[[
-- Recent invite reminders, not a claim about native pending-request state.
-- Respond only through the native Party menu; never call join/decline directly.
local X=require('src.xiv')
local hud_config=require('src.hud_config')
local base_settings=settings
local settings={get=function(key)return hud_config.read(key,base_settings) end}
local R=X.renderer()
local M={window='xn_requests'}
local latest,sequence,hovered=nil,0,false
local preview=false
local busy_until=0
local banner
local last_presentation,shown=nil,false
local function same_key(a,b)
  if not a or #a~=#b then return false end
  for i=1,#b do if a[i]~=b[i] then return false end end
  return true
end
local function hide()
  if shown or not R:ready() then R:hide() end
  last_presentation=nil;shown=false
end
local function current()
  if preview then return {from='PREVIEW player',kind='party',sequence=-1,at=clock(),expires=clock()+120,preview=true} end
  if latest and clock()>=latest.expires then latest=nil;ui.close(M.window) end
  return latest
end
function M.reset()latest=nil;banner=nil;hovered=false;sequence=sequence+1;busy_until=0;ui.close(M.window);R:hide();last_presentation=nil;shown=false end
function M.preview(on)preview=on;last_presentation=nil;ui.close(M.window) end
function M.busy()return ui.is_open(M.window) or clock()<busy_until end
function M.open()
  local info=game.info()
  if info.menu_open then chat.add('XIV Notify: close the current game menu first.');return end
  for _, owner in ipairs({ "xiv-target-bar", "xiv-party-list" }) do
    local ok, busy = pcall(mods.call, owner, "busy")
    if ok and busy then chat.add("XIV Notify: close the current detail window first."); return end
  end
  local request=current()
  if not request then chat.add('XIV Notify: no recent invite reminder. Use the native Party menu to check invitations.');return end
  local token=request.sequence
  ui.window(M.window,{title=request.preview and 'PREVIEW — invitation reminder' or 'Recent '..request.kind..' invitation',width=420,modal=true,elements={
    {type='text',id='from',text='Received from: '..request.from},
    {type='text',id='hint',text='This records a received invite, not verified pending state. The native Party menu checks the current invitation and handles Join/Decline.'},
    {type='buttons',id='respond_'..token,items={'Open native Party menu','Close'}},
  }})
  ui.open(M.window)
end
ui.on(M.window,function(_,e)
  if e.kind~='press' then return end
  local request=current()
  if not request or e.id~='respond_'..request.sequence then return end
  if e.index~=1 then ui.close(M.window);return end
  if request.preview then ui.close(M.window);return end
  -- A genuine user press only opens a menu. It cannot accept another inviter.
  local ok=pcall(function()actions.open_menu('party') end)
  if ok then busy_until=clock()+0.25;ui.close(M.window)
  else ui.update(M.window,'hint',{text='Opening the native menu is unavailable. Check the actions permission, or open Party through the game main menu. No invitation response was sent.'}) end
end)
events.on('party_invite',function(from,kind)
  if type(from)~='string' or from=='' or (kind~='party' and kind~='alliance') then return end
  from=X.short(text.strip(from),24)
  local duplicate=latest and latest.from==from and latest.kind==kind and clock()-latest.at<2
  sequence=sequence+1;latest={from=from,kind=kind,sequence=sequence,at=clock(),expires=clock()+120}
  ui.close(M.window)
  if not duplicate then banner={text=from..' sent a '..kind..' invite',at=clock()} end
end)
for _,event in ipairs({'login','logout','zone_change'}) do events.on(event,M.reset) end
events.on('party_change',function()ui.close(M.window) end)
function M.draw(show,scale)
  local request=current()
  if not show or not request then hide();return end
  local s=hud.screen();local u=s.ui_scale*scale
  local w,h=150*u,34*u
  if w>s.width-8 or h>s.height-8 then hide();return end
  local alpha=banner and not preview and clock()-banner.at<3 and math.floor(255*(1-(clock()-banner.at)/3)) or false
  local key={request.sequence,preview,hovered,s.width,s.height,s.ui_scale,scale,
    settings.get('request_offset_x') or 0,settings.get('request_offset_y') or 0,alpha}
  if same_key(last_presentation,key) and R:ready() then return end
  R:begin();shown=true
  -- Default centre placement avoids the fixed right-hand alliance panels.
  local x=X.clamp((s.width-w)/2+(settings.get('request_offset_x') or 0)*u,0,s.width-w)
  local y=X.clamp(s.height*0.38+(settings.get('request_offset_y') or 0)*u,0,math.max(0,s.height-h))
  R:image('xr_pill',hovered and 'img/pill_hover.png' or 'img/pill.png',x,y,w,h,45,nil,
    {title='Recent '..request.kind..' invite',text='Not verified pending state. Open the native Party menu to respond.'})
  R:text('xr_type',request.preview and 'PREVIEW invite' or 'Recent '..request.kind,x+12*u,y+3*u,9,scale,46)
  R:text('xr_from',X.short(request.from,19),x+12*u,y+16*u,10,scale,46)
  R:grip('xr_grip',x,y,w,h,47,function(_,e)
    if e.kind=='mouse_enter' then hovered=true elseif e.kind=='mouse_leave' then hovered=false
    elseif e.kind=='click' and (not e.button or e.button=='left') then M.open() end
  end,'Recent invitation; native Party menu handles the actual response')
  if alpha then
    R:text('xr_banner',X.short(banner.text,math.max(10,math.floor(s.width/(8*u)))),s.width/2,s.height*0.52,13,scale,46,
      {245,238,208,alpha},'center')
  end
  R:finish()
  last_presentation=R:ready() and key or nil
end
return M
]],
}
