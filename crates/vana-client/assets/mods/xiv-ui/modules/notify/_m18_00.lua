-- M18 bundled sources; generated from stage sources. Do not edit.
return {
["src.config_schema"]=[=[
-- Generated whitelist from owning mod settings + explicit native layout fields.
return {
  {key="on",type="bool",label="XIV Notify",help="Shows a short fading toast when you loot an item.",default=true},
  {key="seconds",type="int",label="Toast Seconds",help="",default=3,min=1,max=10,step=1},
  {key="scale",type="int",label="Notification Scale",help="",default=100,min=50,max=200,step=10},
  {key="offset_x",type="int",label="Notification Horizontal Offset",help="",default=0,min=-600,max=600,step=10},
  {key="offset_y",type="int",label="Notification Vertical Offset",help="",default=0,min=-300,max=600,step=10},
  {key="party_notices",type="bool",label="Observed Party Join/Leave Notices",help="",default=false},
  {key="invite_reminders",type="bool",label="Recent Invite Reminder",help="Observed party/alliance invites. Actual pending state and responses stay in the native Party menu. Opening that menu from the reminder needs actions; no auto-accept.",default=true},
  {key="request_offset_x",type="int",label="Invite Reminder Horizontal Offset",help="",default=0,min=-800,max=800,step=10},
  {key="request_offset_y",type="int",label="Invite Reminder Vertical Offset",help="",default=0,min=-500,max=500,step=10},
}
]=],
["src.hud_config"]=[=[
-- Owner-local layout/settings transactions. No cross-mod userdata or config.json.
local M={version=1};local owner
local function copy(v)
  if type(v)~='table' then return v end
  local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t
end
local function same(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end;return true
end
function M.active()return owner and owner.session~=nil or false end
function M.read(key,base)if owner then return owner.get(key) end;return base.get(key) end
function M.new(base,schema,hooks)
  assert(not owner,'Only one config adapter per owning VM')
  local A={schema=schema,hooks=hooks or {},revision=0,serial=0};owner=A
  local bykey={};for _,f in ipairs(schema) do bykey[f.key]=f end
  local function valid(key,value)
    local f=bykey[key];if not f then return false end
    if f.type=='bool' then return type(value)=='boolean' end
    return type(value)=='number' and value==value and value%1==0 and value>=f.min and value<=f.max
  end
  local function saved()
    local bucket=storage.account.xiv_ui_notify_v1
    return type(bucket)=='table' and type(bucket.values)=='table' and bucket.values or {}
  end
  local function native_value(key)
    local f=bykey[key]
    local v=A.hooks.base and A.hooks.base(key)
    if v==nil then v=base.get(key) end
    if v==nil and f then v=f.default end
    return v
  end
  local function bases()
    local result={};for _,f in ipairs(schema) do result[f.key]=native_value(f.key) end;return result
  end
  function A.get(key)
    if not bykey[key] then return base.get(key) end
    if key=='on' and A.session and A.session.preview then return true end
    local values=A.session and A.session.draft or saved()
    if valid(key,values[key]) then return values[key] end
    return native_value(key) -- one native accessor, not a full-schema scan per HUD field.
  end
  A.settings={get=A.get}
  function A.info()
    local values={};local native=bases();local draft=A.session and A.session.draft or saved()
    for _,f in ipairs(schema) do
      if valid(f.key,draft[f.key]) then values[f.key]=draft[f.key] else values[f.key]=native[f.key] end
    end
    return {version=1,revision=A.revision,fields=copy(schema),values=values,
      defaults=native,preview_supported=A.hooks.preview~=nil,preview=A.session and A.session.preview or false,editing=A.session~=nil}
  end
  function A.cancel(token)
    local s=A.session
    if not s or s.token~=token then return {ok=false,reason='Expired/stale editor'} end
    A.session=nil
    if A.hooks.restore then A.hooks.restore(copy(s.state)) end
    return {ok=true}
  end
  function A.begin()
    if A.session then return {ok=false,reason='Owner already has an editor'} end
    if A.hooks.busy and A.hooks.busy() then return {ok=false,reason='Close this component editor first'} end
    A.serial=A.serial+1
    local token=tostring(A.serial)..':'..tostring(A.revision)
    A.session={token=token,draft=copy(saved()),before=copy(saved()),bases=bases(),
      raw=copy(storage.account.xiv_ui_notify_v1),state=A.hooks.capture and A.hooks.capture() or {},at=clock(),preview=false}
    return {ok=true,token=token,info=A.info()}
  end
  function A.check(token)
    local s=A.session
    if not s or s.token~=token then return {ok=false,reason='Expired/stale editor'} end
    if not same(s.raw,storage.account.xiv_ui_notify_v1) or not same(s.bases,bases()) then return {ok=false,reason='Owner settings changed; cancel/reopen, preserving external changes'} end
    return {ok=true}
  end
  function A.set(token,key,value)
    if not A.session or A.session.token~=token then return {ok=false,reason='Expired/stale editor'} end
    if not valid(key,value) then return {ok=false,reason='Unknown key or out-of-range value'} end
    A.session.draft[key]=value;A.session.at=clock();return {ok=true,info=A.info()}
  end
  function A.preview(token,on)
    if not A.session or A.session.token~=token then return {ok=false,reason='Expired/stale editor'} end
    if type(on)~='boolean' or not A.hooks.preview then return {ok=false,reason='Safe sample not supported'} end
    A.session.preview=on;A.session.at=clock()
    if on then A.hooks.preview(true) elseif A.hooks.restore then A.hooks.restore(copy(A.session.state)) end
    return {ok=true}
  end
  function A.defaults(token)
    if not A.session or A.session.token~=token then return {ok=false,reason='Expired/stale editor'} end
    for key in pairs(bykey) do A.session.draft[key]=nil end
    return {ok=true,info=A.info()}
  end
  function A.commit(token)
    local result=A.check(token);if not result.ok then return result end
    local s=A.session
    if storage.account.xiv_ui_notify_v1~=nil and type(storage.account.xiv_ui_notify_v1)~='table' then return {ok=false,reason='Unrecognised owner config; preserving it'} end
    if type(storage.account.xiv_ui_notify_v1)=='table' and storage.account.xiv_ui_notify_v1.version~=nil and storage.account.xiv_ui_notify_v1.version~=1 then
      return {ok=false,reason='Unrecognised owner config version; preserving it'}
    end
    local bucket=copy(storage.account.xiv_ui_notify_v1 or {});bucket.version=1;bucket.values=copy(s.draft)
    local old=copy(storage.account.xiv_ui_notify_v1);storage.account.xiv_ui_notify_v1=bucket
    local ok=pcall(storage.save)
    if not ok then storage.account.xiv_ui_notify_v1=old;return {ok=false,reason='Owner save failed; draft retained'} end
    A.revision=A.revision+1
    A.rollback={revision=A.revision,before=old,after=copy(bucket)}
    A.cancel(token);return {ok=true,receipt={revision=A.revision}}
  end
  function A.undo(receipt)
    local rollback=A.rollback
    if type(receipt)~='table' or not rollback or receipt.revision~=A.revision or rollback.revision~=receipt.revision or not same(storage.account.xiv_ui_notify_v1,rollback.after) then
      return {ok=false,reason='Rollback conflict; preserving newer owner edit'}
    end
    local current=copy(storage.account.xiv_ui_notify_v1);storage.account.xiv_ui_notify_v1=copy(rollback.before)
    if not pcall(storage.save) then storage.account.xiv_ui_notify_v1=current;return {ok=false,reason='Rollback save failed'} end
    A.revision=A.revision+1;A.rollback=nil;return {ok=true}
  end
  mods.provide('xiv_config',function(op,...)
    if op=='info' then return A.info() end
    if op=='renew' then local token=...;if A.session and A.session.token==token then A.session.at=clock();return {ok=true} end;return {ok=false} end
    if op=='begin' or op=='set' or op=='preview' or op=='check' or op=='commit' or op=='cancel' or op=='defaults' or op=='undo' then return A[op](...) end
    return {ok=false,reason='Unsupported config operation'}
  end)
  timer.every(0.25,function()if A.session and clock()-A.session.at>2 then A.cancel(A.session.token) end end)
  for _,event in ipairs({'zone_change','logout','unload'}) do events.on(event,function()if A.session then A.cancel(A.session.token) end end) end
  return A
end
return M
]=],
["src.inventory"]=[=[
-- Pure inventory delta model. Gains are observations, not attributed loot.
local M={};local Tracker={};Tracker.__index=Tracker
local function integer(v,lo,hi) return type(v)=='number' and v%1==0 and v>=lo and v<=hi end
local function item(id) return integer(id,1,65534) end
local function quantity(n) return integer(n,0,4294967295) and n or 0 end
function M.new()return setmetatable({slots={},pending={},ready=false,dropped=0},Tracker) end
function Tracker:seed(rows)
  self.slots,self.pending={},{}
  for _,r in ipairs(rows or {}) do
    if integer(r.bag,0,17) and integer(r.slot,1,255) and item(r.id) then
      self.slots[r.bag..':'..r.slot]={id=r.id,count=quantity(r.count)}
    end
  end
  self.ready=true
end
function Tracker:delta(id,n,now)
  if not self.ready or not item(id) or n==0 then return end
  local entry=self.pending[id]
  if entry and entry.count<0 and now-entry.at>=3 then self.pending[id]=nil;entry=nil end
  if not entry then
    local count,oldest,oldest_at=0,nil,math.huge
    for key,e in pairs(self.pending) do count=count+1;if e.at<oldest_at then oldest,oldest_at=key,e.at end end
    if count>=128 then self.pending[oldest]=nil;self.dropped=self.dropped+1 end
    entry={count=0,at=now};self.pending[id]=entry
  end
  entry.count,entry.at=entry.count+n,now
  if entry.count==0 then self.pending[id]=nil end
end
function Tracker:set(bag,slot,id,n,now,previous)
  if not integer(bag,0,17) or not integer(slot,1,255) then return end
  local key=bag..':'..slot;local old=self.slots[key]
  if not old and item(id) and previous~=nil then old={id=id,count=quantity(previous)} end
  old=old or {id=0,count=0};n=quantity(n)
  if not item(id) or n==0 then id,n=0,0 end
  if old.id==id then self:delta(id,n-old.count,now)
  else self:delta(old.id,-old.count,now);self:delta(id,n,now) end
  self.slots[key]={id=id,count=n}
end
function Tracker:remove(bag,slot,id,n,now)
  if not integer(bag,0,17) or not integer(slot,1,255) then return end
  local key=bag..':'..slot;local old=self.slots[key]
  if old and old.id==id then self:set(bag,slot,0,0,now)
  elseif not old then
    -- Native removal includes the prior whole stack. An unseen bag's move
    -- can still offset a destination gain. Tombstone prevents duplicate loss.
    self:delta(id,-quantity(n),now);self.slots[key]={id=0,count=0}
  end
end
function Tracker:flush(now)
  local gains={}
  for id,e in pairs(self.pending) do
    local wait=e.count>0 and 1 or 3
    if now-e.at>=wait then
      if e.count>0 then gains[#gains+1]={id=id,count=e.count,source='Settled inventory increase; source not attributed'} end
      self.pending[id]=nil
    end
  end
  table.sort(gains,function(a,b)return a.id<b.id end)
  return gains
end
return M
]=]
}
