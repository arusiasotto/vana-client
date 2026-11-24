-- Submodule settings: layout keys are prefix_field (target_width). Visibility uses
-- mod_<name> toggles via settings.get("on") inside each panel's Lua.
local suite_settings = settings

local mod_toggle = {
  target = "mod_target",
  focus = "mod_focus",
  cast = "mod_cast",
  player = "mod_player",
  buff = "mod_buff",
  exp = "mod_exp",
  party = "mod_party",
  notify = "mod_notify",
}

local function proxy(prefix)
  local p = {}
  function p.get(key)
    if suite_settings.get("on") == false and key == "on" then return false end
    if key == "on" then
      local toggle = mod_toggle[prefix]
      if toggle then return suite_settings.get(toggle) ~= false end
      return false
    end
    return suite_settings.get(prefix .. "_" .. key)
  end
  return p
end

return { proxy = proxy }