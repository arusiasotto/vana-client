-- One M18 namespace: load a module subtree (modules/<name>/), then run its entry.lua.
return function(bridge, assets, opts)
  local prefix = opts.prefix
  local mod_dir = opts.dir
  local manifest = opts.manifest
  local asset_root = mod_dir .. "/"
  assets.register_root(asset_root)
  local native_require = require
  local module_sources, module_cache, module_loading = {}, {}, {}
  local sleep_fn = sleep

  local function install_chunk(t, label)
    if type(t) ~= "table" then error("M18 chunk " .. label .. ": not a table", 0) end
    for k, v in pairs(t) do
      if type(k) ~= "string" or type(v) ~= "string" then
        error("M18 chunk " .. label .. ": bad entry", 0)
      end
      module_sources[prefix .. "." .. k] = v
    end
  end

  local function read_chunk(label)
    local base = mod_dir .. "/" .. label
    local text = fs and fs.read and fs.read(base)
    if type(text) ~= "string" or text == "" then
      text = fs and fs.read and fs.read(base .. ".lua")
    end
    if type(text) ~= "string" or text == "" then
      error("M18 missing chunk " .. base, 0)
    end
    local f, err = load(text, "@" .. base, "t", _ENV)
    if not f then error("M18 chunk " .. label .. ": " .. tostring(err), 0) end
    local ok, tbl = pcall(f)
    if not ok then error("M18 chunk " .. label .. ": " .. tostring(tbl), 0) end
    return tbl
  end

  if sleep_fn and manifest.stagger and not rawget(_ENV, "__xiv_fixture") then
    local h, s = 0, manifest.stagger
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 9973 end
    local delay = (h % 24) * 0.10
    if delay > 0 then sleep_fn(delay) end
  end

  for _, label in ipairs(manifest.chunks) do
    install_chunk(read_chunk(label), label)
    if sleep_fn then sleep_fn(0) end
  end

  local function req(name)
    local key = prefix .. "." .. name
    if module_cache[key] ~= nil then return module_cache[key] end
    local source = module_sources[key]
    if not source then return native_require(name) end
    if module_loading[key] then error("M18 require cycle: " .. key, 0) end
    module_loading[key] = true
    local f, err = load(source, "@" .. name:gsub("%.", "/") .. ".lua", "t", _ENV)
    if not f then
      module_loading[key] = nil
      error("M18 compile " .. key .. ": " .. tostring(err), 0)
    end
    local ok, value = pcall(f, name)
    module_loading[key] = nil
    if not ok then error("M18 module " .. key .. ": " .. tostring(value), 0) end
    if value ~= nil then module_cache[key] = value end
    return value
  end

  local saved_req, saved_settings = require, settings
  _ENV.require = req

  for i, name in ipairs(manifest.imports) do
    local ok, err = pcall(req, name)
    if not ok then error(err, 0) end
  end

  local X = module_cache[prefix .. ".src.xiv"]
  bridge.patch_xiv(prefix .. ".src.xiv", module_cache)
  assets.patch_xiv_module(X, asset_root)

  if sleep_fn and #manifest.imports > 0 then sleep_fn(0) end

  local unwrap = bridge.wrap_provide(prefix)
  _ENV.settings = opts.settings
  if sleep_fn then sleep_fn(0) end
  local text = fs.read(mod_dir .. "/entry.lua")
  local body, err = load(text, "@" .. mod_dir .. "/entry.lua", "t", _ENV)
  if not body then error(err, 0) end
  local ok, run_err = pcall(body)
  _ENV.require = saved_req
  _ENV.settings = saved_settings
  unwrap()
  if not ok then error(run_err, 0) end
end