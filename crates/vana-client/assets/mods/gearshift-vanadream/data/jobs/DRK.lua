--[[
    vanagear: Dark Knight.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Dark Knight: Guide by Raenryong, Logic of Equipment (2009, level 75), and
      the Dark Knight/Equipment Guide chart. His rules: "Haste > Accuracy > Attack > STR", with
      the ratios "1 haste = 2.5 acc on a TP build" and "1 acc = 3 atk on a TP build" (the
      weights below are those ratios); an accuracy ring, not a STR one; double attack next
      after haste and accuracy; Store TP "useful if it takes you one less hit to 100%, useless
      otherwise". Weaponskills: Guillotine "ACCURACY is your most important stat" to 95%, then
      attack, then STR; Spinning Slash STR first. The chart's pieces below 61 (Spike Necklace,
      Tilt, Life and Swift Belts, Sniper's Ring, Voyager Sallet, Haubergeon) are accuracy,
      attack and haste pieces, so his rules are applied to those bands too.
    - BG-wiki, Community Dark Knight Guide (July 2026, level 99): Store TP is central (Abyssal
      Beads +2, Ratri Cuisses so Insurgency reaches 4-5 hits); Last Resort with Desperate Blows
      reaches the ability haste cap, so gear haste is needed less; "DT-% gear often doubles as
      TP gear"; weaponskills want multi-hit at low TP and weaponskill damage at 1750+;
      Stun and Impact sets are INT, magic accuracy and fast cast; Drain gear is dark magic
      skill; Dread Spikes is HP and DEF. No idle section.
]]--

return {
    Fighter = true, Skills = { 'Dark Magic', 'Elemental Magic', 'Enfeebling Magic' },
    Tweaks = {
        Tp_Default = { Stats = { STORETP = 2, CRIT_DMG_INCREASE = 0.5 } },
        Dark = { Stats = { DARK = 1.5, ENHANCES_ABSORB_EFFECTS = 2 } },
        Drain = { Stats = { ENH_DRAIN_ASPIR = 3, DARK = 1 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.2, ATT = 0.4, STR = 0.3, DOUBLE_ATTACK = 1, STORETP = 0.5, CRIT_DMG_INCREASE = 0 } }, -- Raenryong: haste > acc > atk > STR; 1 haste = 2.5 acc = 7.5 atk; accuracy ring, not STR
        } },
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.2, ATT = 0.4, STR = 0.3, DOUBLE_ATTACK = 1, STORETP = 0.5, CRIT_DMG_INCREASE = 0 } }, -- Raenryong's ratios; the chart's Tilt, Life and Swift Belts, Sniper's Ring, Voyager Sallet
            Ws_Default = { Stats = { ACC = 0.9, ATT = 0.5, STR = 0.5 } },                                                 -- Raenryong, weaponskills: accuracy to 95%, then attack, then STR
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.2, ATT = 0.4, STR = 0.3, DOUBLE_ATTACK = 2, STORETP = 0.5, CRIT_DMG_INCREASE = 0 } }, -- Raenryong: double attack next after haste and accuracy (Brutal Earring); Store TP only if it saves a hit
            Ws_Default = { Stats = { ACC = 0.9, ATT = 0.6, STR = 0.5, MND = 0.1, DOUBLE_ATTACK = 0.5 } },                  -- Raenryong, Guillotine and Spinning Slash: accuracy to 95%, attack, STR, a little MND
        } },
        { To = 99, Tweaks = {
            Tp_Default = { Stats = { STORETP = 2, CRIT_DMG_INCREASE = 0.5, DOUBLE_ATTACK = 2, HASTE_GEAR = 2.5, ACC = 0.6 } }, -- Community guide: Store TP central; Desperate Blows covers the ability haste so gear haste matters less
            Tp_Hybrid = { Stats = { PDT = -4, MDT = -3 } },                                                                    -- Community guide: "DT-% gear often doubles as TP gear"
            Dark = { Stats = { DARK = 1.5, MACC = 1.5, INT = 0.6, FASTCAST = 0.5 } },                                           -- Community guide, Stun, Impact and enfeebling sets: INT, magic accuracy, fast cast
            Drain = { Stats = { ENH_DRAIN_ASPIR = 3, DARK = 1.2 } },                                                           -- Community guide, Drain: dark magic skill
            Ws_Default = { Stats = { STR = 1, ATT = 0.5, ALL_WSDMG_ALL_HITS = 3, STORETP = 0.5 } },                           -- Community guide: weaponskill damage at high TP, Store TP for the multi-hit ones at low TP
        } },
    },
    -- Ability sets come from what the server reads when each ability goes off. Souleater's
    -- script reads Muted Soul gear only; the Souleater effect gear the guide names is not read
    -- on the press, so it is not worn for it.
    Abilities = {
        ['Arcane Circle'] = { Stats = { ARCANE_CIRCLE_POTENCY = 2 } },
    },
};
