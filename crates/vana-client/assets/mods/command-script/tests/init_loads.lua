chat = { add = function() end }
fs = {
  read = function() return "{}" end,
  write = function() end,
}
json = {
  decode = function(s) return load("return " .. s)() end,
  encode = function(t) return "{}" end,
}
log = { warn = function() end }
commands = {
  register = function() end,
  usage = function() return {} end,
  run = function() end,
}
settings = { get = function(k) return k == "on" end }
events = { on = function() end }
packets = { on_out = function() end }
timer = { every = function() return end }
game = setmetatable({
  player = function() return { main_job = 1, sub_job = 0, id = 1 } end,
  info = function() return { server = "Test" } end,
}, { __index = function() return function() end end })
res = setmetatable({ job = function(id) return ({ [1] = "WAR" })[id] end },
  { __index = function() return function() end end })
ui = setmetatable({
  window = function() end,
  on = function() end,
  open = function() end,
  close = function() end,
  is_open = function() return false end,
  update = function() end,
}, { __index = function() return function() end end })

local ok, err = pcall(require, "init")
assert(ok, tostring(err))