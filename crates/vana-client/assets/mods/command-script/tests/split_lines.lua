local data = require("src.data")

local lines = data.split_lines('/ja "A" <t> | wait 1 | then /ws "B" <t>')
assert(#lines == 3, "pipe split")
assert(lines[2]:match("wait"))
assert(data.sanitize_word(" Pull-1 ") == "pull-1")
assert(data.sanitize_word("bad!") == "bad")