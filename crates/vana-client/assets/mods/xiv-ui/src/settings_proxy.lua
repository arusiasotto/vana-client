-- Maps module settings keys to xiv-ui/mod.toml (target_on, focus_width, …).
-- Capture the suite settings table at load: bootstrap replaces _ENV.settings with
-- the proxy while entry.lua runs, so p.get must not call through that global.
local suite_settings = settings

local function proxy(prefix)
  local p = {}
  function p.get(key)
    if suite_settings.get("on") == false and key == "on" then return false end
    return suite_settings.get(prefix .. "_" .. key)
  end
  return p
end

return { proxy = proxy }