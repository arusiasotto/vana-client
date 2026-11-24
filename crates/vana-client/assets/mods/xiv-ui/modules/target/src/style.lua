-- Shared FFXIV-style palette and geometry for the XIV mod forks.
-- Copy this file (and tooltip.lua) into each fork's src/ folder: vana-client mods
-- cannot require files from another mod.

local M = {}

M.colour = {
  bg         = { 30, 30, 30, 235 },
  bg_soft    = { 41, 41, 41, 225 },
  bg_dim     = { 28, 28, 28, 160 },
  edge       = { 168, 139, 80, 235 },
  edge_dim   = { 90, 84, 70, 150 },
  text       = { 216, 214, 208, 255 },
  text_dim   = { 150, 148, 142, 255 },
  gold       = { 201, 164, 99, 255 },
  hp         = { 100, 200, 120, 255 },
  mp         = { 96, 150, 230, 255 },
  tp         = { 235, 185, 90, 255 },
  cast       = { 110, 200, 230, 255 },
  recast     = { 0, 0, 0, 175 },
  outline    = { 0, 0, 0, 210 },
}

M.tooltip = {
  pad   = 10,
  icon  = 38,
  gap   = 8,
  size  = 11,
  radius = 6,
  line  = 1.5,
  layer = 60,
}

M.slot = {
  size   = 40,
  gap    = 6,
  radius = 8,
  line   = 1.5,
}

M.font = "regular"

function M.scale()
  return hud.screen().ui_scale
end

function M.px(n)
  return math.floor(n * M.scale() + 0.5)
end

return M
