--[[
    vanagear: Thief.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Thief: Guide to Weapons and Armor (Andres and Falk, levels 1-75) and the
      Thief/Equipment Guide chart. Two sets from the start, "one focusing on Accuracy and
      Attack for normal melee attacks/TP gain, and another focusing on DEX and AGI for SATA";
      some defence to 29 for Sneak Attack hate, none needed after 30. 31-60 accuracy and haste
      for TP (Tilt, Life and Virtuoso Belts, Headlong and Swift Belts, Rapparee Harness, Tabin
      Boots); 61-75 Store TP, attack and haste (Cobra set, Dusk, Homam, Walahra Turban, Denali
      Bonnet, Assassin's Poulaines' triple attack, Brutal Earring, Suppanomimi) and DEX, STR and
      attack for the weaponskill macro (Hecatomb, Warwolf Belt, Cerberus Mantle, Rajas Ring).
    - BG-wiki, Community Thief Guide (Oct 2026, level 99): cap delay first (about 26% gear
      haste with the dual wield the magic haste needs), "after that, stack accuracy to the
      content's cap", "then stack Triple Attack and Store TP", with "+2~2.5 STP similar to 1%
      Triple Attack"; the tiebreaker is magic evasion or defence; weaponskills stack
      weaponskill damage with DEX (Rudra's, Mandalic, Savage Blade), Evisceration crit rate and
      damage; TH8 is the most that counts.
    - Earlier (M382): For the Shinies (FFXIAH 171). The server reads no gear when Sneak Attack
      or Trick Attack goes off, so no set is worn for them; Steal, Flee, Hide, Feint and the rest
      come from what the server reads on the press.
]]--

return {
    Fighter = true,
    Tweaks = {
        Tp_Default = { Stats = { TRIPLE_ATTACK = 3.5, TREASURE_HUNTER = 2 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.0, ATT = 0.5, DEX = 0.45, STR = 0.3, EVA = 0.1, TRIPLE_ATTACK = 0, TREASURE_HUNTER = 0 } }, -- Falk 1-30: the accuracy and attack set; Battle Gloves, Spike Necklace, Rajas and Courage rings
            Idle = { Stats = { DEF = 0.05, EVA = 0.05 } },                                          -- Falk 15-29: "must incorporate some defense gear" for Sneak Attack hate
        } },
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { ACC = 1.5, ATT = 0.5, DEX = 0.4, STORETP = 1.2, EVA = 0.05, TRIPLE_ATTACK = 0, TREASURE_HUNTER = 1 } }, -- Falk 31-60: accuracy belts for TP, haste belts, Rapparee Harness, Tabin Boots
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { STORETP = 1.8, TRIPLE_ATTACK = 3, ACC = 1.2, ATT = 0.5, DEX = 0.4, DUAL_WIELD = 2, TREASURE_HUNTER = 1.5 } }, -- Falk 61-75: Cobra set's Store TP and accuracy, Dusk, Homam and Walahra haste, Assassin's Poulaines, Brutal Earring, Suppanomimi
            Ws_Default = { Stats = { DEX = 1.0, STR = 0.5, ATT = 0.5 } },                          -- Falk 61-75: Hecatomb, Warwolf Belt, Cerberus Mantle, DEX rings for the weaponskill macro
        } },
        { To = 99, Tweaks = {
            Tp_Default = { Stats = { DUAL_WIELD = 3, ACC = 1.0, TRIPLE_ATTACK = 3.5, STORETP = 1.5, TREASURE_HUNTER = 2 } }, -- Community guide: delay cap, accuracy to the content's cap, then Triple Attack and Store TP (1% TA ~ 2-2.5 STP)
            Tp_Hybrid = { Stats = { PDT = -4, MDT = -3, MEVA = 0.05 } },                            -- Community guide: tiebreak on magic evasion or defence; glass-cannon sets run DT -10 to -25%
            Ws_Default = { Stats = { DEX = 1.0, ALL_WSDMG_ALL_HITS = 3, ATT = 0.5 } },               -- Community guide: weaponskill damage with DEX (Rudra's, Mandalic, Savage Blade)
        } },
    },
};
