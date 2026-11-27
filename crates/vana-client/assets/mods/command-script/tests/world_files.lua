local files = { ["scripts.json"] = json.encode({ ALL = { greet = { lines = { "/echo hi" } } } }) }
local data = require("src.data")
data.init({
  read = function(f) return files[f] end,
  write = function(f, t) files[f] = t end,
  decode = json.decode,
  encode = json.encode,
})
assert(data.file() == "scripts.json")
assert(data.get("greet", "WAR").lines[1] == "/echo hi")

local switched, loaded = data.set_world("Asura")
assert(switched and loaded and data.file() == "scripts-Asura.json")
assert(data.get("greet", "WAR").lines[1] == "/echo hi")

data.set("pull", { '/ja "Provoke" <t>' }, "WAR")
assert(files["scripts-Asura.json"]:find("Provoke"), "saved on this world")