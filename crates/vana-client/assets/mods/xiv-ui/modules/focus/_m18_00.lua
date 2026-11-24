-- M18 bundled sources; generated from stage sources. Do not edit.
return {
["src.config_schema"]=[[
-- Generated whitelist from owning mod settings + explicit native layout fields.
return {
  {key="on",type="bool",label="XIV Focus and Last Target",help="",default=true},
  {key="width",type="int",label="Bar Width",help="",default=300,min=160,max=600,step=20},
  {key="scale",type="int",min=50,max=200,step=10,default=100,label="Own scale (%)",help="Owner-native geometry; not a renderer/window stacking workaround."},
  {key="offset_x",type="int",min=-1200,max=1200,step=4,default=0,label="Focus X offset",help="Owner-native geometry; not a renderer/window stacking workaround."},
  {key="offset_y",type="int",min=-800,max=800,step=4,default=0,label="Focus Y offset",help="Owner-native geometry; not a renderer/window stacking workaround."},
  {key="last_x",type="int",min=-1200,max=1200,step=4,default=0,label="Last-target X offset",help="Owner-native geometry; not a renderer/window stacking workaround."},
  {key="last_y",type="int",min=-800,max=800,step=4,default=0,label="Last-target Y offset",help="Owner-native geometry; not a renderer/window stacking workaround."},
}
]],
["src.hud_config"]=[[
local factory = require("src.hud_config_factory")
local ALIAS = "focus"
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
["src.target_palette"]=[[
-- The FFXIV-style reference target palette, shared verbatim with Focus/Last XIV.
-- Colour is based on target type, not remaining HP.
local P = {
  enemy = { track = { 80, 15, 15, 255 }, fill = { 255, 186, 183, 255 }, border = { 255, 140, 140, 255 }, text = { 255, 186, 183, 255 } },
  player = { track = { 8, 45, 82, 255 }, fill = { 226, 255, 255, 255 }, border = { 80, 180, 250, 255 }, text = { 226, 255, 255, 255 } },
  npc = { track = { 70, 52, 10, 255 }, fill = { 255, 238, 170, 255 }, border = { 250, 208, 90, 255 }, text = { 255, 238, 170, 255 } },
  object = { track = { 42, 42, 46, 255 }, fill = { 214, 214, 220, 255 }, border = { 172, 172, 180, 255 }, text = { 214, 214, 220, 255 } },
}
return function(t)
  if t.kind == "player" or t.in_party or t.in_alliance or t.trust or t.pet then return P.player end
  if t.kind == "mob" then return P.enemy end
  if t.gauge == false or t.walks == false then return P.object end
  return P.npc
end
]],
}
