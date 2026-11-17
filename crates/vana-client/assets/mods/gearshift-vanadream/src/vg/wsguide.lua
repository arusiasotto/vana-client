--[[
    vanagear: what the wiki weaponskill pages say about gear, laid over every job's weaponskill
    sets (M402, "the ws guides, fold those into every template"; read 22 Oct 2026).

    The server's own scripts already give vanagear each weaponskill's stat modifiers, hit count
    and kind (vg\plan.lua, wsMode). The BG-wiki and FFXIclopedia weaponskill pages were read
    for every weapon type and state no gear priority beyond those modifiers, except the notes
    below. Nothing here is a weight the pages gave; each is the stat the page named, at a
    weight on roles.lua's Ws_Default scale. Pages that named nothing are not here.
]]--

-- "Chance of critical hit varies with TP" (or a flat crit bonus): crit rate and crit damage count
local crit = { CRITHITRATE = 1, CRIT_DMG_INCREASE = 1 };

-- the page says attack is the lever: no attack/defense ratio bonus (Fudo, "as with Kaiten"), the TP
-- term scales attack (Iron Tempest, Sturmwind), "stack Strength and Attack" (Mercy Stroke)
local attack = { ATT = 1 };

-- "Accuracy varies with TP": the hits want landing more than usual
local accuracy = { ACC = 0.8 };
local rangedAccuracy = { RACC = 1 };

local guide = {
    -- axe
    ['Rampage'] = crit,
    -- dagger (Malizia's Thief WS damage guide and the pages)
    ['Evisceration'] = crit,
    ['Mercy Stroke'] = attack,
    ['Cyclone'] = { MATT = 1 },                                   -- FFXIclopedia: "directly affected by Magic Attack Bonus"
    -- katana
    ['Blade: Rin'] = crit,
    ['Blade: Jin'] = crit,
    ['Blade: Hi'] = crit,
    -- sword
    ['Vorpal Blade'] = crit,
    ['Chant du Cygne'] = crit,
    ['Swift Blade'] = accuracy,
    ['Sanguine Blade'] = { MATT = 1.5, INT = 0.5 },               -- FFXIclopedia: "Magic Attack Bonus increases this far more than INT"; INT difference uncapped
    ['Spirits Within'] = { HP = 1 },                              -- BG: depends only on current HP and TP
    ['Atonement'] = { ALL_WSDMG_ALL_HITS = 3, ENMITY = 0.5 },     -- BG: weaponskill damage applies to both hits; enmity gear only indirectly
    -- great sword
    ['Power Slash'] = crit,
    ['Herculean Slash'] = { MATT = 1 },                           -- FFXIclopedia: "also modified by Magic Attack Bonus"
    -- great axe
    ['Iron Tempest'] = attack,
    ['Sturmwind'] = attack,
    ['Keen Edge'] = crit,
    ['Raging Rush'] = crit,
    ["Ukko's Fury"] = crit,
    ['Armor Break'] = { MACC = 0.5 },                             -- BG: the effect depends on magic accuracy
    -- scythe
    ['Vorpal Scythe'] = crit,
    -- polearm
    ['Penta Thrust'] = accuracy,
    ['Vorpal Thrust'] = crit,
    ['Skewer'] = crit,
    ['Drakesbane'] = crit,
    -- great katana
    ['Tachi: Fudo'] = attack,
    ['Tachi: Kaiten'] = attack,
    ['Tachi: Rana'] = accuracy,
    -- hand-to-hand
    ['Backhand Blow'] = crit,
    ['Victory Smite'] = crit,
    ["Ascetic's Fury"] = crit,
    ['Stringing Pummel'] = crit,
    -- club
    ['Hexa Strike'] = crit,
    ['True Strike'] = { CRIT_DMG_INCREASE = 1.5 },                -- BG: "100% Critical Hit Rate", so only the crit damage counts
    -- staff
    ['Starburst'] = { MAGIC_DAMAGE = 1 },                         -- BG: the formula adds Magic Damage directly
    ['Sunburst'] = { MAGIC_DAMAGE = 1 },
    -- marksmanship
    ['Sniper Shot'] = crit,
    ['Heavy Shot'] = crit,
    ['Slug Shot'] = rangedAccuracy,                               -- BG: a substantial ranged accuracy penalty at 1000 TP
    ['Wildfire'] = { MATT = 1 },                                  -- BG: "enhanced by Magic Attack Bonus", independent of gun and bullet damage
    -- archery
    ['Dulling Arrow'] = crit,
    ['Arching Arrow'] = crit,
    ['Sidewinder'] = rangedAccuracy,                              -- BG: an accuracy penalty that varies with TP
};

return guide;
