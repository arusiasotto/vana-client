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

local MODULE_BUCKETS = {
  "xiv_ui_target_v1", "xiv_ui_focus_v1", "xiv_ui_cast_v1", "xiv_ui_player_v1",
  "xiv_ui_exp_v1", "xiv_ui_party_v1", "xiv_ui_notify_v1",
}

local function strip_persisted_on()
  local dirty = false
  for _, key in ipairs(MODULE_BUCKETS) do
    local bucket = storage.account[key]
    if type(bucket) == "table" and type(bucket.values) == "table" and bucket.values.on ~= nil then
      bucket.values.on = nil
      dirty = true
    end
  end
  if dirty then pcall(storage.save) end
end

function M.run()
  strip_persisted_on()
  copy_legacy_values("xiv_ui_target_v1", {
    "on", "width", "scale", "status_count", "place_x", "place_y",
  })
  copy_legacy_values("xiv_ui_focus_v1", {
    "on", "width", "scale", "offset_x", "offset_y", "last_x", "last_y",
    "show_focus", "show_last",
  })
  copy_legacy_values("xiv_ui_cast_v1", {
    "on", "width", "offset_x", "offset_y", "cast", "swing", "ranged", "swing_text",
  })
  copy_legacy_values("xiv_ui_player_v1", {
    "on", "scale", "offset_x", "offset_y", "compact", "avoid_cast",
  })
  copy_legacy_values("xiv_ui_exp_v1", {
    "on", "mode", "scale", "offset_x", "offset_y", "dark_thin", "stats_text",
    "attach_vitals", "attach_below",
  })
  copy_legacy_values("xiv_ui_party_v1", {
    "on", "offset_x", "offset_y", "scale", "buff_count", "range", "pets", "hide_solo",
    "hide_cutscene", "align_bottom", "single_alliance", "range_numbers", "filter_whitelist",
  })
  copy_legacy_values("xiv_ui_notify_v1", {
    "on", "seconds", "scale", "offset_x", "offset_y", "party_notices", "invite_reminders",
    "request_offset_x", "request_offset_y",
  })
end

return M