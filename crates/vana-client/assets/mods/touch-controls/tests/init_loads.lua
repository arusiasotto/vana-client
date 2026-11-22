local keys = require("src.keys")

local m = keys.active(keys.move, 0, -1, 0.15)
assert(m.up and not m.down and not m.left and not m.right)
m = keys.active(keys.move, 0, 0, 0.15)
assert(not m.up and not m.down and not m.left and not m.right)

local c = keys.active(keys.cam, 1, 0, 0.15)
assert(c.right and not c.left and not c.up and not c.down)