local runner = require("src.runner")

local kind, cmd, after = runner.parse_line('/ja "Composure" <me> <wait 1>')
assert(kind == "cmd" and cmd:find("Composure") and after == 1)
local k, w = runner.parse_line("wait 4")
assert(k == "wait" and w == 4)