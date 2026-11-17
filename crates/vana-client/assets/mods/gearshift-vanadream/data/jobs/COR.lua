--[[
    vanagear: Corsair - a support job (Lee, 22 Oct 2026) that shoots second and melees to build TP.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Corsair/Equipment Guide (Darkhack, 2012, 1-99), Corsair Equipment Guide,
      Corsair: A Guide By Keisho (2007, to 40), the guides by Yemaya and Kerb, How-To Guide:
      Corsair, Tight-Wad's Corsair Guide with its Party Roles and Weapons pages, Frugal
      Pirate, the Quick Draw Equipment Guide and Mastering Chance, all read to the end. Before
      22 guns and bullets are "not worth it": melee for TP with the rolls. From 22 "your Gun
      takes over as your main source of damage" and "the only problem is having the Ranged
      Accuracy to pull it off" (Keisho). Tight-Wad: "first and foremost we are a support job...
      Ranger-attacker second"; melee "Haste > Accuracy > Attack > Strength"; ranged "Accuracy
      > Attack > Strength", AGI behind; ranged weaponskills "Accuracy > Agility > Strength >
      Attack". Quick Draw from 40: accuracy "depends on your AGI" (Yemaya), damage is gun plus
      bullet times magic attack; Corsair's Tricorne at 60 adds Quick Draw damage and accuracy;
      Rapid Shot helps the slow guns; Commodore pieces augment the dice at 75.
    - BG-wiki, Community Corsair Guide (Oct 2026, level 99): Snapshot then Rapid Shot, Triple
      Shot and Store TP in the shot, magic accuracy for Quick Draw, roll duration and recast.
    - Earlier (M381): Luck of the Draw (FFXIAH 326), which set the Preshot cap (10% of the 70%
      comes from job points) and the idle below. The job point Snapshot is now counted from the
      server's gifts for the points the player has spent (vg\plan.lua Bonus), so the cap here is 70.
]]--

return {
    Fighter = true, Shooter = true,
    Modes = { 'PhantomRoll', 'QuickDraw', 'QuickDrawAcc' },
    Tweaks = {
        Idle = { Stats = { MEVA = 0.08, PDT = -4, MDT = -3, REFRESH = 1 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { HASTE_GEAR = 3, ACC = 1, ATT = 0.4, STR = 0.25 } },               -- Tight-Wad: melee TP "Haste > Accuracy > Attack > Strength"; no gun before 22
            Midshot = { Stats = { RACC = 2, RATT = 0.4 } },                                            -- Keisho 22-30: ranged accuracy is the limit
        } },
        { To = 60, Tweaks = {
            Midshot = { Stats = { RACC = 2, RATT = 0.6, STR = 0.3, AGI = 0.2 } },                     -- Tight-Wad: ranged "Accuracy > Attack > Strength", AGI behind
            Preshot = { Stats = { RAPID_SHOT = 2 } },                                                  -- How-To: Rapid Shot helps the slow guns (Beater's Mantle)
            Ws_Default = { Stats = { RACC = 1, AGI = 0.6, STR = 0.4, RATT = 0.25 } },                  -- Tight-Wad: ranged weaponskills "Accuracy > Agility > Strength > Attack"
            QuickDrawAcc = { Stats = { AGI = 1.5 } },                                                  -- Yemaya: Quick Draw accuracy "depends on your AGI"
            QuickDraw = { Stats = { MATT = 2, QUICK_DRAW_DMG = 0.5 } },                                -- Yemaya: gun plus bullet times magic attack; Corsair's Tricorne at 60
        } },
        { To = 75, Tweaks = {
            Midshot = { Stats = { RACC = 2, RATT = 0.6, STR = 0.3, AGI = 0.2 } },                     -- Tight-Wad, the same
            Ws_Default = { Stats = { RACC = 1, AGI = 0.6, STR = 0.4, RATT = 0.25 } },
            QuickDrawAcc = { Stats = { AGI = 1.5 } },
            QuickDraw = { Stats = { MATT = 2, QUICK_DRAW_DMG = 1 } },                                  -- the Equipment Guide: Quick Draw is (gun + bullet) x magic attack; the Tricorne's +10
            PhantomRoll = { Stats = { PHANTOM_ROLL = 10, PHANTOM_DURATION = 0.5 } },                   -- the Equipment Guide's dice table: Commodore Tricorne +1 at 75
        } },
        { To = 99, Tweaks = {
            Preshot = { Stats = { SNAPSHOT = 3, RAPID_SHOT = 1 } },                                    -- Community guide: the Snapshot piece, Rapid Shot for Flurry builds
            Midshot = { Stats = { STORETP = 2 } },
            TripleShot = { Stats = { TRIPLE_SHOT_RATE = 3, STORETP = 2 } },                            -- Community guide: Chasseur's Frac, Lanun Gants, the Culottes (the rate only counts under Triple Shot)
            Tp_Default = { Stats = { DOUBLE_ATTACK = 2, TRIPLE_ATTACK = 3, PDT = -1 } },               -- Community guide: the engaged entry set
            QuickDrawAcc = { Stats = { MACC = 2, QUICK_DRAW_MACC = 2 } },                              -- Community guide: Laksamana's Tricorne
            QuickDraw = { Stats = { QUICK_DRAW_DMG = 1, MATT = 2 } },                                  -- Community guide: Lanun Frac
            PhantomRoll = { Stats = { PHANTOM_ROLL = 10, PHANTOM_DURATION = 1, PHANTOM_RECAST = 2 } }, -- the Equipment Guide and the Community guide: Navarch's Gants, Desultor Tassets
        } },
    },
};
