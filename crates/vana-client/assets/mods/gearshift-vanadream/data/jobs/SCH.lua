--[[
    vanagear: Scholar - a support job (Lee, 22 Oct 2026).

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks. No
    fighting set: melee is "a C+ at best" and the one TP set (BG-wiki, 99) is cape augments.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Scholar: The Flexible Mage and the Scholar/Equipment Guide chart, both
      read in full. A support caster from Arts at 10; nothing stated about gear below 52 but
      a note that SCH/NIN at 20 wields clubs for "extra INT & MND for soloing". The artifact
      set drives 52-60: Bracers' spell interruption, Loafers' cast and recast reduction "our
      own little Fast Cast", Pants and Gown +15 skill in their Arts, Mortarboard's Sublimation
      and INT "you'll be wearing this piece almost all the time"; healing "buff up on your MP
      pool for the most part"; enhancing skill "usually not worth it" except the barspells.
      61-75 the nuking set: "focus on INT, Magic Accuracy, Magic Attack and Elemental Magic
      skill"; the enfeebling set: skill (Enfeebling Torque), MND and INT, magic accuracy.
    - BG-wiki, Community Scholar Guide (2023-25, level 99): fast cast to 80%; cure potency
      50% and potency II 30%, Conserve MP, enmity down; Cursna from healing skill; Regen
      duration and potency; enhancing 500 skill for the barspells, duration for the rest;
      enfeebling magic accuracy and skill in Dark Arts; "low-tier nukes benefit from Magic
      Damage, high-tier nukes more from Magic Attack Bonus", accuracy to the 95% hit rate;
      burst sets by tier; idle Refresh and Sublimation sets with damage-taken pieces.
    - The Magic Burst pages: SCH's first burst gear is Catalyst at 69 and Static Earring at
      72; the job's own burst trait at 79, 89 and 99 and Mujin Band at 88 sit outside the
      40% gear cap.
    - Earlier (M382): A Scholar's Education (FFXIAH 41).
]]--

return {
    Support = true, Skills = { 'Healing Magic', 'Enhancing Magic', 'Enfeebling Magic', 'Elemental Magic', 'Dark Magic' },
    Tweaks = {
        Idle = { Stats = { REFRESH = 8, SUBLIMATION_BONUS = 2 } },
        Cure = { Stats = { HEALING = 0.8, ENMITY = 0 } },
        Nuke = { Stats = { MAGIC_DAMAGE = 1.5 } },
        -- Grimoire gear cuts the cast and recast of a spell that matches your Arts (battleutils.cpp reads
        -- GRIMOIRE_SPELLCASTING, a negative number, as the spell starts)
        Precast = { Stats = { GRIMOIRE_SPELLCASTING = -2 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Nuke = { Stats = { INT = 1.2 } },                                                              -- the chart's note: clubs for "extra INT & MND for soloing"
            Cure = { Stats = { MND = 0.6 } },
            Idle = { Stats = { REFRESH = 8, MP = 0.02, SUBLIMATION_BONUS = 0 } },                          -- no Refresh or Sublimation gear exists yet
        } },
        { To = 60, Tweaks = {
            Cure = { Stats = { MP = 0.05 } },                                                              -- The Flexible Mage, healing: "buff up on your MP pool for the most part", Ether and Serket Rings, Light Staff
            Precast = { Stats = { FASTCAST = 3 } },                                                        -- The Flexible Mage: the Loafers at 54, "our own little Fast Cast"
            Idle = { Stats = { SUBLIMATION_BONUS = 2, MP = 0.02 } },                                        -- The Flexible Mage: the Mortarboard at 60, worn "almost all the time"
            Nuke = { Stats = { INT = 1.2, ELEM = 0.5 } },                                                   -- The Flexible Mage: the Mortarboard's INT "crucial for your nukes", the Gown's skill in Dark Arts
        } },
        { To = 75, Tweaks = {
            Nuke = { Stats = { INT = 1.2, MATT = 2, MACC = 0.8, ELEM = 0.8 } },                             -- The Flexible Mage: "INT, Magic Accuracy, Magic Attack and Elemental Magic skill"
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 3, MATT = 1.2, INT = 0.8 } },                     -- the burst pages: Catalyst 69, Static Earring 72
            Enfeebling = { Stats = { ENFEEBLE = 1.5, MND = 0.7, INT = 0.7, MACC = 1.0 } },                   -- The Flexible Mage: skill (the torque), MND and INT, magic accuracy
            Enhancing = { Stats = { ENHANCE = 0.5 } },                                                     -- The Flexible Mage: enhancing skill "usually not worth it" except the barspells
        } },
        { To = 99, Tweaks = {
            Precast = { Stats = { FASTCAST = 3.5 } },                                                      -- Community guide: 80%
            Cure = { Stats = { CURE_POTENCY = 3.5, CURE_POTENCY_II = 2, CONSERVE_MP = 0.3, ENMITY = -0.4 } }, -- Community guide: 50% and 30%, Conserve MP, enmity down
            Cursna = { Stats = { HEALING = 1.5, ENHANCES_CURSNA = 3 } },                                    -- Community guide: healing skill
            Regen = { Stats = { REGEN_DURATION = 2.5, ENH_MAGIC_DURATION = 1.5 } },                          -- Community guide: duration and potency
            Enhancing = { Stats = { ENHANCE = 1.2, ENH_MAGIC_DURATION = 2.5 } },                             -- Community guide: 500 skill for the barspells, duration for the rest
            Enfeebling = { Stats = { MACC = 1.8, ENFEEBLE = 1.2, MND = 0.5, INT = 0.5 } },                   -- Community guide: magic accuracy and skill in Dark Arts
            Nuke = { Stats = { MATT = 2.2, MAGIC_DAMAGE = 1.5, MACC = 1.0, INT = 0.9 } },                     -- Community guide: magic damage for the low tiers, magic attack for the high, accuracy to 95%
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 4, MAGIC_BURST_BONUS_UNCAPPED = 4, MATT = 1.2, MACC = 0.6 } }, -- Community guide and the burst pages: the 40% gear cap, Burst II outside it
            Idle = { Stats = { REFRESH = 7, SUBLIMATION_BONUS = 2, PDT = -3, MDT = -2 } },                   -- Community guide: the Refresh and Sublimation idles with damage-taken pieces
        } },
    },
};
