--[[
    vanagear: Warrior.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Warrior: Equipment Guide v2.0 (Vaala, 2006, levels 1-75). No stated priority
      line; the bands below 76 are read from which pieces he picks and why: accuracy first and
      early (Neckchopper, Vision Ring, Tilt Belt, Sniper's Rings, Life Belt), STR and attack
      beside it (Spike Necklace, Haubergeon), then from 61 double attack (Brutal Earring,
      Warrior's Cuisses), haste (Panther Mask, Dusk) and STR/attack/DEX pieces for the
      weaponskill macro (Hecatomb, gorgets, Warwolf Belt).
    - BG-wiki, Community Warrior Guide (2026, level 99): idle is damage taken to -50% then
      magic evasion; TP sets are haste to the 25% gear cap, double attack, Store TP, accuracy;
      weaponskills stack STR and weaponskill damage, attack until it is capped; the hybrid set
      is full Sakpata for damage taken.
    - Earlier (M382): The Parthenon (FFXIAH 35200) for the ability gear below.
]]--

return {
    Fighter = true,
    Tweaks = {
        Tp_Default = { Stats = { DOUBLE_ATTACK = 2.2, STORETP = 1.5 } },
        Dt = { Stats = { PDT = -12, HP = 0.06 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.0, ATT = 0.5, STR = 0.5, DEX = 0.4 } },      -- Vaala 1-30: accuracy on anything, STR rings, Lantern Shield's attack
            Idle = { Stats = { DEF = 0.05, EVA = 0.05 } },                                  -- Vaala 1-30: Bone set's evasion, otherwise plain DEF
        } },
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.5, ATT = 0.5, STR = 0.5, DEX = 0.4 } },      -- Vaala 31-60: accuracy is the bottleneck (Tilt Belt, Sniper's Rings, Life Belt, Peti)
            Tp_Acc = { Stats = { ACC = 2.0 } },                                             -- Vaala 43: Swordbelt, "if you need Acc or Attk"
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.0, ATT = 0.6, STR = 0.6, DEX = 0.4, STORETP = 1.5, DOUBLE_ATTACK = 2.5 } }, -- Vaala 61-75: Brutal Earring, Warrior's Cuisses, Dusk and Panther haste
            Ws_Default = { Stats = { STR = 1.2, ATT = 0.6, DEX = 0.5 } },                   -- Vaala 61-75: Hecatomb, gorgets, Warwolf Belt, STR earrings for the weaponskill macro
        } },
        { To = 99, Tweaks = {
            Tp_Default = { Stats = { DOUBLE_ATTACK = 2.2, STORETP = 1.5, ACC = 0.6 } },     -- Community guide: DA to 72-100%, gear haste 25%, Store TP, accuracy pieces
            Tp_Hybrid = { Stats = { PDT = -3, MDT = -2 } },                                 -- Community guide: the hybrid is full Sakpata
            Dt = { Stats = { PDT = -12, MEVA = 0.15 } },                                    -- Community guide: DT -50% first, magic evasion second
            Ws_Default = { Stats = { STR = 1.2, ALL_WSDMG_ALL_HITS = 3, ATT = 0.5 } },      -- Community guide: "as much STR and Weapon Skill Damage as possible", attack until capped
        } },
    },
    Abilities = {
        ['Berserk'] = { Stats = { BERSERK_DURATION = 1, BERSERK_POTENCY = 2 } },
        ['Warcry'] = { Stats = { WARCRY_DURATION = 1 } },
        ['Aggressor'] = { Stats = { AGGRESSOR_DURATION = 1 } },
        ['Blood Rage'] = { Stats = { ENHANCES_BLOOD_RAGE = 1 } },
        ['Restraint'] = { Stats = { ENHANCES_RESTRAINT = 1 } },
    },
};
