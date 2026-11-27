local match = require("src.match")

local sid = 123
assert(match.spell_wire({ category = 4, param = sid }) == sid)
assert(match.spell_wire({ category = 8, param = 0x6163, targets = { { results = { { value = sid } } } } }) == sid)
assert(match.spell_wire({ category = 8, param = 0x6163, targets = { { results = { { value = sid + 0x10000 } } } } }) == sid)