--[[
    vanagear: Dragoon.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Dragoon Guide by Sharaa (2009-10, levels 1-75, with Dakk's haste build) and
      Dragoon: Guide to Weapons and Armor (Juso, 2010). Two builds: meat, "stack lots of acc
      and eat meat", and sushi, "lots of STR and ATT". "High Delay, it hurts when you miss."
      31-60 Peacock Charm "THE best Accuracy piece on your neck", Sniper's Rings "not
      optional", Swift and Headlong Belts for haste, Scorpion Harness, Ecphoria Ring and
      Chivalrous Chain for Store TP, Pole Grip's double attack; "Penta Thrust is very accuracy
      dependent, so stack on the acc". 61-75 Assault Jerkin's attack, Optical Hat, Askar
      Korazin "some DA, store TP that will push most DRGs into a 6-hit build", Homam triple
      attack and accuracy; "do not try to be a full haste build if you are not planning on
      going 8/8 polearm skill".
    - BG-wiki, Community Dragoon Guide and Dragoon Guide by Kaius (level 99): "the next two
      most important aspects to any engaged set are accuracy and haste", to the 80% delay cap
      with Hasso and the wyvern's ability haste; "Store TP and multi-hit come after haste";
      "a nice balance between X-hit and STP"; jumps "maximize TP return"; weaponskills
      Stardiver multi-attack, TP bonus, STR, attack; Impulse Drive and Camlann's Torment
      weaponskill damage first; Drakesbane crit; Geirskogul DEX.
    - Earlier (M382): Sigurd's Descendants (FFXIAH 182) for the ability sets below.
]]--

return {
    Fighter = true, Pet = true,
    Tweaks = {
        Tp_Default = { Stats = { STORETP = 2 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { ACC = 0.8, STR = 0.35, DEX = 0.45, ATT = 0.3, STORETP = 0.5 } }, -- Sharaa: the meat build stacks accuracy; "DEX = acc, STR = att"; Spike Necklace, Beetle Earring
            Tp_Acc = { Stats = { ACC = 1.5, DEX = 0.6 } },                                             -- Sharaa: "High Delay, it hurts when you miss"
        } },
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.0, STORETP = 1.8, HASTE_GEAR = 2, DOUBLE_ATTACK = 2 } },  -- Sharaa and Juso: Peacock Charm, Ecphoria Ring, Swift and Headlong Belts, Pole Grip
            Tp_Acc = { Stats = { ACC = 1.8, STORETP = 1, DEX = 0.5 } },                                -- Sharaa 50-59: Scorpion Harness "the best ACC piece you can get"
            Ws_Default = { Stats = { ACC = 0.7, STR = 1, DEX = 0.5, DOUBLE_ATTACK = 1 } },             -- Sharaa: Penta Thrust "stack on the acc"; Pole Grip "beneficial for TP as well as WS"
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { ACC = 0.9, ATT = 0.4, STORETP = 1.8, DOUBLE_ATTACK = 2.2, TRIPLE_ATTACK = 3, HASTE_GEAR = 2 } }, -- Sharaa: Assault Jerkin, Askar Korazin's six-hit build, Homam; haste only with 8/8 polearm
            Tp_Acc = { Stats = { ACC = 2, DEX = 0.5 } },                                               -- Sharaa: the meat build, Optical Hat, Scorpion Harness
            Ws_Default = { Stats = { STR = 1.1, ATT = 0.6, ACC = 0.6, DEX = 0.5 } },                   -- Sharaa: "the attack screams get me"; Penta Thrust is accuracy dependent
        } },
        { To = 99, Tweaks = {
            Tp_Default = { Stats = { HASTE_GEAR = 3.5, ACC = 0.9, STORETP = 2, DOUBLE_ATTACK = 2, TRIPLE_ATTACK = 3, QUAD_ATTACK = 4 } }, -- Community guide and Kaius: accuracy and haste to the delay cap, then Store TP and multi-hit
            Ws_Default = { Stats = { STR = 1, ATT = 0.5, ALL_WSDMG_ALL_HITS = 3, TP_BONUS = 0.01, DEX = 0.3 } }, -- Community guide: weaponskill damage, TP bonus, STR, attack
        } },
    },
    Abilities = {
        ['Jump'] = { Stats = { JUMP_DOUBLE_ATTACK = 2, JUMP_ACC_BONUS = 0.5, JUMP_TP_BONUS = 0.05, JUMP_ATT_BONUS = 1, DOUBLE_ATTACK = 1.5, TRIPLE_ATTACK = 2, STORETP = 1, ACC = 0.3 } },
        ['High Jump'] = { Stats = { JUMP_DOUBLE_ATTACK = 2, JUMP_ACC_BONUS = 0.5, JUMP_TP_BONUS = 0.05, JUMP_ATT_BONUS = 1, DOUBLE_ATTACK = 1.5, TRIPLE_ATTACK = 2, STORETP = 1, ACC = 0.3 } },
        ['Spirit Jump'] = { Stats = { JUMP_DOUBLE_ATTACK = 2, JUMP_ACC_BONUS = 0.5, JUMP_SPIRIT_TP_BONUS = 0.05, JUMP_SOUL_SPIRIT_ATT_BONUS = 1, DOUBLE_ATTACK = 1.5, STORETP = 1 } },
        ['Soul Jump'] = { Stats = { JUMP_DOUBLE_ATTACK = 2, JUMP_ACC_BONUS = 0.5, JUMP_SPIRIT_TP_BONUS = 0.05, JUMP_SOUL_SPIRIT_ATT_BONUS = 1, DOUBLE_ATTACK = 1.5, STORETP = 1 } },
        ['Ancient Circle'] = { Stats = { ANCIENT_CIRCLE_DURATION = 1, ANCIENT_CIRCLE_POTENCY = 2 } },
        ['Spirit Link'] = { Stats = { ENHANCES_SPIRIT_LINK = 1 } },
        ['Deep Breathing'] = { Stats = { ENHANCE_DEEP_BREATHING = 1 } },
        -- the wyvern's level and whether it copies your subjob traits are set as it is called (petutils.cpp,
        -- pets\wyvern.lua); JUMP_DOUBLE_ATTACK and JUMP_ACC_BONUS above are read on the jump (weaponskills.lua)
        ['Call Wyvern'] = { Stats = { WYVERN_LVL_BONUS = 3, WYVERN_SUBJOB_TRAITS = 2 } },
    },
};
