--[[
    vanagear: Red Mage - a support job (Lee, 22 Oct 2026): the enfeebler, refresher and dispeller.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks. The
    fighting and weaponskill sets come in at 76, where the one guide that gives them is.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Red Mage Equipment Guide by Moonpirate (2008, 1-60 with later edits to
      78) and the Red Mage/Equipment Guide chart (1-85 with stats), both read in full. "INT
      and MND play an important role when it comes to a Red Mage's primary job: Enfeebling
      Magic", so INT, MND and enfeebling skill, "rarely wear MP+ gear"; wands per level for
      INT and MND; Enfeebling Earring at 35, Glamor Jupon at 50, Warlock's Tights' enhancing
      skill, Vermillion Cloak at 59 the first Refresh; 61-75 Spider and Enfeebling Torques
      "Enfeebling Skill +7, which is just beautiful", Avocat Pigaches, Bricta's Cuffs for the
      MND enfeebles, Nashira Seraweels, Dalmatica and Yigit for Refresh, Morrigan and Novio
      for the secondary nukes.
    - BG-wiki, Red Mage 101 (2017, marked outdated; role by level): enfeebling the main job
      from 11, Paralyze and Slow first; "many players stop meleeing" from 32; Dispel at 32,
      Convert at 40, Refresh at 41 "defines" the role; fast cast at 35 and 55; "magic bursts on
      skillchains are the main use" of nukes. Community Red Mage Guide (2023, level 99): for
      the skill-based enfeebles "skill is preferred over raw accuracy because skill also adds
      accuracy"; Sleep, Bind, Silence and Break want accuracy and duration; Paralyze II, Slow
      II and Addle II a full MND set, Blind II a full INT set; enhancing skill for the
      barspells and Stoneskin, duration for Haste and Blink under Composure; Refresh potency
      on the artifact body; a TP set at 99 (Crocea Mors and Daybreak, DEX, accuracy, attack,
      dual wield, damage taken).
    - The FFXIclopedia and BG-wiki Magic Burst pages: Channeling Robe 34, Catalyst 69 and
      Static Earring 72 count toward the 40% cap for RDM; the job's own burst trait at 85 and
      95 and Mujin Band at 88 sit outside it.
    - Earlier (M382): Jack of All Trades (FFXIAH 295). The server reads no gear when Saboteur
      goes off; its gear is weighed in the enfeebling set.
]]--

return {
    Support = true, Skills = { 'Healing Magic', 'Enhancing Magic', 'Enfeebling Magic', 'Elemental Magic', 'Dark Magic', 'Divine Magic' },
    Tweaks = {
        Idle = { Stats = { REFRESH = 8, REGEN = 2, PDT = -2, MDT = -2 } },
        Enfeebling = { Stats = { MACC = 2, ENFEEBLE = 1.2, MND = 0.8, ENHANCES_SABOTEUR = 1 } },
        Enhancing = { Stats = { ENH_MAGIC_DURATION = 2.5, ENHANCE = 1.2 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Enfeebling = { Stats = { ENFEEBLE = 1.2, MND = 0.9, INT = 0.9, MACC = 0.8 } },                   -- Moonpirate: INT, MND and enfeebling skill; wands for INT and MND
            Resting = { Stats = { MPHEAL = 2.5 } },                                                          -- the chart: Pilgrim's Wand the only MP-while-healing weapon
            Idle = { Stats = { REFRESH = 8, MP = 0.02, PDT = 0, MDT = 0 } },                                   -- no Refresh gear exists yet
        } },
        { To = 60, Tweaks = {
            Enfeebling = { Stats = { ENFEEBLE = 1.5, MND = 0.8, INT = 0.8, MACC = 0.8 } },                   -- Moonpirate: Enfeebling Earring, Glamor Jupon, Mohbwa Scarf, Penitent's Rope; Red Mage 101: the A+ skill
            Precast = { Stats = { FASTCAST = 3.5 } },                                                        -- Red Mage 101: fast cast at 35 and 55, the artifact hat +10%
            Enhancing = { Stats = { ENHANCE = 1.3, ENH_MAGIC_DURATION = 1.5 } },                              -- the chart: Warlock's Tights enhancing skill +15
            Idle = { Stats = { REFRESH = 6, PDT = 0, MDT = 0 } },                                              -- the chart: Vermillion Cloak at 59, the first Refresh
        } },
        { To = 75, Tweaks = {
            Enfeebling = { Stats = { ENFEEBLE = 1.8, MND = 0.8, INT = 0.8, MACC = 1.2 } },                   -- Moonpirate: the torques, Avocat Pigaches, Bricta's Cuffs; the chart: Nashira Seraweels
            Precast = { Stats = { FASTCAST = 3.5 } },                                                        -- the chart: Loquacious Earring at 75
            Idle = { Stats = { REFRESH = 8, PDT = -1, MDT = 0 } },                                             -- the chart: Dalmatica "frees up your head slot while still giving Refresh"
            Nuke = { Stats = { MATT = 1.6, INT = 0.9, MACC = 0.7 } },                                          -- the chart: Morrigan, Novio; Red Mage 101: nuking is secondary
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 3, MATT = 1.2, INT = 0.8 } },                        -- Red Mage 101: bursts are the main use; the burst pages: Channeling Robe, Catalyst, Static Earring
        } },
        { To = 99, Tweaks = {
            Enfeebling = { Stats = { ENFEEBLE = 1.4, MACC = 1.6, MND = 0.8, INT = 0.5 } },                   -- Community guide: skill over raw accuracy for the skill-based enfeebles; the MND set for Paralyze, Slow, Addle
            Macc = { Stats = { MACC = 2, ENFEEBLE = 0.8, INT = 0.4, MND = 0.4 } },                             -- Community guide: Sleep, Bind, Silence and Break want accuracy and duration
            Precast = { Stats = { FASTCAST = 3.5 } },                                                        -- Community guide: the hat +4, the cape +10
            Enhancing = { Stats = { ENHANCE = 1.4, ENH_MAGIC_DURATION = 2.5 } },                              -- Community guide: skill for the barspells and Stoneskin, duration for Haste and Blink under Composure
            Stoneskin = { Stats = { MND = 0.5, ENHANCE = 0.6 } },                                             -- Community guide: enhancing skill plus three times MND
            Idle = { Stats = { REFRESH = 7, PDT = -3, MDT = -2 } },                                            -- Community guide: the artifact body's Refresh potency; Malignance for damage taken
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 3, MAGIC_BURST_BONUS_UNCAPPED = 3, MATT = 1.2 } },  -- the burst pages: gear to the 40% cap, then Burst II; the job's trait at 85 and 95
            Tp_Default = { Stats = { DEX = 0.4, ACC = 0.6, ATT = 0.25, DUAL_WIELD = 1.5, PDT = -3, MDT = -2 } }, -- Community guide, TP at 99 only: Crocea Mors and Daybreak, DEX, accuracy, attack, dual wield, damage taken
        }, Modes = { 'Tp_Default', 'Tp_Hybrid', 'Ws_Default' } },
    },
};
