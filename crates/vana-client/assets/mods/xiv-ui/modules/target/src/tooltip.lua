-- Shared FFXIV-style tooltip helper.
-- Based on XivUI's lib/tooltip.lua (permission granted by the maintainer),
-- rewritten for vana-client's hud API. Copy into each fork's src/ folder.

local style = require("src.style")

local M = {}
local Tooltip = {}
Tooltip.__index = Tooltip

local C = style.colour
local T = style.tooltip

-- Width and height in UI units (not pixels): hud.text's size is a multiple of
-- the UI's 16-unit line, so measure with that rather than raw pixels.
local function measure(text, size)
  local maxlen, lines = 0, 0
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    lines = lines + 1
    if #line > maxlen then maxlen = #line end
  end
  if lines == 0 then lines = 1 end
  local line_h = 16 * (size / 10)
  return maxlen * line_h * 0.55, lines * line_h
end

local function normalise(text)
  if type(text) == "table" then
    local title = text.title or ""
    local body = text.text or ""
    if title ~= "" and body ~= "" then return title .. "\n" .. body end
    if title ~= "" then return title end
    return body
  end
  return tostring(text or "")
end

function M.new(id, opts)
  opts = opts or {}
  local self = setmetatable({}, Tooltip)
  self.prefix = id .. "_tip_"
  self.size = opts.size or T.size
  self.pad = opts.pad or T.pad
  self.layer = opts.layer or T.layer
  self.icon_size = opts.icon_size or T.icon
  self.gap = opts.gap or T.gap
  self.attached = {}
  self.image_made = false

  hud.rect(self.prefix .. "bg", {
    x = 0, y = 0, w = 1, h = 1, visible = false, layer = self.layer,
    round = style.px(T.radius * 0.5), colour = C.bg,
  })
  hud.text(self.prefix .. "text", {
    x = 0, y = 0, text = "", visible = false, layer = self.layer + 1,
    size = self.size / 10, colour = C.text, font = style.font,
  })
  hud.icon(self.prefix .. "icon", {
    x = 0, y = 0, size = self.icon_size, visible = false, layer = self.layer + 1,
    kind = "spell", id = 1,
  })
  return self
end

function Tooltip:show(text, x, y, icon)
  local body = normalise(text)
  local u = style.scale()
  local twu, thu = measure(body, self.size)
  local tw, th = math.ceil(twu * u), math.ceil(thu * u)
  local has_icon = type(icon) == "table" and (icon.path or icon.id)
  local pad = math.max(2, math.floor(self.pad * u))
  local gap = math.max(2, math.floor(self.gap * u))
  -- Icons are in window pixels; keep one about two text lines tall.
  local iw = has_icon and math.max(8, math.floor((icon.size or self.icon_size) * 0.5 * u)) or 0
  local w = pad + (has_icon and iw + gap or 0) + tw + pad
  local h = pad + math.max(has_icon and iw or 0, th) + pad

  local scr = hud.screen()
  x, y = math.floor(x or 0), math.floor(y or 0)
  if x + w > scr.width then x = scr.width - w end
  if y + h > scr.height then y = scr.height - h end
  if x < 0 then x = 0 end
  if y < 0 then y = 0 end

  local bg = self.prefix .. "bg"
  local tx = self.prefix .. "text"
  local ic = self.prefix .. "icon"
  local im = self.prefix .. "image"

  hud.set(bg, { x = x, y = y, w = w, h = h, visible = true })
  hud.set(tx, { x = x + pad + (has_icon and iw + gap or 0), y = y + pad,
    text = body, visible = true })

  if not has_icon then
    hud.set(ic, { visible = false })
    if self.image_made then hud.set(im, { visible = false }) end
  elseif icon.path then
    hud.set(ic, { visible = false })
    hud.image(im, { x = x + pad, y = y + pad, w = iw, h = iw,
      path = icon.path, layer = self.layer + 1, visible = true })
    self.image_made = true
  else
    if self.image_made then hud.set(im, { visible = false }) end
    hud.set(ic, { x = x + pad, y = y + pad, size = iw,
      kind = icon.kind or "spell", id = icon.id or 1, visible = true })
  end

  self.x, self.y, self.w, self.h = x, y, w, h
  self.visible = true
end

function Tooltip:hide()
  hud.set(self.prefix .. "bg", { visible = false })
  hud.set(self.prefix .. "text", { visible = false })
  hud.set(self.prefix .. "icon", { visible = false })
  if self.image_made then hud.set(self.prefix .. "image", { visible = false }) end
  self.visible = false
end

-- Attach to one of your HUD elements. get_text may return a string or {title, text}.
function Tooltip:attach(element_id, get_text, get_icon)
  self.attached[#self.attached + 1] = element_id
  hud.on(element_id, function(id, e)
    if e.kind == "mouse_enter" then
      local u = style.scale()
      self:show(get_text(), e.x + 14 * u, e.y + 16 * u, get_icon and get_icon())
    elseif e.kind == "mouse_leave" then
      self:hide()
    end
  end)
end

function Tooltip:destroy()
  self:hide()
  for _, id in ipairs(self.attached) do hud.off(id) end
  self.attached = {}
  hud.remove(self.prefix .. "bg")
  hud.remove(self.prefix .. "text")
  hud.remove(self.prefix .. "icon")
  hud.remove(self.prefix .. "image")
end

return M
