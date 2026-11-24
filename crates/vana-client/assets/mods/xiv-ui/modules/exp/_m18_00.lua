-- M18 bundled sources; generated from stage sources. Do not edit.
return {
["src.config_schema"]=[[
-- Generated whitelist from owning mod settings + explicit native layout fields.
return {
  {key="on",type="bool",label="XIV Points Strip",help="",default=true},
  {key="mode",type="int",label="Display Mode: 1 Auto, 2 EXP, 3 Limit, 4 Capacity",help="Display only. Auto uses level/available data; the game's allocation switch is not exposed.",default=1,min=1,max=4,step=1},
  {key="scale",type="int",label="XP Strip Scale",help="",default=100,min=50,max=200,step=10},
  {key="offset_x",type="int",label="Horizontal Offset",help="",default=0,min=-800,max=800,step=10},
  {key="offset_y",type="int",label="Vertical Offset From Top",help="",default=6,min=0,max=800,step=1},
  {key="dark_thin",type="bool",label="Thin Dark/Glow Artwork",help="",default=true},
  {key="stats_text",type="bool",label="Observed Rate / Estimated Time Text",help="",default=false},
  {key="attach_vitals",type="bool",label="Attach To Player Bars",help="On: XP strip follows player bars; drag player to move both. Off: drag the XP strip.",default=false},
  {key="attach_below",type="bool",label="Attach Below Player Bars (off = above)",help="Only when Attach To Player Bars is on. Default below vitals.",default=true},
}
]],
["src.hud_config"]=[[
local factory = require("src.hud_config_factory")
local ALIAS = "exp"
local M = {}
function M.new(base, schema, hooks) return factory.new(base, schema, hooks, ALIAS) end
function M.active() return factory.active(ALIAS) end
function M.read(key, base) return factory.read(ALIAS, key, base) end
return M
]],
["src.hud_drag"]=[[
-- Owner-local drag transactions. No frame timer, global state or direct saves.
local M = {}
function M.new(cfg, xkey, ykey, units, allow, ysign)
  local drag
  return function(e)
    if e.kind == "drag_start" then
      if e.button and e.button ~= "left" then return false end
      if allow and not allow() then return true end
      if cfg.hooks.capture and cfg.hooks.capture().preview then return true end
      local b = cfg.begin()
      if not b.ok then return true end
      local fields = {}
      for _, f in ipairs(b.info.fields) do fields[f.key] = f end
      if not fields[xkey] or not fields[ykey] then cfg.cancel(b.token); return true end
      drag = { token = b.token, x = b.info.values[xkey], y = b.info.values[ykey], fields = fields, u = units() }
      return true
    elseif e.kind == "drag" or e.kind == "drag_end" then
      if not drag then return false end
      local function value(key, start, delta)
        local f = drag.fields[key]
        local n = math.floor(start + (delta or 0) / math.max(.01, drag.u) + .5)
        return math.max(f.min, math.min(f.max, n))
      end
      local x = cfg.set(drag.token, xkey, value(xkey, drag.x, e.dx))
      local y = cfg.set(drag.token, ykey, value(ykey, drag.y, (e.dy or 0) * (ysign or 1)))
      if not x.ok or not y.ok then cfg.cancel(drag.token); drag = nil; return true end
      if e.kind == "drag_end" then
        if e.window or e.over then cfg.cancel(drag.token)
        else
          local r = cfg.commit(drag.token)
          if not r.ok then cfg.cancel(drag.token); chat.add("XIV HUD: drag not saved; " .. (r.reason or "conflict")) end
        end
        drag = nil
      end
      return true
    end
    return false
  end
end
return M
]],
["src.points"]=[[
-- Read-only counter model adapted from native XP Tracker 1.0.2.
-- Same EXP/merit/JP rollover equations; monotonic time and per-job reset.
local M={};local Tracker={};Tracker.__index=Tracker
local function valid(n)return type(n)=='number' and n==n and n>=0 and n<math.huge end
function M.new()local self=setmetatable({},Tracker);self:reset();return self end
function Tracker:reset(reading)
  self.last=nil
  if reading then self.last={};for key,value in pairs(reading) do self.last[key]=value end end
  self.gains={exp={total=0},limit={total=0},capacity={total=0}}
end
function Tracker:add(kind,n,now)
  if not valid(n) or n<=0 then return end
  local gain=self.gains[kind];gain.since=gain.since or now;gain.total=gain.total+n
end
function Tracker:sample(b,now)
  if type(b)~='table' or not valid(b.job) then return end
  local a=self.last
  if a and a.job~=b.job then self:reset();a=nil end
  if a then
    if valid(a.exp) and valid(b.exp) and valid(a.level) and valid(b.level) then
      if b.level==a.level then self:add('exp',b.exp-a.exp,now)
      elseif b.level==a.level+1 and valid(a.exp_next) then self:add('exp',a.exp_next-a.exp+b.exp,now)
      elseif b.level>a.level+1 then self.gains.exp.incomplete=true end
    end
    if valid(a.limit) and valid(b.limit) and valid(a.merits) and valid(b.merits) then
      self:add('limit',(b.merits-a.merits)*10000+b.limit-a.limit,now)
      if b.merits<a.merits then self.gains.limit.incomplete=true end
    end
    if valid(a.capacity) and valid(b.capacity) and valid(a.jp) and valid(b.jp) and
        valid(a.jp_spent) and valid(b.jp_spent) then
      if b.jp_spent>=a.jp_spent then
        self:add('capacity',((b.jp+b.jp_spent)-(a.jp+a.jp_spent))*30000+b.capacity-a.capacity,now)
      else self.gains.capacity.incomplete=true end
    end
  end
  local saved={};for key,value in pairs(b) do saved[key]=value end;self.last=saved
end
function M.select(r,choice)
  if type(r)~='table' then return nil end
  if choice=='auto' or choice==nil then
    if (r.level or 0)>=99 and valid(r.capacity) and valid(r.jp) then choice='capacity'
    elseif (r.level or 0)>=75 and valid(r.limit) and valid(r.merits) then choice='limit'
    else choice='exp' end
  end
  if choice=='exp' and valid(r.exp) and valid(r.exp_next) and r.exp_next>0 then
    return {kind='exp',label='EXP',current=r.exp,total=r.exp_next}
  elseif choice=='limit' and (r.level or 0)>=75 and valid(r.limit) and valid(r.merits) then
    return {kind='limit',label='LIMIT',current=r.limit,total=10000,merits=r.merits,merit_max=r.merit_max}
  elseif choice=='capacity' and (r.level or 0)>=99 and valid(r.capacity) and valid(r.jp) then
    return {kind='capacity',label='CAPACITY',current=r.capacity,total=30000,points=r.jp,spent=r.jp_spent}
  end
  return nil
end
function Tracker:detail(row,now)
  if not row then return nil end
  local result={};for key,value in pairs(row) do result[key]=value end
  local gain=self.gains[row.kind];result.observed_gain=gain.total;result.incomplete=gain.incomplete or false
  local elapsed=gain.since and now-gain.since or 0
  if elapsed>=60 then
    result.rate=gain.total*3600/elapsed
    if result.rate>0 and not result.incomplete then result.eta=math.max(0,row.total-row.current)/result.rate*3600 end
  end
  return result
end
return M
]],
}
