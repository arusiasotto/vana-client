-- M18 bundled sources; generated from stage sources. Do not edit.
return {
["src.config_schema"]=[[
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
]],
["src.hud_config"]=[[
local factory = require("src.hud_config_factory")
local ALIAS = "notify"
local M = {}
function M.new(base, schema, hooks) return factory.new(base, schema, hooks, ALIAS) end
function M.active() return factory.active(ALIAS) end
function M.read(key, base) return factory.read(ALIAS, key, base) end
return M
]],
["src.inventory"]=[[
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
]],
}
