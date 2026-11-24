-- M18 bundled sources; generated from stage sources. Do not edit.
return {
["src.config_schema"]=[[
-- Generated whitelist from owning mod settings + explicit native layout fields.
return {
  {key="offset_x",type="int",min=-1200,max=1200,step=4,default=0,label="Horizontal HUD offset",help="Native gauge origin, no window stacking workaround."},
  {key="on",type="bool",label="XIV Cast Bar",help="Shows your casting progress as a gold-rimmed bar.",default=true},
  {key="width",type="int",label="Width",help="Width of the cast track in UI units. 180 matches the approved mockup.",default=180,min=100,max=500,step=10},
  {key="offset_y",type="int",label="Vertical offset",help="Moves the bar up or down from its default position.",default=0,min=-400,max=400,step=4},
  {key="cast",type="bool",label="Show Casting",help="",default=true},
  {key="swing",type="bool",label="Show Estimated Melee Timing",help="",default=true},
  {key="ranged",type="bool",label="Show Estimated Ranged Timing",help="",default=true},
  {key="swing_text",type="bool",label="Show Interval/Hit Labels",help="",default=false},
}
]],
["src.hud_config"]=[[
local factory = require("src.hud_config_factory")
local ALIAS = "cast"
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
}
