--[[
    vanagear: Beastmaster.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against Lee's own sets first (LuAshitacast\Ferrin_3\BST.lua, his
    LegacyAC xml and the 19 Sept sets notes): hybrid engaged with accuracy, pet gear in its
    own sets, Reward on MND and Reward gear, Charm on CHR, Idle on damage taken and Regen, the
    Ready recast piece on the press. The guides agree with that shape:
    - FFXIclopedia, Beastmaster Equipment Guide, How-To Guide: Beastmaster, Beastmaster Solo
      Guide by Zennytri, Beastmaster Vs. Maat Guide, all read in full. Early: "high HP and
      defense over anything else", CHR gear because charisma "is the only statistic which
      aides charm success rates", and "accuracy over pure damage" so the master does not
      out-damage the pet. 31-60 in a party: "strength, dexterity, attack, and accuracy"; the
      artifact set's Charm +20 "doubles the duration". 61-75: Dusk and Suppanomimi at 72,
      /DNC dual wield; the Maat-fight Rampage set is STR, accuracy and attack.
    - FFXIclopedia, Beastmaster Reward Guide (Linkzell): Pet Food Zeta heals 900 + 3 per MND
      over 45, Eta 1200 + 4 per MND over 50, Reward gear to a 50% cap (axes, gloves, boots), so
      one point of Reward is worth about 2.5 MND at Zeta.
    - BG-wiki, All Jobs Gear Sets/Beastmaster (level 99): Onslaught "DEX and Weapon Skill
      Damage", Primal Rend "CHR and Weapon Skill Damage", the TP set "DEX and Store TP" at
      -50% and -25% damage taken; Community Beastmaster Guide (gear section empty): Sic/Ready
      recast and Reward recast "very viable", Charm "almost completely obsolete" at 99 (Lee
      keeps a Charm set, so its weights are not lowered).
    - Earlier (M381): Falkirk's Compendium (FFXIAH 227) for the pet modes, which none of the
      wiki guides band: those stay as the base Tweaks below.
]]--

return {
    Fighter = true, Pet = true,
    Modes = { 'ReadyPrecast', 'Reward', 'Charm', 'Call' },
    Tweaks = {
        Idle = { Stats = { REFRESH = 0, REGEN = 4 } },
        PetTP = { Pet = { DOUBLE_ATTACK = 2.5, REGAIN = 0.5 } },
        PetAtk = { Pet = { PET_TP_BONUS = 0.02 } },
        PetDT = { Pet = { REGEN = 1 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { ACC = 0.8, STR = 0.3, ATT = 0.3 } },                                 -- Equipment Guide: "accuracy over pure damage"; STR rings
            Idle = { Stats = { HP = 0.03, DEF = 0.05, REGEN = 2 } },                                      -- How-To: "high HP and defense over anything else"
            Charm = { Stats = { CHR = 1.5 } },                                                            -- Equipment Guide: CHR "the only statistic which aides charm"
        } },
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { ACC = 0.8, STR = 0.35, ATT = 0.3, DOUBLE_ATTACK = 2, DUAL_WIELD = 0.5 } }, -- How-To, party play: "strength, dexterity, attack, and accuracy"
            Reward = { Stats = { MND = 1, REWARD_HP_BONUS = 2.5, REWARD_RECAST = 1 }, Caps = { REWARD_HP_BONUS = 50 } }, -- Reward Guide: 3 HP per MND at Zeta, about 2.5 MND per 1% Reward, 50% cap
            Charm = { Stats = { CHR = 1.5, CHARM_TIME = 0.8 } },                                          -- How-To: the artifact Charm +20 "doubles the duration"
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { ACC = 0.9, STR = 0.35, ATT = 0.4, HASTE_GEAR = 2, DUAL_WIELD = 0.8 } }, -- Equipment Guide: Dusk and Suppanomimi at 72; How-To: /DNC dual wield
            Ws_Default = { Stats = { STR = 1.1, ACC = 0.5, ATT = 0.5 } },                                 -- Vs. Maat: the Rampage set (Chivalrous Chain, Assault Earring, Amemet Mantle +1)
            Reward = { Stats = { MND = 1.2, REWARD_HP_BONUS = 3, REWARD_RECAST = 1 }, Caps = { REWARD_HP_BONUS = 50 } }, -- Reward Guide: Reward to the 50% cap, then MND without limit
        } },
        { To = 99, Tweaks = {
            Tp_Default = { Stats = { DEX = 0.45, STORETP = 1.8, ACC = 0.7, DOUBLE_ATTACK = 2, DUAL_WIELD = 0.8 } }, -- All Jobs Gear Sets: the "DEX and Store TP" TP set
            Ws_Default = { Stats = { STR = 1, DEX = 0.6, ALL_WSDMG_ALL_HITS = 3, TP_BONUS = 0.01 } },      -- All Jobs Gear Sets: Onslaught "DEX and Weapon Skill Damage"
            Reward = { Stats = { MND = 1.2, REWARD_HP_BONUS = 3, REWARD_RECAST = 1 }, Caps = { REWARD_HP_BONUS = 50 } }, -- Reward Guide and Community guide: "Reward Recast is very viable"
            ReadyPrecast = { Stats = { SIC_READY_RECAST = 5 } },                                          -- Community guide: Sic/Ready recast
        } },
    },
};
