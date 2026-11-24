-- Internal suite bus (was mods.call between xiv-* ids).
local M = {
  registry = {},
  ---@type table<string, function> per-panel hud_config API (op, ...)
  config = {},
  aliases = {
    ["xiv-target-bar"] = "target",
    ["xiv-focus-target"] = "focus",
    ["xiv-party-list"] = "party",
    ["xiv-player-bars"] = "player",
    ["xiv-cast-bar"] = "cast",
    ["xiv-buff-bar"] = "buff",
    ["xiv-exp-bar"] = "exp",
    ["xiv-notify"] = "notify",
  },
}

function M.call(mod, method, ...)
  local alias = M.aliases[mod] or mod
  local tab = M.registry[alias]
  local fn = tab and tab[method]
  if fn then return fn(...) end
  if mods and mods.call then
    local ok, value = pcall(mods.call, mod, method, ...)
    if ok then return value end
  end
  return nil
end

function M.register(alias, name, fn)
  M.registry[alias] = M.registry[alias] or {}
  M.registry[alias][name] = fn
end

function M.register_config(alias, api)
  M.config[alias] = api
end

function M.get_config(alias)
  return M.config[alias]
end

function M.config_dispatch(op, panel, ...)
  if type(panel) ~= "string" or panel == "" then
    return { ok = false, reason = "panel id required (target, focus, cast, player, buff, exp, party, notify)" }
  end
  local fn = M.config[panel]
  if not fn then
    return { ok = false, reason = "panel not loaded: " .. panel }
  end
  return fn(op, ...)
end

function M.wrap_provide(alias)
  local base = mods.provide
  mods.provide = function(name, fn)
    M.register(alias, name, fn)
    if name == "xiv_config" then
      M.register_config(alias, fn)
      return
    end
    -- Host names are namespaced so target/focus do not overwrite each other's provides.
    return base("xiv_" .. alias .. "_" .. name, fn)
  end
  return function()
    mods.provide = base
  end
end

function M.patch_xiv(module_key, cache, module_req)
  local X = cache[module_key]
  if type(X) ~= "table" then return end
  if type(X.call) == "function" then X.call = M.call end
  if module_req then X._module_require = module_req end
end

return M