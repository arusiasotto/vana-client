--[[
    vanagear: Dancer.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, The Street Performer: Dancer Equipment Guide for the Stingy of Wallet
      (Vyenpakakapaka, 2009, levels 1-75), the only source with a stated priority list. Pre-50:
      "1. Accuracy; 2. +DEX when +ACC isn't available; 3. +STR, +Attack to prevent daggers from
      hitting for 0; 4. Evasion/AGI for survivability when you steal hate". CHR gear "NOT
      important for your early levels". Post-50: "1. Accuracy & Haste Gear; 2. +STR, +Attack;
      3. Evasion/AGI" - TP in haste gear with accuracy in the slots that give no haste
      (Rapparee Harness, Swift Belt, Scorpion Harness "the most important piece", Walahra
      Turban, Etoile Tights, Dusk), Store TP from the Cobra set, Ecphoria Ring and White
      Tathlum, Brutal Earring, Suppanomimi. Weaponskills "in a combination of mostly
      Accuracy/DEX + some STR/Attack/CHR", because the job's weaponskills are all multi-hit.
      Also Dancer Equipment Guide by Eclipstic and Dancer: Guide to Weapons and Armor (piece
      tables, read in full).
    - BG-wiki, Community Dancer Guide (Aug 2026, level 99): TP sets by dual-wield haste level,
      accuracy to offset the off hand, Store TP for Terpsichore, crit for Twashtar; waltz
      potency caps at 50%; weaponskills are weaponskill damage and crit with DEX (Climactic
      Flourish forces a crit); steps want accuracy, Violent Flourish magic accuracy.
    - Earlier (M382): The Last Dance III (FFXIAH 373) for the ability sets below.
]]--

-- Waltzes, Steps, Sambas, Jigs and Flourishes: the server reads the stats below when they go
-- off (data\abilities.lua); waltz potency caps at 50% (both guides), and the step needs to land.
local waltz = { Stats = { WALTZ_POTENCY = 3, CHR = 0.5 }, Caps = { WALTZ_POTENCY = 50 } };
local step = { Stats = { ACC = 1 } };

return {
    Fighter = true,
    Tweaks = {
        Tp_Default = { Stats = { STORETP = 1.8, DEX = 0.5 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.5, DEX = 0.5, STR = 0.25, ATT = 0.25, STORETP = 0.5, HASTE_GEAR = 0 } }, -- Street Performer pre-50: accuracy, then DEX, then STR and attack so daggers do not hit for 0
            Idle = { Stats = { EVA = 0.1, DEF = 0.03 } },                                                           -- Street Performer pre-50 item 4: evasion and AGI for when hate is stolen
        } },
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.5, DEX = 0.4, STR = 0.25, ATT = 0.25, STORETP = 0.8 } },               -- Street Performer post-50: accuracy and haste first; Rapparee, Swift Belt, Life and Virtuoso Belts, Ecphoria Ring
            Tp_Acc = { Stats = { ACC = 2.2 } },                                                                       -- Street Performer: Scorpion Harness "the most important piece of gear in these levels"
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.2, STORETP = 1.2, DOUBLE_ATTACK = 1.5, DUAL_WIELD = 1.5, DEX = 0.4, STR = 0.25, ATT = 0.3 } }, -- Street Performer 65-75: the haste build (Walahra, Etoile Tights, Dusk), Cobra Store TP, Brutal Earring, Suppanomimi
            Ws_Default = { Stats = { ACC = 1.0, DEX = 0.8, STR = 0.4, ATT = 0.4, CHR = 0.2 } },                      -- Street Performer: mostly accuracy and DEX, some STR, attack and CHR; every dancer weaponskill is multi-hit
        } },
        { To = 99, Tweaks = {
            Tp_Default = { Stats = { DUAL_WIELD = 3, HASTE_GEAR = 2.5, ACC = 0.8, DEX = 0.5, STORETP = 1.8, DOUBLE_ATTACK = 1.5, CRITHITRATE = 1 } }, -- Community guide: delay capped by dual wield per haste level, accuracy for the off hand, Store TP, crit for Twashtar
            Ws_Default = { Stats = { DEX = 1.0, ALL_WSDMG_ALL_HITS = 3, CRITHITRATE = 1, CRIT_DMG_INCREASE = 0.8, ATT = 0.5, ACC = 0.4 } }, -- Community guide: weaponskill damage and crit with DEX (Rudra's Storm, Evisceration, Climactic Flourish)
        } },
    },
    Abilities = {
        ['Curing Waltz'] = waltz, ['Curing Waltz II'] = waltz, ['Curing Waltz III'] = waltz,
        ['Curing Waltz IV'] = waltz, ['Curing Waltz V'] = waltz, ['Divine Waltz'] = waltz, ['Divine Waltz II'] = waltz,
        ['Box Step'] = step, ['Quickstep'] = step, ['Stutter Step'] = step, ['Feather Step'] = step,
        ['Violent Flourish'] = { Stats = { MACC = 1 } },
    },
};
