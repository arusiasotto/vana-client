--[[
    vanagear: Ninja - the blink tank (Lee, 22 Oct 2026).

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks. The
    fighting set (Tp_Default, "Engaged") is the tanking set from 31 to 75; the damage swaps
    are the weaponskill sets, as the guides have them.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Ninja - Doing it right (2013, levels 1-99, "NIN found its role as a tank.
      And this is how I've treated it"): 1-30 "accuracy will be a pretty big issue", a STR+2
      and a DEX+2 ring, other slots "for defense, evasion or HP", evasion gear from 20; Ninjutsu
      skill capped so casts are not interrupted. 31-60 Utsusemi: Ni at 37 "completely changes
      the feel of NIN"; haste "lowers recast timers on magic spells, which is defensively why
      it's so important", haste gear on as the cast finishes; enmity gear from the 40s; Ninja
      Hatsuburi swapped in to land the enfeebles. 61-75 Arhat's Gi +1 and Jinpachi +1 "for the
      physical damage reduction stat", hands and legs for enmity, "attack speed is your best
      friend... wherever you can get haste gear, slap that on" (20% gear haste is a 28 s
      Utsusemi with the spell); the weaponskill swap is STR and attack, DEX and accuracy so all
      three hits of Blade: Jin land. 76-99 the enmity cap matters when tanking; fast cast on
      before the cast, haste on as it finishes; NIN/DRK "prioritized by Haste, Fast Cast, then
      enmity"; DD: "Haste, Double Attack, and then Dual Wield", more dual wield past the delay
      floor lowers TP gain. Also Dibble's Essential Ninja Equipment Guide (2012), the Ninja
      Equipment Guide chart and the How-To Guide, all read in full.
    - BG-wiki, The Silent Silhouette and Finans Gearset Guides/Ninja (2026, level 99): NIN is
      "a mid-tier damage dealer with defensive and utility strengths", not the main tank in
      every fight; Utsusemi midcast "FC +40, -50% DT" and "FC +56"; "high DT in all my sets";
      an idle evasion set; Hachiya pieces for ninjutsu magic accuracy; Store TP at the haste
      cap; weaponskills: Shun DEX and double attack, Ten and Chi STR and weaponskill damage,
      Hi AGI and weaponskill damage, Jin crit.
    - Earlier (M382): the NIN Guide by Kincard (FFXIAH 35).
]]--

return {
    Fighter = true, Tank = true, Shooter = true, Skills = { 'Ninjutsu' },
    Tweaks = {
        Tp_Default = { Stats = { DAKEN = 0.5 } },                                                -- Daken throws the shuriken in the ammo slot as you swing (attackround.cpp reads DAKEN)
        Tp_Hybrid = { Stats = { PDT = -3.5, MDT = -2.5 } },
        Ninjutsu = { Stats = { MATT = 2, MACC = 1, NINJUTSU = 0.8, NIN_NUKE_BONUS_INNIN = 1 } },
    },
    Modes = { 'Macc', 'Burst' },
    Bands = {
        { To = 30, Tweaks = {                                                                        -- a melee that is already asked to tank from 12
            Tp_Default = { Stats = { ACC = 1.0, STR = 0.4, DEX = 0.5, EVA = 0.1, HP = 0.02 } },      -- Doing it right 1-30: accuracy, a STR and a DEX ring, the rest "defense, evasion or HP"
            Idle = { Stats = { EVA = 0.15, HP = 0.02, DEF = 0.05 } },                                -- Doing it right 1-30
            Dt = { Stats = { EVA = 0.2, HP = 0.03, DEF = 0.05 } },                                   -- Doing it right 20-29: "start equipping your NIN for evasion"
            Ninjutsu = { Stats = { NINJUTSU = 1, MACC = 1, MATT = 0.5 } },                            -- Doing it right: skill capped, fewer interruptions
        } },
        { To = 60, Tweaks = {                                                                        -- tank: Utsusemi: Ni at 37
            Tp_Default = { Stats = { HASTE_GEAR = 3, ENMITY = 0.5, EVA = 0.15, PDT = -2, MDT = -1.5, ACC = 0.9, DUAL_WIELD = 0.6 } }, -- Doing it right 31-60: haste for the recast, enmity from the 40s, evasion, accuracy for Yonin
            Utsusemi = { Stats = { HASTE_GEAR = 3, PDT = -0.5 } },                                   -- Doing it right 50-59: haste on as the cast finishes cuts the recast
            Tp_Hybrid = { Stats = { ENMITY = 0.5, EVA = 0.15, PDT = -3.5, MDT = -2.5, ACC = 0.9 } },  -- the same with more damage taken
            Dt = { Stats = { EVA = 0.25, HP = 0.03, DEF = 0.05 } },                                  -- Doing it right: Ninja Hakama and the evasion pieces
            NinjutsuDebuff = { Stats = { MACC = 2, NINJUTSU = 2 } },                                 -- Doing it right: Ninja Hatsuburi swapped in to land the enfeebles
        } },
        { To = 75, Tweaks = {                                                                        -- tank; the damage swap is the weaponskill
            Tp_Default = { Stats = { HASTE_GEAR = 3.5, ENMITY = 0.6, EVA = 0.15, PDT = -3, MDT = -2, ACC = 0.8, DOUBLE_ATTACK = 1, DUAL_WIELD = 0.8 } }, -- Doing it right 61-75: "attack speed is your best friend", Arhat's damage reduction, enmity hands and legs
            Utsusemi = { Stats = { HASTE_GEAR = 4, FASTCAST = 2, PDT = -0.5 } },                     -- Doing it right: 28 s Utsusemi with haste
            Tp_Hybrid = { Stats = { PDT = -4, MDT = -3, ENMITY = 0.6, EVA = 0.15 } },                -- Doing it right: Arhat's Gi +1 and Jinpachi +1
            Dt = { Stats = { PDT = -6, MDT = -4, EVA = 0.25, HP = 0.03 } },                          -- Doing it right: "the physical damage reduction stat"
            Ws_Default = { Stats = { STR = 1.2, ATT = 0.6, DEX = 0.8, ACC = 0.5 } },                 -- Doing it right 70-75: STR and attack to hit harder, DEX and accuracy so all three hits land
        } },
        { To = 99, Tweaks = {                                                                        -- a damage dealer that tanks when asked; NIN/DRK the enmity tank
            Utsusemi = { Stats = { UTSUSEMI_BONUS = 10, FASTCAST = 3, HASTE_GEAR = 3, PDT = -1, MDT = -0.5 } }, -- Doing it right, Silhouette, Finans: fast cast before, haste as it finishes, "FC +40, -50% DT"
            Precast = { Stats = { FASTCAST = 3 } },                                                  -- Finans: fast cast for the shadows
            Tp_Hybrid = { Stats = { PDT = -4, MDT = -3, ENMITY = 0.8, HASTE_GEAR = 3 } },            -- Doing it right: the enmity cap matters when tanking; haste, fast cast, then enmity
            Dt = { Stats = { PDT = -12, MDT = -10, EVA = 0.15, HP = 0.04, MEVA = 0.1 } },            -- Silhouette: "high DT in all my sets"
            Idle = { Stats = { EVA = 0.2, MEVA = 0.1, PDT = -3, MDT = -2 } },                        -- Silhouette: the idle evasion set
            NinjutsuDebuff = { Stats = { MACC = 2, NINJUTSU = 1.5 } },                               -- Silhouette: Hachiya pieces for enfeebling magic accuracy
            Tp_Default = { Stats = { HASTE_GEAR = 4, DOUBLE_ATTACK = 3, DUAL_WIELD = 0.8, TRIPLE_ATTACK = 3, STORETP = 1.5 } }, -- Doing it right and Silhouette, DD: "Haste, Double Attack, and then Dual Wield"; Store TP at the haste cap
            Ws_Default = { Stats = { STR = 1, DEX = 0.8, ATT = 0.5, CRITHITRATE = 1, CRIT_DMG_INCREASE = 1.5, ALL_WSDMG_ALL_HITS = 3 } }, -- Silhouette and Finans: Jin crit; Ten and Chi STR and weaponskill damage; Shun DEX and double attack
        } },
    },
    -- Mijin Gakure: the reraise the server reads when it kills you (char_entity.cpp, MIJIN_RERAISE)
    Abilities = {
        ['Mijin Gakure'] = { Stats = { MIJIN_RERAISE = 10 } },
    },
};
