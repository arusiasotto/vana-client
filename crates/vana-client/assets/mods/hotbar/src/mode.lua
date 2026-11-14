-- Which way the player plays: the keyboard's hotbars (the default) or the gamepad's crossbars (src/pad.lua). Only one
-- shows and answers at a time. The Mode setting (per character, on the Extras page) says which; //hb mode switches it
-- for the session until the setting is changed again. With Detect Gamepad on, a controller coming or going switches it.

local M = {}

M.HOTBARS = "hotbars"
M.GAMEPAD = "gamepad"

local override = nil

function M.get()
  if override then return override end
  return settings.get("mode") == "Gamepad" and M.GAMEPAD or M.HOTBARS
end

function M.is_pad()
  return M.get() == M.GAMEPAD
end

-- `to` is M.HOTBARS or M.GAMEPAD, until the setting changes (use_setting).
function M.set(to)
  override = to == M.GAMEPAD and M.GAMEPAD or M.HOTBARS
end

-- The Mode setting was changed: it decides again.
function M.use_setting()
  override = nil
end

local seen = nil -- whether a controller played at the last sample; nil: not sampled yet

-- Forgets the last sample: the next one counts as the first.
function M.forget()
  seen = nil
end

-- Samples whether a controller plays. When detecting is on and that changed, picks the mode (gamepad with one,
-- hotbars without) and returns it; else nil. At the first sample only a controller changes anything.
function M.detect(enabled, connected)
  local before = seen
  seen = connected
  if not enabled or connected == before or (before == nil and not connected) then return nil end
  local to = connected and M.GAMEPAD or M.HOTBARS
  if M.get() == to then return nil end
  M.set(to)
  return to
end

function M.toggle()
  M.set(M.is_pad() and M.HOTBARS or M.GAMEPAD)
  return M.get()
end

local ALIASES = {
  hotbars = M.HOTBARS, hotbar = M.HOTBARS, bars = M.HOTBARS, keyboard = M.HOTBARS, keys = M.HOTBARS,
  gamepad = M.GAMEPAD, pad = M.GAMEPAD, controller = M.GAMEPAD, crossbar = M.GAMEPAD, crossbars = M.GAMEPAD,
}

-- A typed word ("pad", "keyboard", ...) as a mode, or nil.
function M.parse(text)
  return ALIASES[tostring(text or ""):lower()]
end

return M
