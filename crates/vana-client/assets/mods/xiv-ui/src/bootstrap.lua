-- One M18 namespace per submodule: load in small steps (chunks/imports/entry).
local M = {}

local function read_chunk(mod_dir, label)
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

local function install_chunk(state, t, label)
  if type(t) ~= "table" then error("M18 chunk " .. label .. ": not a table", 0) end
  local prefix = state.prefix
  for k, v in pairs(t) do
    if type(k) ~= "string" or type(v) ~= "string" then
      error("M18 chunk " .. label .. ": bad entry", 0)
    end
    state.module_sources[prefix .. "." .. k] = v
  end
end

local function make_req(state)
  local native_require = state.native_require
  local function req(name)
    local key = state.prefix .. "." .. name
    if state.module_cache[key] ~= nil then return state.module_cache[key] end
    local source = state.module_sources[key]
    if not source then return native_require(name) end
    if state.module_loading[key] then error("M18 require cycle: " .. key, 0) end
    state.module_loading[key] = true
    local f, err = load(source, "@" .. name:gsub("%.", "/") .. ".lua", "t", _ENV)
    if not f then
      state.module_loading[key] = nil
      error("M18 compile " .. key .. ": " .. tostring(err), 0)
    end
    local ok, value = pcall(f, name)
    state.module_loading[key] = nil
    if not ok then error("M18 module " .. key .. ": " .. tostring(value), 0) end
    if value ~= nil then state.module_cache[key] = value end
    return value
  end
  return req
end

function M.begin(bridge, assets, opts)
  local prefix = opts.prefix
  local mod_dir = opts.dir
  local manifest = opts.manifest
  local asset_root = mod_dir .. "/"
  assets.register_root(asset_root)
  return {
    bridge = bridge,
    assets = assets,
    opts = opts,
    prefix = prefix,
    mod_dir = mod_dir,
    manifest = manifest,
    asset_root = asset_root,
    module_sources = {},
    module_cache = {},
    module_loading = {},
    native_require = require,
    phase = "stagger",
    chunk_i = 1,
    source_i = 1,
    import_i = 1,
    req = nil,
    unwrap = nil,
    saved_req = nil,
    saved_settings = nil,
    done = false,
  }
end

function M.step(state)
  if state.done then return true end
  local sleep_fn = sleep
  local manifest = state.manifest
  local mod_dir = state.mod_dir
  local prefix = state.prefix

  if state.phase == "stagger" then
    if sleep_fn and manifest.stagger and not rawget(_ENV, "__xiv_fixture") then
      local h, s = 0, manifest.stagger
      for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 9973 end
      local delay = (h % 24) * 0.10
      if delay > 0 then sleep_fn(delay) end
    end
    state.phase = manifest.source_files and "sources" or "chunks"
    return false
  end

  if state.phase == "chunks" then
    local labels = manifest.chunks or {}
    if state.chunk_i > #labels then
      state.phase = "imports_init"
      return false
    end
    local label = labels[state.chunk_i]
    install_chunk(state, read_chunk(mod_dir, label), label)
    state.chunk_i = state.chunk_i + 1
    if sleep_fn then sleep_fn(0) end
    return false
  end

  if state.phase == "sources" then
    local names = manifest.imports or {}
    if state.source_i > #names then
      state.phase = "imports_init"
      return false
    end
    local name = names[state.source_i]
    local rel = mod_dir .. "/" .. name:gsub("%.", "/") .. ".lua"
    local text = fs.read(rel)
    if type(text) ~= "string" or text == "" then
      error("XIV-UI missing source " .. rel, 0)
    end
    state.module_sources[prefix .. "." .. name] = text
    state.source_i = state.source_i + 1
    if sleep_fn then sleep_fn(0) end
    return false
  end

  if state.phase == "imports_init" then
    state.req = make_req(state)
    state.saved_req, state.saved_settings = require, settings
    _ENV.require = state.req
    state.unwrap = state.bridge.wrap_provide(prefix)
    state.phase = "imports"
    return false
  end

  if state.phase == "imports" then
    local names = manifest.imports or {}
    if state.import_i > #names then
      state.phase = "patch"
      return false
    end
    local ok, err = pcall(state.req, names[state.import_i])
    if not ok then
      _ENV.require = state.saved_req
      _ENV.settings = state.saved_settings
      if state.unwrap then state.unwrap(); state.unwrap = nil end
      error(err, 0)
    end
    state.import_i = state.import_i + 1
    if sleep_fn then sleep_fn(0) end
    return false
  end

  if state.phase == "patch" then
    local xiv_key = prefix .. ".src.xiv"
    local X = state.module_cache[xiv_key]
    if type(X) == "table" then
      state.bridge.patch_xiv(xiv_key, state.module_cache)
      state.assets.patch_xiv_module(X, state.asset_root)
    end
    if sleep_fn then sleep_fn(0) end
    state.phase = "entry"
    return false
  end

  if state.phase == "entry" then
    _ENV.settings = state.opts.settings
    if sleep_fn then sleep_fn(0) end
    local ok, run_err = pcall(function()
      local text = fs.read(mod_dir .. "/entry.lua")
      local body, err = load(text, "@" .. mod_dir .. "/entry.lua", "t", _ENV)
      if not body then error(err, 0) end
      body()
    end)
    _ENV.require = state.saved_req
    _ENV.settings = state.saved_settings
    if state.unwrap then state.unwrap(); state.unwrap = nil end
    if not ok then error(run_err, 0) end
    state.done = true
    return true
  end

  error("XIV-UI bootstrap: unknown phase " .. tostring(state.phase), 0)
end

function M.run(bridge, assets, opts)
  local st = M.begin(bridge, assets, opts)
  while not M.step(st) do end
end

return M