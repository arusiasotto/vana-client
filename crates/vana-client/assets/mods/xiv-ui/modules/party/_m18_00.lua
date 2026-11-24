-- M18 bundled sources; generated from stage sources. Do not edit.
return {
["src.config_schema"]=[[
-- Generated whitelist from owning mod settings + explicit native layout fields.
return {
  {key="on",type="bool",label="XIV Party List",help="Draws an FFXIV-style party frame on the left of the screen.",default=true},
  {key="offset_x",type="int",label="Left offset",help="Distance from the left edge of the screen.",default=16,min=0,max=1200,step=4},
  {key="offset_y",type="int",label="Top offset",help="Distance from the top of the screen.",default=120,min=0,max=1200,step=4},
  {key="scale",type="int",label="Party Scale",help="",default=100,min=50,max=150,step=10},
  {key="buff_count",type="int",label="Visible Main Party Statuses",help="",default=6,min=1,max=32,step=1},
  {key="range",type="int",label="Range Marker (yalms)",help="",default=21,min=5,max=30,step=1},
  {key="pets",type="bool",label="Show Observed Pets",help="",default=true},
  {key="hide_solo",type="bool",label="Hide Solo",help="",default=false},
  {key="hide_cutscene",type="bool",label="Hide During Events",help="",default=true},
  {key="align_bottom",type="bool",label="Bottom-align Party Rows",help="",default=false},
  {key="single_alliance",type="bool",label="Full-width Single Alliance",help="",default=false},
  {key="range_numbers",type="bool",label="Numeric Range",help="",default=false},
  {key="filter_whitelist",type="bool",label="Only Prioritised Statuses",help="",default=false},
}
]],
["src.hud_config"]=[[
local factory = require("src.hud_config_factory")
local ALIAS = "party"
local M = {}
function M.new(base, schema, hooks) return factory.new(base, schema, hooks, ALIAS) end
function M.active() return factory.active(ALIAS) end
function M.read(key, base) return factory.read(ALIAS, key, base) end
return M
]],
["src.hud_drag"]=[[
-- Owner-local drag transactions. No frame timer, global state or direct saves.
local M = {}
function M.new(cfg, xkey, ykey, units, allow, ysign)
  local drag
  return function(e)
    if e.kind == "drag_start" then
      if e.button and e.button ~= "left" then return false end
      if allow and not allow() then return true end
      if cfg.hooks.capture and cfg.hooks.capture().preview then return true end
      local b = cfg.begin()
      if not b.ok then return true end
      local fields = {}
      for _, f in ipairs(b.info.fields) do fields[f.key] = f end
      if not fields[xkey] or not fields[ykey] then cfg.cancel(b.token); return true end
      drag = { token = b.token, x = b.info.values[xkey], y = b.info.values[ykey], fields = fields, u = units() }
      return true
    elseif e.kind == "drag" or e.kind == "drag_end" then
      if not drag then return false end
      local function value(key, start, delta)
        local f = drag.fields[key]
        local n = math.floor(start + (delta or 0) / math.max(.01, drag.u) + .5)
        return math.max(f.min, math.min(f.max, n))
      end
      local x = cfg.set(drag.token, xkey, value(xkey, drag.x, e.dx))
      local y = cfg.set(drag.token, ykey, value(ykey, drag.y, (e.dy or 0) * (ysign or 1)))
      if not x.ok or not y.ok then cfg.cancel(drag.token); drag = nil; return true end
      if e.kind == "drag_end" then
        if e.window or e.over then cfg.cancel(drag.token)
        else
          local r = cfg.commit(drag.token)
          if not r.ok then cfg.cancel(drag.token); chat.add("XIV HUD: drag not saved; " .. (r.reason or "conflict")) end
        end
        drag = nil
      end
      return true
    end
    return false
  end
end
return M
]],
["src.trusts"]=[[
-- Trust job hints from XivUI/jobs.lua (Tylas/maybeLynd). Models/ambiguity validated at runtime; no inferred levels.
return {
  { name = "Amchuchu", job = "RUN" },
  { name = "ArkEV", job = "PLD" },
  { name = "ArkHM", job = "WAR" },
  { name = "August", job = "PLD" },
  { name = "Curilla", job = "PLD" },
  { name = "Gessho", job = "NIN" },
  { name = "Mnejing", job = "PLD" },
  { name = "Rahal", job = "PLD" },
  { name = "Rughadjeen", job = "PLD" },
  { name = "Trion", job = "PLD" },
  { name = "Valaineral", job = "PLD" },
  { name = "Abenzio", job = "THF" },
  { name = "Abquhbah", job = "WAR" },
  { name = "Aldo", job = "THF", model = 3034 },
  { name = "Areuhat", job = "WAR" },
  { name = "ArkGK", job = "SAM" },
  { name = "ArkMR", job = "BST" },
  { name = "Ayame", job = "SAM", model = 3004 },
  { name = "BabbanMheillea", job = "MNK" },
  { name = "Balamor", job = "DRK" },
  { name = "Chacharoon", job = "THF" },
  { name = "Cid", job = "WAR" },
  { name = "Darrcuiln", job = "SPC" },
  { name = "Excenmille", job = "PLD", model = 3003 },
  { name = "Excenmille", job = "SPC" },
  { name = "Fablinix", job = "RDM" },
  { name = "Gilgamesh", job = "SAM" },
  { name = "Halver", job = "PLD" },
  { name = "Ingrid", job = "WAR", model = 3102 },
  { name = "Iroha", job = "SAM", model = 3111 },
  { name = "Iroha", job = "SAM", model = 3112 },
  { name = "IronEater", job = "WAR" },
  { name = "Klara", job = "WAR" },
  { name = "LehkoHabhoka", job = "THF" },
  { name = "LheLhangavo", job = "MNK" },
  { name = "LhuMhakaracca", job = "BST" },
  { name = "Lilisette", job = "DNC", model = 3049 },
  { name = "Lilisette", job = "DNC", model = 3084 },
  { name = "Lion", job = "THF", model = 3011 },
  { name = "Lion", job = "THF", model = 3081 },
  { name = "Luzaf", job = "COR" },
  { name = "Maat", job = "MNK", model = 3037 },
  { name = "Maximilian", job = "WAR" },
  { name = "Mayakov", job = "DNC" },
  { name = "Mildaurion", job = "PLD" },
  { name = "Morimar", job = "BST" },
  { name = "Mumor", job = "DNC", model = 3050 },
  { name = "NajaSalaheem", job = "MNK", model = 3016 },
  { name = "Naji", job = "WAR" },
  { name = "NanaaMihgo", job = "THF" },
  { name = "Nashmeira", job = "PUP", model = 3027 },
  { name = "Noillurie", job = "SAM" },
  { name = "Prishe", job = "MNK", model = 3017 },
  { name = "Prishe", job = "MNK", model = 3082 },
  { name = "Rainemard", job = "RDM" },
  { name = "RomaaMihgo", job = "THF" },
  { name = "Rongelouts", job = "WAR" },
  { name = "Selh\\", job = "SPC" },
  { name = "ShikareeZ", job = "DRG" },
  { name = "Tenzen", job = "SAM", model = 3012 },
  { name = "Teodor", job = "SAM" },
  { name = "UkaTotlihn", job = "DNC" },
  { name = "Volker", job = "WAR" },
  { name = "Zazarg", job = "MNK" },
  { name = "Zeid", job = "DRK", model = 3010 },
  { name = "Zeid", job = "DRK", model = 3086 },
  { name = "Matsui-P", job = "NIN" },
  { name = "Elivira", job = "RNG" },
  { name = "Makki-Chebukki", job = "RNG" },
  { name = "Margret", job = "RNG" },
  { name = "Najelith", job = "RNG" },
  { name = "SemihLafihna", job = "RNG" },
  { name = "Tenzen", job = "RNG", model = 3097 },
  { name = "Adelheid", job = "SCH" },
  { name = "Ajido-Marujido", job = "BLM" },
  { name = "ArkTT", job = "BLM" },
  { name = "D.Shantotto", job = "BLM" },
  { name = "Gadalar", job = "BLM" },
  { name = "Ingrid", job = "WHM", model = 3025 },
  { name = "Kayeel-Payeel", job = "BLM" },
  { name = "Kukki-Chebukki", job = "BLM" },
  { name = "Leonoyne", job = "BLM" },
  { name = "Mumor", job = "BLM", model = 3104 },
  { name = "Ovjang", job = "RDM" },
  { name = "Robel-Akbel", job = "BLM" },
  { name = "Rosulatia", job = "BLM" },
  { name = "Shantotto", job = "BLM", model = 3000 },
  { name = "Shantotto", job = "BLM", model = 3110 },
  { name = "Ullegore", job = "BLM" },
  { name = "Cherukiki", job = "WHM" },
  { name = "FerreousCoffin", job = "WHM" },
  { name = "Karaha-Baruha", job = "WHM" },
  { name = "Kupipi", job = "WHM" },
  { name = "MihliAliapoh", job = "WHM" },
  { name = "Monberaux", job = "SPC" },
  { name = "Nashmeira", job = "WHM", model = 3083 },
  { name = "Ygnas", job = "WHM" },
  { name = "Arciela", job = "RDM", model = 3074 },
  { name = "Arciela", job = "RDM", model = 3085 },
  { name = "Joachim", job = "BRD" },
  { name = "KingOfHearts", job = "RDM" },
  { name = "Koru-Moru", job = "RDM" },
  { name = "Qultada", job = "COR" },
  { name = "Ulmia", job = "BRD" },
  { name = "Brygid", job = "GEO" },
  { name = "Cornelia", job = "GEO" },
  { name = "Kupofried", job = "GEO" },
  { name = "KuyinHathdenna", job = "GEO" },
  { name = "Moogle", job = "GEO" },
  { name = "Sakura", job = "GEO" },
  { name = "StarSibyl", job = "GEO" },
  { name = "Aldo", job = "THF" },
  { name = "Apururu", job = "WHM", model = 3061 },
  { name = "Ayame", job = "SAM" },
  { name = "Flaviria", job = "DRG" },
  { name = "InvincibleShield", job = "WAR" },
  { name = "JakohWahcondalo", job = "THF" },
  { name = "Maat", job = "MNK" },
  { name = "NajaSalaheem", job = "THF" },
  { name = "Pieuje", job = "WHM" },
  { name = "Sylvie", job = "GEO" },
  { name = "Yoran-Oran", job = "WHM" },
}
]],
}
