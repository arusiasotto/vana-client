--[[
    vanagear: Samurai.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Samurai: Ultimate Guide by Gregedor (2010, level 75-80), its armour,
      sample gear, weaponskill and stance sections; Samurai Gear Guide by Ashmada (weapons);
      the SAM Equipment Chart. Gregedor's TP rule: "not usually base stat bonuses like STR and
      DEX, but rather raw accuracy and attack" (STR and DEX count as 0.75 of them); "before
      level 50 you can't really affect [hits to 100 TP] because you have no Store TP gear";
      from 50, build to the hit count (Rajas Ring, Chivalrous Chain, Hachiman Sune-Ate),
      Ochiudo's Kote and Haubergeon for attack. At the core of the job is "the ability to do
      rapid weaponskills": the six-hit Store TP build first and never past it ("15% more
      weaponskills... worth more than the meager 2% or 3% haste"), then haste with Hasso,
      Brutal Earring always on. Weaponskills: "STR, STR and more STR" (Yukikaze, Gekko and
      Kasha are 75% STR), accuracy still matters as they are one hit; Rana is multi-hit.
    - BG-wiki, Community Samurai Guide (Oct 2025, level 99; its armour sections are marked
      unfinished): Store TP "a must for x-hit builds", Zanshin merits, accuracy tiers by
      content, cape double attack or DEX, Samurai's Nodowa +2 and the weaponskill-damage rings.
    - Earlier (M382): Bushido (FFXIAH 125). Meditate and Warding Circle sets come from what the
      server reads on the press; the server reads no gear for Third Eye, Seigan or Sengikori.
]]--

return {
    Fighter = true, Shooter = true,
    Tweaks = {
        Tp_Default = { Stats = { STORETP = 2.2, ZANSHIN = 0.5 } },
        Tp_Acc = { Stats = { STORETP = 1.5 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.0, ATT = 0.6, STR = 0.35, DEX = 0.35, STORETP = 0, ZANSHIN = 0, HASTE_GEAR = 2 } }, -- Gregedor: raw accuracy and attack, STR and DEX at 0.75 of them; no Store TP gear before 50
        } },
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.0, ATT = 0.6, STR = 0.35, DEX = 0.35, STORETP = 2.5, ZANSHIN = 0, HASTE_GEAR = 1.5 } }, -- Gregedor: build to the hit count from 50 (Rajas, Chivalrous Chain, Hachiman), Ochiudo's Kote, Haubergeon, then Swift Belt
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { STORETP = 3, HASTE_GEAR = 1.5, ACC = 1.0, ATT = 0.6, DOUBLE_ATTACK = 2, ZANSHIN = 0.5, STR = 0.35, DEX = 0.35 } }, -- Gregedor: the six-hit build first, then haste with Hasso, Brutal Earring always
            Tp_Acc = { Stats = { STORETP = 2, ACC = 1.5 } },                                      -- Gregedor: evasive mobs, accuracy over Store TP
            Ws_Default = { Stats = { STR = 1.2, ATT = 0.3, ACC = 0.5, DOUBLE_ATTACK = 0.5 } },     -- Gregedor: "STR, STR and more STR" (1 STR is about 4-5 attack), accuracy kept, Brutal Earring kept
        } },
        { To = 99, Tweaks = {
            Tp_Default = { Stats = { STORETP = 2.2, ZANSHIN = 0.5, DOUBLE_ATTACK = 2, HASTE_GEAR = 1.5, ACC = 0.8 } }, -- Community guide: Store TP for the x-hit build, Zanshin, cape double attack, accuracy tiers by content
            Tp_Acc = { Stats = { STORETP = 1.5, ACC = 1.5 } },                                    -- Community guide: the low, mid and high accuracy tiers
            Ws_Default = { Stats = { STR = 1.0, ALL_WSDMG_ALL_HITS = 3, ATT = 0.5, ACC = 0.4 } },  -- Community guide: Samurai's Nodowa +2, the weaponskill-damage rings and earring
        } },
    },
};
