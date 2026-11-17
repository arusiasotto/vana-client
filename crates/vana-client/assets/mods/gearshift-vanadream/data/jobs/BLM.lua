--[[
    vanagear: Black Mage - a support job (Lee, 22 Oct 2026): the nuker and burster.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks. No
    fighting set: the only melee section (BG-wiki, 99) is cape augments with no priorities.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Black Mage Equipment Guide by Eclipstic (1-90, read in full), by Cefeida
      (items only) and Black Mage: Guide to Playing the Job. Below 30 "most BLM gear is
      pretty basic": "low level INT boosts are great", Nunyenunc and Seer's Tunic for MP
      recovered while healing. At 51 the elemental staves "are the backbone of the black
      mage"; solo "skill was extremely important" (Shaman's Cloak), the artifact hands' "+15
      skill is the biggest boost you can get", the head "extra mp, extra INT and -4 enmity".
      61-75 INT peaks (Errant and Mahatma, Sorcerer's Belt "more INT than any other belt",
      the Obis), magic attack appears (Uggalepih Pendant, Bloodlapper hands), +8 magic
      accuracy ammo at 75 "so you can concentrate more MATK in other slots"; Demon's Cloak at
      68 the first Refresh ("idle in this"); Loquacious Earring and Rostrum Pumps for fast
      cast on the enfeebles.
    - FFXIclopedia Magic Burst, Magic Burst Bonus and Black Mage/Equipment Sets; BG-wiki
      Magic Burst and Magic Burst Bonus: a burst adds 30% and more with Sorcerer's Gloves,
      Static Earring and Catalyst; the burst gear timeline is Channeling Robe 34 (+2%),
      Catalyst 69, Static Earring and Sorcerer's Gloves 72, +1 at 75, +2 at 90; gear burst
      damage caps at +40%, Magic Burst Damage II (Mujin Band 88 and the 99 pieces) sits
      outside the cap.
    - BG-wiki, Community Black Mage Guide (Oct 2025, level 99): free nukes want magic attack
      and magic accuracy plus INT; bursts capped gear to 40%, then Burst II, then magic
      attack and accuracy; precast keeps 42 fast cast and fills the rest with damage taken
      and magic evasion; idle Refresh +14 with a separate damage-taken set for Mana Wall;
      enfeebling "magic accuracy and enfeebling skill"; Drain and Aspir potency, magic
      accuracy, dark skill.
    - Earlier (M382): The Black Sacrament (FFXIAH 297).
]]--

return {
    Support = true, Skills = { 'Elemental Magic', 'Enfeebling Magic', 'Dark Magic' },
    Tweaks = {
        Idle = { Stats = { REFRESH = 8 } },
        Nuke = { Stats = { MATT = 2.2, MACC = 0.8, INT = 0.8 } },
        Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 4, MAGIC_BURST_BONUS_UNCAPPED = 4.5 } },
        Enfeebling = { Stats = { ENFEEBLE = 1.5, MACC = 1.2 } },
    },
    -- The server reads no gear when Mana Wall goes off; for damage taken under it, /vg dt.
    Modes = { 'Macc' },
    Bands = {
        { To = 30, Tweaks = {
            Nuke = { Stats = { INT = 1.5, MATT = 1, MACC = 0.3, MP = 0.05 } },                        -- Eclipstic: the INT wands "great" until the staves; MP pieces
            Resting = { Stats = { MPHEAL = 3 } },                                                       -- Eclipstic: Nunyenunc "a wonderful tool for healing MP", Seer's Tunic
            Idle = { Stats = { REFRESH = 8, MP = 0.02 } },                                              -- no Refresh gear exists yet
        } },
        { To = 60, Tweaks = {
            Nuke = { Stats = { INT = 1.2, ELEM = 0.6, MATT = 1, MACC = 0.4, MP = 0.04 } },               -- Eclipstic: the elemental staves "the backbone"; solo skill; the artifact head's MP and INT
            Enfeebling = { Stats = { ENFEEBLE = 1.5, MACC = 1.0, INT = 0.5, MND = 0.4 } },              -- Eclipstic's enfeebling set: skill; sleep and bind for solo
            Resting = { Stats = { MPHEAL = 3 } },                                                       -- Eclipstic: Qiqirn Sash, Beak Necklace
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 2, INT = 1, MATT = 1 } },                     -- Magic Burst gear table: Channeling Robe at 34 is the only burst piece in this band
            Idle = { Stats = { REFRESH = 8, MP = 0.02 } },                                              -- the first Refresh body is 68
        } },
        { To = 75, Tweaks = {
            Nuke = { Stats = { INT = 1.2, MATT = 2, MACC = 0.7, ELEM = 0.4 } },                         -- Eclipstic 70-75: INT then magic attack; +8 magic accuracy ammo frees slots for attack
            Idle = { Stats = { REFRESH = 8 } },                                                         -- Eclipstic: Demon's Cloak at 68, "idle in this for the refresh"; Mahatma at 74
            Precast = { Stats = { FASTCAST = 2 } },                                                     -- Eclipstic: Loquacious Earring and Rostrum Pumps for fast cast on the enfeebles
            Enfeebling = { Stats = { ENFEEBLE = 1.5, MACC = 1.2, INT = 0.5 } },                          -- Eclipstic's enfeebling set
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 4, MATT = 1.2, INT = 0.8 } },                  -- Magic Burst pages: Catalyst 69, Static Earring and Sorcerer's Gloves 72 all count toward the 40% cap
        } },
        { To = 99, Tweaks = {
            Nuke = { Stats = { MATT = 2.4, MACC = 0.9, INT = 0.9 } },                                   -- Community guide, free nukes: magic attack, magic accuracy, INT
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 4, MAGIC_BURST_BONUS_UNCAPPED = 4.5, MATT = 1.2, MACC = 0.6 } }, -- Community guide and the burst pages: capped gear to 40%, Burst II outside it, then magic attack and accuracy
            Precast = { Stats = { FASTCAST = 2.5, PDT = -0.6, MEVA = 0.03 } },                           -- Community guide: 42 fast cast, the rest damage taken and magic evasion
            Idle = { Stats = { REFRESH = 8, PDT = -2, MDT = -1.5 } },                                    -- Community guide: the Refresh +14 idle, a separate damage-taken set
            Enfeebling = { Stats = { MACC = 1.6, ENFEEBLE = 1.5, INT = 0.4 } },                          -- Community guide: "magic accuracy and enfeebling skill"
            Drain = { Stats = { ENH_DRAIN_ASPIR = 3, DARK = 1, MACC = 1 } },                             -- Community guide: potency, magic accuracy, dark skill
        } },
    },
};
