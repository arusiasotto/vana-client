-- Resolve img/ paths: aliases, suite img/, img/panels/<panel>/, then modules/<panel>/.
local M = {}

local aliases_cache

local function load_aliases()
  if aliases_cache ~= nil then return aliases_cache end
  aliases_cache = {}
  if not fs or not fs.read then return aliases_cache end
  local ok, text = pcall(fs.read, "img/_aliases.lua")
  if not ok or type(text) ~= "string" or text == "" then return aliases_cache end
  local f, err = load(text, "@img/_aliases.lua", "t", _ENV)
  if not f then return aliases_cache end
  local ok2, tab = pcall(f)
  if ok2 and type(tab) == "table" then aliases_cache = tab end
  return aliases_cache
end

local function follow_aliases(path, depth)
  depth = depth or 0
  if depth > 16 or type(path) ~= "string" then return path end
  local aliases = load_aliases()
  local to = aliases[path]
  if type(to) == "string" and to ~= path then
    return follow_aliases(to, depth + 1)
  end
  return path
end

local function copy_spec(spec)
  local c = {}
  for k, v in pairs(spec) do c[k] = v end
  return c
end

function M.panel_alias_from_root(root)
  if type(root) ~= "string" then return nil end
  return root:match("^modules/([^/]+)/$") or root:match("^modules/([^/]+)/")
end

function M.resolve_image_path(path, opts)
  opts = opts or {}
  if type(path) ~= "string" then return path end
  if path:find("^modules/", 1) then return path end
  if path:sub(1, 4) ~= "img/" then
    if opts.root then return opts.root .. path end
    return path
  end
  local rest = path:sub(5)
  if fs and fs.exists and opts.alias and fs.exists("img/panels/" .. opts.alias .. "/" .. rest) then
    return "img/panels/" .. opts.alias .. "/" .. rest
  end
  path = follow_aliases(path)
  if fs and fs.exists and fs.exists(path) then return path end
  if opts.root then return opts.root .. path end
  return path
end

function M.prefix_path(root, path)
  return M.resolve_image_path(path, { root = root, alias = M.panel_alias_from_root(root) })
end

--- Patch one module's bundled src.xiv (R.put + X.exists).
local function renderer_proto(X)
  if type(X) ~= "table" or type(X.renderer) ~= "function" then return nil end
  local sample = X.renderer()
  local mt = sample and getmetatable(sample)
  if type(mt) ~= "table" then return nil end
  if type(mt.put) == "function" then return mt end
  if type(mt.__index) == "table" and type(mt.__index.put) == "function" then return mt.__index end
  return nil
end

function M.patch_xiv_module(X, root)
  if type(X) ~= "table" then return end
  local alias = M.panel_alias_from_root(root)
  X.__xiv_ui_asset_root = root
  X.__xiv_ui_panel_alias = alias
  if type(X.exists) == "function" then
    local old_exists = X.exists
    function X.exists(path)
      local resolved = M.resolve_image_path(path, { root = root, alias = alias })
      if fs and fs.exists and fs.exists(resolved) then return true end
      return old_exists(resolved)
    end
  end
  local R = renderer_proto(X)
  if not R or R.__xiv_ui_asset_put then return end
  R.__xiv_ui_asset_put = true
  local orig_put = R.put
  function R.put(self, kind, id, spec)
    if kind == "image" and type(spec) == "table" and type(spec.path) == "string" then
      spec = copy_spec(spec)
      spec.path = M.resolve_image_path(spec.path, { root = root, alias = alias })
    end
    return orig_put(self, kind, id, spec)
  end
end

local roots_key = "__xiv_ui_asset_roots"
local id_roots = {
  tb_ = "modules/target/",
  xtb_ = "modules/target/",
  xft_ = "modules/focus/",
  xcb_ = "modules/cast/",
  pb_ = "modules/player/",
  xxp_ = "modules/exp/",
  xpl_ = "modules/party/",
}

function M.register_root(root)
  local roots = rawget(_G, roots_key) or {}
  rawset(_G, roots_key, roots)
  for _, r in ipairs(roots) do
    if r == root then return end
  end
  roots[#roots + 1] = root
end

function M.resolve_path(path, hud_id)
  if type(path) ~= "string" or path:find("^modules/", 1) then return path end
  local alias
  if type(hud_id) == "string" then
    if hud_id:find("^bb", 1) then
      alias = "buff"
      local resolved = M.resolve_image_path(path, { root = "modules/buff/", alias = alias })
      if fs and fs.exists and fs.exists(resolved) then return resolved end
      return M.prefix_path("modules/buff/", path)
    end
    for prefix, root in pairs(id_roots) do
      if hud_id:find("^" .. prefix, 1) then
        alias = M.panel_alias_from_root(root)
        local resolved = M.resolve_image_path(path, { root = root, alias = alias })
        if fs and fs.exists and fs.exists(resolved) then return resolved end
        return M.prefix_path(root, path)
      end
    end
  end
  local roots = rawget(_G, roots_key) or {}
  if fs and fs.exists and path:sub(1, 4) == "img/" then
    local resolved = M.resolve_image_path(path, { root = #roots == 1 and roots[1] or nil, alias = nil })
    if fs.exists(resolved) then return resolved end
    for i = #roots, 1, -1 do
      local a = M.panel_alias_from_root(roots[i])
      resolved = M.resolve_image_path(path, { root = roots[i], alias = a })
      if fs.exists(resolved) then return resolved end
    end
  end
  if fs and fs.exists then
    for i = #roots, 1, -1 do
      local full = roots[i] .. path
      if fs.exists(full) then return full end
    end
  end
  if #roots == 1 then return roots[1] .. path end
  if #roots > 0 then return roots[#roots] .. path end
  return follow_aliases(path)
end

return M