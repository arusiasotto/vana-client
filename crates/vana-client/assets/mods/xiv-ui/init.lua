-- XIV-UI: load heavy M18 modules across frames (100 ms budget per slice).
local function load_src(path)
  local text = fs.read(path)
  local f, err = load(text, "@" .. path, "t", _ENV)
  if not f then error(err, 0) end
  return f()
end

local bridge = load_src("src/bridge.lua")
local bootstrap = load_src("src/bootstrap.lua")
local settings_proxy = load_src("src/settings_proxy.lua")
local assets = load_src("src/assets.lua")
local migrate = load_src("src/migrate.lua")

pcall(migrate.run)

if not rawget(_G, "__xiv_ui_hud_image_patched") then
  rawset(_G, "__xiv_ui_hud_image_patched", true)
  local old_image = hud.image
  function hud.image(id, spec)
    if type(spec) == "table" and type(spec.path) == "string" then
      local copy = {}
      for k, v in pairs(spec) do copy[k] = v end
      copy.path = assets.resolve_path(copy.path, id)
      spec = copy
    end
    return old_image(id, spec)
  end
end

local function load_manifest(dir)
  local f = load(fs.read(dir .. "/manifest.lua"), "@" .. dir .. "/manifest.lua", "t", _ENV)
  return f()
end

local function suite_on()
  return settings.get("on") ~= false
end

local function run_module(alias, dir, setting_key)
  if not suite_on() then return end
  if settings.get(setting_key) == false then return end
  bootstrap(bridge, assets, {
    prefix = alias,
    dir = dir,
    manifest = load_manifest(dir),
    settings = settings_proxy.proxy(alias),
  })
end

mods.provide("loaded", function() return true end)
mods.provide("suite", function() return bridge.registry end)

local HOST_COMPAT = {
  target = { "layout", "cast", "casts_for", "effects" },
  player = { "layout" },
}

local function publish_host_compat()
  for alias, names in pairs(HOST_COMPAT) do
    local tab = bridge.registry[alias]
    if not tab then goto continue end
    for _, name in ipairs(names) do
      local fn = tab[name]
      if type(fn) == "function" then mods.provide(name, fn) end
    end
    ::continue::
  end
end

local queue = {}
local function enqueue(alias, dir, toggle)
  if suite_on() and settings.get(toggle) ~= false then
    queue[#queue + 1] = { alias, dir, toggle }
  end
end
enqueue("target", "modules/target", "mod_target")
enqueue("focus", "modules/focus", "mod_focus")
enqueue("cast", "modules/cast", "mod_cast")
enqueue("player", "modules/player", "mod_player")
enqueue("buff", "modules/buff", "mod_buff")
enqueue("exp", "modules/exp", "mod_exp")
enqueue("party", "modules/party", "mod_party")
enqueue("notify", "modules/notify", "mod_notify")

local next_ix = 1
local function pump()
  if next_ix > #queue then return end
  local job = queue[next_ix]
  next_ix = next_ix + 1
  run_module(job[1], job[2], job[3])
end

if #queue > 0 then
  local frame_id
  local function frame_hook()
    local ok, err = pcall(pump)
    if not ok then
      if log and log.error then log.error("XIV-UI load: " .. tostring(err)) end
      events.off(frame_id)
      return
    end
    if next_ix > #queue then
      events.off(frame_id)
      publish_host_compat()
    end
  end
  frame_id = events.on("frame", frame_hook)
elseif suite_on() then
  publish_host_compat()
end