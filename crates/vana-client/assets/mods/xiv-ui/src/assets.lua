-- Prefix img/ paths with modules/<name>/ for HUD and renderer code.
local M = {}

local function copy_spec(spec)
  local c = {}
  for k, v in pairs(spec) do c[k] = v end
  return c
end

function M.prefix_path(root, path)
  if type(path) ~= "string" or path:find("^modules/", 1) then return path end
  return root .. path
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
  X.__xiv_ui_asset_root = root
  if type(X.exists) == "function" then
    local old_exists = X.exists
    function X.exists(path)
      return old_exists(M.prefix_path(root, path))
    end
  end
  local R = renderer_proto(X)
  if not R or R.__xiv_ui_asset_put then return end
  R.__xiv_ui_asset_put = true
  local orig_put = R.put
  function R.put(self, kind, id, spec)
    if kind == "image" and type(spec) == "table" and type(spec.path) == "string" then
      spec = copy_spec(spec)
      spec.path = M.prefix_path(root, spec.path)
    end
    return orig_put(self, kind, id, spec)
  end
end

local roots_key = "__xiv_ui_asset_roots"
-- HUD element id prefix -> module asset root (paths relative to xiv-ui/).
local id_roots = {
  tb_ = "modules/target/",
  xtb_ = "modules/target/",
  xft_ = "modules/focus/",
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
  if type(hud_id) == "string" then
    for prefix, root in pairs(id_roots) do
      if hud_id:find("^" .. prefix, 1) then return M.prefix_path(root, path) end
    end
  end
  local roots = rawget(_G, roots_key) or {}
  if fs and fs.exists then
    for i = #roots, 1, -1 do
      local full = roots[i] .. path
      if fs.exists(full) then return full end
    end
  end
  if #roots == 1 then return roots[1] .. path end
  if #roots > 0 then return roots[#roots] .. path end
  return path
end

return M