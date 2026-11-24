-- One-time import from standalone XIV mods (shared storage.account.xiv_ui_v1 buckets).
local M = {}

local function empty_bucket(key)
  local bucket = storage.account[key]
  return type(bucket) ~= "table" or type(bucket.values) ~= "table" or next(bucket.values) == nil
end

local function copy_legacy_values(into_key, keys)
  if not empty_bucket(into_key) then return end
  local leg = storage.account.xiv_ui_v1
  if type(leg) ~= "table" or type(leg.values) ~= "table" then return end
  local values = {}
  for _, k in ipairs(keys) do
    local v = leg.values[k]
    if v ~= nil then values[k] = v end
  end
  if next(values) == nil then return end
  storage.account[into_key] = { version = 1, values = values }
  pcall(storage.save)
end

function M.run()
  copy_legacy_values("xiv_ui_target_v1", {
    "on", "width", "scale", "status_count", "place_x", "place_y",
  })
  copy_legacy_values("xiv_ui_focus_v1", {
    "on", "width", "scale", "offset_x", "offset_y", "last_x", "last_y",
    "show_focus", "show_last",
  })
end

return M