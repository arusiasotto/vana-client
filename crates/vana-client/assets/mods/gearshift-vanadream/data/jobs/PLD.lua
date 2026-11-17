--[[
    vanagear: Paladin - a tank (Lee, 22 Oct 2026).

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Paladin: Guide by Akirus (2009), Guide by Willriker (Parts I and III),
      Guide to PLD/NIN tanking by Thycian (2008-09), the Basic Hate Guide, Guide by Larahmie
      and the Misc part of Guide to Weapons and Armor. "A Paladin's job is to maintain
      consistent hate while taking as little damage as possible, and you should hold your
      priorities in that order." Early gear "VIT > Def > AGI > HP > MP" (Willriker), with
      enmity, MP and later accuracy the exceptions (Akirus); VIT to 50, DEF 50-56 as mob
      attack rises, VIT again after; Life Belt at 48 so Spirits Within connects; the artifact
      set's enmity, VIT, HP, AGI and shield skill; "+Enmity is a hate multiplier". End-game
      at 75 (Willriker): "every scrap of HP", VIT "not nearly as important as Hit Points",
      enmity and movement speed for kiting; DD only in burn parties: "Accuracy, Attack,
      Strength". PLD/NIN (Thycian): "forget VIT and DEF... focus on Haste for shorter recast
      timers on everything, Enmity for more hate and HP in case shadows are down"; "50% haste
      yields the same effect as +100 enmity" for Flash.
    - BG-wiki, Community Paladin Guide (2026, level 99): "Traditional Tank with emphasis on
      physical damage mitigation"; cap damage taken; balance the HP pool across sets, HP
      swaps first; the base tank set "balances DEF, HP, Acc, Attk, block rate, and enmity";
      the hybrid "HP > DT/PDT/MDT > Accuracy/Attack > STP/DA/TA/QA. In that order"; fast cast
      to 80%, spell interruption to -102%; cure set "Capped Cure Potency, Cure Potency
      Received, and DT"; Phalanx+ flat after skill; Flash sets fast cast and enmity; the block
      set "heavy emphasis on shield skill+".
    - Earlier (M382): The Divine Protector (FFXIAH 482) for the ability sets below.
]]--

return {
    Fighter = true, Tank = true, Skills = { 'Healing Magic', 'Enhancing Magic', 'Divine Magic' },
    Tweaks = {
        Idle = { Stats = { PDT = -6, MDT = -5, HP = 0.05, DEF = 0.03, VIT = 0.2, MEVA = 0.05, ENMITY = 0.2 } },
        Tp_Default = { Stats = { PDT = -3, MDT = -2.5, ENMITY = 0.5, SHIELDBLOCKRATE = 1, STORETP = 1, HP = 0.02 } },
        Tp_Hybrid = { Stats = { PDT = -5, MDT = -4, ENMITY = 0.5 } },
        Cure = { Stats = { SPELLINTERRUPT = 1, PDT = -1, MDT = -1, HP = 0.03, ENMITY = 0.5 }, Caps = { SPELLINTERRUPT = 102 } },
        Phalanx = { Stats = { PHALANX_RECEIVED = 6, ENHANCE = 0.6, SPELLINTERRUPT = 0.5 }, Caps = { SPELLINTERRUPT = 102 } },
        Divine = { Stats = { ENMITY = 1, FASTCAST = 1 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Idle = { Stats = { VIT = 0.3, DEF = 0.05, AGI = 0.15, HP = 0.03, MP = 0.02 } },                   -- Willriker: "VIT > Def > AGI > HP > MP"
            Dt = { Stats = { VIT = 0.3, DEF = 0.05, AGI = 0.15, HP = 0.03 } },                                -- Akirus: the most VIT, HP and AGI for the level
            Tp_Default = { Stats = { VIT = 0.3, DEF = 0.05, AGI = 0.15, HP = 0.03, MP = 0.03, ENMITY = 0.3, STORETP = 0 } }, -- Akirus: the exceptions are enmity and MP
        } },
        { To = 60, Tweaks = {
            Idle = { Stats = { VIT = 0.3, DEF = 0.06, AGI = 0.15, HP = 0.04, MP = 0.02 } },                   -- Akirus: VIT to 50, DEF 50-56, VIT again
            Dt = { Stats = { VIT = 0.3, DEF = 0.08, AGI = 0.15, HP = 0.04 } },                                -- Akirus: DEF has diminishing returns after 55
            Tp_Default = { Stats = { VIT = 0.3, DEF = 0.06, AGI = 0.15, HP = 0.04, ENMITY = 0.5, ACC = 0.5, MP = 0.03, STORETP = 0 } }, -- Akirus: Life Belt for Spirits Within, Mermaid Ring, the artifact enmity
            Divine = { Stats = { ENMITY = 1, FASTCAST = 1 } },                                                -- Hate Guide and Larahmie: Flash is hate; haste and fast cast shorten it
        } },
        { To = 75, Tweaks = {
            Idle = { Stats = { VIT = 0.2, DEF = 0.03, AGI = 0.1, HP = 0.06, MP = 0.02 } },                    -- Willriker, end-game: HP above VIT
            Dt = { Stats = { HP = 0.08, VIT = 0.2, DEF = 0.03 } },                                            -- Willriker: "every scrap of HP"
            Tp_Default = { Stats = { HP = 0.06, VIT = 0.2, ENMITY = 0.6, ACC = 0.5, STORETP = 0 } },          -- Willriker: enmity the multiplier, HP first
            Tp_Acc = { Stats = { ACC = 1.5, ATT = 0.6, STR = 0.6 } },                                         -- Willriker, burn parties only: "Accuracy, Attack, Strength"
            Movement = { Stats = { MOVE_SPEED_GEAR_BONUS = 12 } },                                            -- Willriker: kiting
            Utsusemi = { Stats = { HASTE_GEAR = 4, FASTCAST = 3, ENMITY = 0.5, HP = 0.03, SPELLINTERRUPT = 1 } }, -- Thycian, PLD/NIN: haste, enmity, HP; shield skill so a block does not interrupt
        } },
        { To = 99, Tweaks = {
            Idle = { Stats = { PDT = -8, MDT = -6, HP = 0.05, DEF = 0.02 } },                                 -- Community guide: cap damage taken
            Dt = { Stats = { PDT = -12, MDT = -10, HP = 0.06, MEVA = 0.1 } },                                 -- Community guide: "as close as possible to capping Damage Taken"
            Tp_Default = { Stats = { DEF = 0.03, HP = 0.05, ACC = 0.4, ATT = 0.2, SHIELDBLOCKRATE = 1, SHIELD = 0.2, ENMITY = 0.6, ENMITY_LOSS_REDUCTION = 0.3 } }, -- Community guide: the base tank set, DEF, HP, accuracy, attack, block rate, enmity
            Tp_Hybrid = { Stats = { HP = 0.05, PDT = -5, MDT = -4, ACC = 0.6, ATT = 0.3, STORETP = 0.8, DOUBLE_ATTACK = 0.8 } }, -- Community guide: "HP > DT/PDT/MDT > Accuracy/Attack > STP/DA/TA/QA"
            Precast = { Stats = { FASTCAST = 3 } },                                                           -- Community guide: fast cast to 80%
            Interim = { Stats = { SPELLINTERRUPT = 1.5 } },                                                   -- Community guide: -102%
            Cure = { Stats = { CURE_POTENCY = 3, CURE_POTENCY_RCVD = 1, SPELLINTERRUPT = 1, PDT = -1, MDT = -1 } }, -- Community guide: capped cure potency, cure potency received, DT
            Phalanx = { Stats = { PHALANX_RECEIVED = 6, ENHANCE = 0.6, SPELLINTERRUPT = 0.5 } },              -- Community guide: Phalanx+ is flat after skill
            Divine = { Stats = { ENMITY = 1, FASTCAST = 1.5 } },                                              -- Community guide: Flash sets, fast cast and enmity
        } },
    },
    Abilities = {
        ['Rampart'] = { Stats = { RAMPART_DURATION = 1 } },
        ['Sentinel'] = { Stats = { SENTINEL_EFFECT = 1 } },
        ['Cover'] = { Stats = { COVER_DURATION = 1, COVER_TO_MP = 1 } },
        ['Fealty'] = { Stats = { ENHANCES_FEALTY = 1 } },
        ['Chivalry'] = { Stats = { ENHANCES_CHIVALRY = 1, MND = 0.2 } },
        ['Divine Emblem'] = { Stats = { ENHANCES_DIVINE_EMBLEM = 1 } },
        ['Holy Circle'] = { Stats = { HOLY_CIRCLE_DURATION = 1, HOLY_CIRCLE_POTENCY = 2 } },
        ['Shield Bash'] = { Stats = { SHIELD_BASH = 1 } },
        ['Provoke'] = { Stats = { ENMITY = 1 } },
    },
};
