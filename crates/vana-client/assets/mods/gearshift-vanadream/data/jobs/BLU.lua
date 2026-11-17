--[[
    vanagear: Blue Mage - a unique job (Lee, 22 Oct 2026): as much about which spells are
    set as what is worn.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks. The
    spell sets the guides recommend per level are in the M401 reading notes; vanagear cannot
    set spells.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Blue Mage Gear Guide by Aislin (1-75 by slot), Blue Mage Damage Guide
      (Zalora), Blue Mage: Endgame Gear Guide (Bryeen, 2008-10), Guide to Playing the Job,
      Scryes Imperial Blue Mage Guide, Immortals Tome by Tyson, all read to the end. "For
      the most part while leveling up, you will want to be geared as a physical DD." Physical
      blue magic: STR first ("every 4 STR above the target's VIT is a damage tier"), "Attack
      does not affect the damage of physical Blue Magic", Blue Magic skill raises damage and
      accuracy (base = skill x 0.22 + 3, so a skill point is worth about 0.9 of a STR point),
      DEX on Frenetic Rip, Hysteric Barrage and Disseverment, VIT and defence on Cannonball;
      low-level spells "miss a lot". Magical blue magic: INT raises damage and accuracy, MND
      for the debuffs and heals; the Damage Guide and the Endgame guide disagree on whether
      magic attack helps. Melee: "Haste is the best way to increase your melee damage,
      Accuracy is best put in slots where you can't obtain haste, and Attack is great for
      when you can't get accuracy" (Scryes); Suppanomimi and Brutal Earring at 70-75. Magic
      accuracy for Head Butt (Mirage Shalwar, Denali Gamashes). Magic Fruit and Wild Carrot
      take VIT and cure potency.
    - BG-wiki, Community Blue Mage Guide and Azure Tomes (Sabishii), level 99: STR then DEX
      for physical, INT and magic attack for magical, White Wind takes cure potency and max
      HP with MND no effect; magic accuracy for the debuffs.
    - The Magic Burst pages: BLU can wear Channeling Robe at 34 and Static Earring at 72;
      Tyson: Burst Affinity "not very helpful" at 25 since most spells are area; the job's
      own burst trait at 78, 90 and 99 and Magic Burst Damage II sit outside the 40% cap.
    - Earlier (M382): The Beast Within (FFXIAH 25) for the idle below. The server reads no
      gear when Burst or Chain Affinity goes off, so no set is worn for them.
]]--

return {
    Fighter = true, Skills = { 'Blue Magic', 'Healing Magic', 'Enhancing Magic' },
    Tweaks = {
        Idle = { Stats = { PDT = -4, MDT = -3, MEVA = 0.08 } },
        BlueMagical = { Stats = { MAGIC_DAMAGE = 1.2 } },
        Cure = { Stats = { BLUE = 0.3 } },
    },
    Modes = { 'Macc' },
    Bands = {
        { To = 30, Tweaks = {
            BluePhysical = { Stats = { STR = 1, DEX = 0.5, ACC = 1, ATT = 0, BLUE = 0.5 } },           -- the Damage Guide: STR first, attack does nothing; Aislin: the low spells "miss a lot"
            Tp_Default = { Stats = { HASTE_GEAR = 3, ACC = 1.2, ATT = 0.3 } },                         -- Scryes: haste, then accuracy, attack last
        } },
        { To = 60, Modes = { 'Burst' }, Tweaks = {
            BluePhysical = { Stats = { STR = 1, DEX = 0.7, ACC = 0.8, ATT = 0, BLUE = 0.9 } },         -- the Damage Guide's formula: skill and STR both move the base damage; Magus Jubbah +15 skill at 58
            Tp_Default = { Stats = { HASTE_GEAR = 3, ACC = 1, ATT = 0.3 } },                           -- Scryes; the Endgame guide's Diabolos's Earring note
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 2, INT = 0.7, MACC = 0.3 } },               -- the burst pages: Channeling Robe at 34; Tyson: seldom bursting yet
            Cure = { Stats = { MND = 0.5, VIT = 0.4, CURE_POTENCY = 3 } },                             -- Playing the Job: Magic Fruit and Wild Carrot take VIT and cure potency; Aislin: Justice Badge
        } },
        { To = 75, Modes = { 'Burst' }, Tweaks = {
            BluePhysical = { Stats = { STR = 1, DEX = 0.9, ACC = 0.8, ATT = 0, BLUE = 0.9 } },         -- the Endgame guide: the big three use DEX as much as STR
            BlueMagical = { Stats = { INT = 1, MATT = 1, MACC = 0.7, BLUE = 0.9 } },                    -- the Damage Guide and Immortals Tome: INT and skill; magic attack disputed
            Tp_Default = { Stats = { HASTE_GEAR = 3, ACC = 1, ATT = 0.3, DUAL_WIELD = 1 } },            -- the Endgame guide: Suppanomimi and Brutal Earring; Scryes
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 3, INT = 0.7, MACC = 0.3 } },               -- the burst pages: Static Earring at 72; Burst Affinity doubles the INT correction
            Macc = { Stats = { MACC = 2, BLUE = 0.9 } },                                                -- the Endgame guide: magic accuracy for Head Butt; the Damage Guide: skill lowers resists
        } },
        { To = 99, Modes = { 'Burst' }, Tweaks = {
            BluePhysical = { Stats = { STR = 1, DEX = 0.7, ACC = 0.5, ATT = 0 } },                     -- Azure Tomes: STR then DEX; attack not used
            BlueMagical = { Stats = { MATT = 2, INT = 1 } },                                            -- Azure Tomes: INT and magic attack
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 4, MAGIC_BURST_BONUS_UNCAPPED = 4, MACC = 0.3 } }, -- the burst pages: the 40% gear cap, the trait and Damage II outside it
            Macc = { Stats = { MACC = 2 } },                                                            -- Community guide: the magic accuracy set for the debuffs
            Cure = { Stats = { CURE_POTENCY = 3, HP = 0.02, MND = 0 } },                                -- Azure Tomes: White Wind takes cure potency and max HP, MND no effect
        } },
    },
};
