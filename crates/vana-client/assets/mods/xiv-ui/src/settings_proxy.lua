-- Maps module settings keys to xiv-ui/mod.toml (target_on, focus_width, …).
local function proxy(prefix)
  local p = {}
  function p.get(key)
    if settings.get("on") == false and key == "on" then return false end
    return settings.get(prefix .. "_" .. key)
  end
  return p
end

return { proxy = proxy }