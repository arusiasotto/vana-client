--[[
    vanagear: Monk.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Monk Guide by Gisselle (2006-2010, level 75 cap). Early armour is "pretty
      weak", so DEF plus attack and accuracy pieces (Legionnaire's Mittens, Republic Subligar,
      Courage Ring, Purple Belt's haste); 31-60 accuracy and attack ("Ochiudo's Kote +20 attack
      is a must", Sniper's Ring, Life and Virtuoso Belts, Scorpion Harness, Chivalrous Chain's
      Store TP, Kung Fu Shoes for kicks); 61-75 attack and STR with haste (Amemet Mantle, Aesir
      Ear Pendant, Byakko's Haidate, Walahra Turban, Brutal Earring) and accuracy kept as the
      swap-out rule: "I rather hit for a point less but more often". Weaponskills read STR and
      VIT but accuracy is not traded for them.
    - BG-wiki, Community Monk Guide (2026, level 99): Martial Arts only to the delay floor for
      the weapon ("extra Martial Arts will actually decrease your TP gain"), Subtle Blow 50+25
      in the TP set, kick attack rate, Store TP, multi-attack over weaponskill damage for the
      multi-hit weaponskills; idle and the Omen/Odyssey sets are damage taken -50% first.
    - Earlier (M382): iiPunch (FFXIAH 173) for the ability gear below.
]]--

return {
    Fighter = true,
    Tweaks = {
        Tp_Default = { Stats = { MARTIAL_ARTS = 0.5, KICK_ATTACK_RATE = 0.8, SUBTLE_BLOW = 0.3, ACC = 0.8, COUNTER = 0.3 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.0, ATT = 0.6, STR = 0.5, DEX = 0.3, MARTIAL_ARTS = 0.1, KICK_ATTACK_RATE = 0, SUBTLE_BLOW = 0, COUNTER = 0 } }, -- Gisselle 1-30: attack and accuracy hands, legs and earrings, STR rings; kicks come at 50
            Idle = { Stats = { DEF = 0.05 } },                                                  -- Gisselle 1-30: armour is DEF only
        } },
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.5, ATT = 0.6, STR = 0.5, DEX = 0.3, KICK_ATTACK_RATE = 0.4, SUBTLE_BLOW = 0, COUNTER = 0 } }, -- Gisselle 31-60: accuracy belts and rings, Ochiudo's Kote, Chivalrous Chain, Kung Fu Shoes
            Ws_Default = { Stats = { STR = 0.8, VIT = 0.3, ACC = 0.5 } },                      -- Gisselle: weaponskills read STR and VIT; accuracy is not swapped out for them
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.2, ATT = 0.7, STR = 0.6, DEX = 0.3, DOUBLE_ATTACK = 2, KICK_ATTACK_RATE = 0.8, SUBTLE_BLOW = 0, COUNTER = 0 } }, -- Gisselle 61-75: Amemet, Aesir, STR rings, Byakko and Walahra haste, Brutal Earring, Dune Boots
            Ws_Default = { Stats = { STR = 1.0, VIT = 0.4, ACC = 0.5, ATT = 0.5 } },           -- Gisselle 61-75: STR and VIT for the weaponskill macro, accuracy kept
        } },
        { To = 99, Tweaks = {
            Tp_Default = { Stats = { MARTIAL_ARTS = 0.5, KICK_ATTACK_RATE = 0.8, SUBTLE_BLOW = 0.3, ACC = 0.8, COUNTER = 0.3, STORETP = 1.5, DOUBLE_ATTACK = 2 } }, -- Community guide: Martial Arts to the floor, kicks, Subtle Blow 50+25, Store TP, multi-attack
            Tp_Hybrid = { Stats = { PDT = -4, MDT = -2, SUBTLE_BLOW = 0.4 } },                  -- Community guide: the established set is DT-capped with Subtle Blow
            Dt = { Stats = { PDT = -12, SUBTLE_BLOW = 0.3 } },                                  -- Community guide: 50% DT first
            Idle = { Stats = { PDT = -4 } },                                                    -- Community guide idle: 50% DT first
        } },
    },
    Abilities = {
        ['Chakra'] = { Stats = { VIT = 1, CHAKRA_MULT = 2, CHAKRA_REMOVAL = 1 } },
        ['Counterstance'] = { Stats = { COUNTERSTANCE_EFFECT = 1, COUNTER = 0.5 } },
        ['Boost'] = { Stats = { BOOST_EFFECT = 1 } },
        ['Footwork'] = { Stats = { FOOTWORK_ATT_BONUS = 1 } },
        ['Impetus'] = { Stats = { AUGMENTS_IMPETUS = 1 } },
        -- read off the target (yourself) in job_utils\monk.lua, so the script reader misses them
        -- (GetAwayCoxn's MNK.lua has both sets)
        ['Dodge'] = { Stats = { DODGE_EFFECT = 1 } },
        ['Focus'] = { Stats = { FOCUS_EFFECT = 1 } },
    },
};
