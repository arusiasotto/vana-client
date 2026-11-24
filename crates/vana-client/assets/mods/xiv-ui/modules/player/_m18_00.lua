-- M18 bundled sources; generated from stage sources. Do not edit.
return {
["src.config_schema"]=[[
-- Generated whitelist from owning mod settings + explicit native layout fields.
return {
  {key="on",type="bool",label="XIV Player Bars",help="Shows FFXIV-style HP, MP and TP bars near the bottom of the screen.",default=false},
  {key="scale",type="int",label="Bar Scale",help="Scales the whole bar group. 100 matches the approved mockup.",default=100,min=50,max=200,step=10},
  {key="offset_y",type="int",label="Height",help="Moves the bars up (negative) or down from their place over the hotbars' area.",default=0,min=-400,max=400,step=10},
  {key="offset_x",type="int",label="Horizontal Offset",help="",default=0,min=-800,max=800,step=10},
  {key="compact",type="bool",label="Compact Artwork",help="",default=false},
  {key="avoid_cast",type="bool",label="Avoid Cast/Attack Gauge Space",help="Uses the cast mod's actual reserved layout when available; no guessed behind-window geometry.",default=true},
}
]],
["src.hud_config"]=[[
local factory = require("src.hud_config_factory")
local ALIAS = "player"
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
["src.vitals"]=[[
-- Pure real-value normalization. TP display fills at XI's 1000 readiness point.
local M={}
local function number(v)return type(v)=='number' and v==v and v>=0 and v<math.huge and v or nil end
function M.read(p)
  if type(p)~='table' then return nil end
  local hp,max=number(p.hp),number(p.hp_max)
  if hp==nil or max==nil or max<=0 then return nil end
  local mp,mpmax,tp=number(p.mp),number(p.mp_max),number(p.tp)
  local function ratio(cur,total)return cur and total and total>0 and math.min(1,cur/total) or 0 end
  return {hp={current=hp,total=max,fraction=ratio(hp,max)},
    mp={current=mp,total=mpmax,fraction=ratio(mp,mpmax)},
    tp={current=tp,total=3000,fraction=ratio(tp,1000),ready=tp~=nil and tp>=1000},
    mp_less=mpmax==0,job=p.main_job,level=p.main_level,sub_job=p.sub_job,sub_level=p.sub_level}
end
function M.smooth(old,new,dt)
  if new==0 then return 0 end
  if old==nil or math.abs(old-new)<0.002 then return new end
  dt=math.max(0,math.min(0.1,tonumber(dt) or 0.016))
  return old+(new-old)*(1-math.exp(-dt*12))
end
return M
]],
}
