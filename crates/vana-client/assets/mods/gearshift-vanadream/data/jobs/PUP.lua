--[[
    vanagear: Puppetmaster.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Puppetmaster Guide by Poof (2007), Puppetmasters Guide to Vanadiel
      (Wolfandre), The Definitive Solo Guide (Guwhenivar and others, 2010-11), Puppetmaster on
      a Budget (Zhecks), A guide for new Pups, Scoda's How To, all read in full. The automaton
      is the focus; solo "the master is the tank, you will want to gear up with as much
      Evasion + gear as possible"; "Evasion is key"; Battle Gloves at 14 "the most useful piece
      of hand gear", DEX or STR rings, Martial Arts at 25. 31-60 evasion pieces, Rajas Ring
      for Store TP, Swift Belt, Peacock Charm "main TP piece". 61-75 Pantin Taj "auto regen",
      Optical Hat, Chivalrous Chain and Potent Belt for the melee master, Boxer's Mantle.
    - BG-wiki, String Theory (Fabiano, 2022, level 99): master TP "Double/Triple/Quad Attack,
      Store TP, Accuracy/Attack, Martial Arts, and Haste"; the pet wants its haste cap (26%)
      and double attack, Store TP for ranged pets; pet weaponskills Bone Crusher double
      attack, Arcuballista, Daze and Chimera Ripper TP bonus, Asuran Fists accuracy and
      attack; the tank automaton wants damage taken and regen; Repair potency caps at +50%.
      Community Puppetmaster Guide: the same, with no idle section.
    - Earlier (M382): PUP Gearsets (FFXIAH 426) for the base pet weights below. Frames,
      heads, attachments and maneuvers are the job's centre and vanagear cannot choose them;
      the guides' setups per level range are kept in the M401 reading notes.
]]--

return {
    Fighter = true, Pet = true,
    Tweaks = {
        Tp_Default = { Stats = { MARTIAL_ARTS = 0.5 } },
        PetTP = { Pet = { HASTE_GEAR = 4, ACC = 0.8, DOUBLE_ATTACK = 2.2, STORETP = 0.8 } },
        PetAtk = { Pet = { PET_TP_BONUS = 0.02, TP_BONUS = 0.01 } },
        PetDT = { Pet = { REGEN = 1.5 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Tp_Default = { Stats = { ACC = 0.8, DEX = 0.4, STR = 0.25, MARTIAL_ARTS = 0.5 } },            -- Wolfandre: DEX or STR rings, Battle Gloves' accuracy
            Idle = { Stats = { EVA = 0.2 } },                                                             -- Wolfandre and the Solo Guide: "Evasion is key"; the master tanks solo
            Dt = { Stats = { EVA = 0.25 } },                                                              -- Solo Guide: "as much Evasion + gear as possible"
        } },
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { ACC = 0.9, DEX = 0.4, STORETP = 1.8, HASTE_GEAR = 2, MARTIAL_ARTS = 0.5 } }, -- Solo Guide: Rajas Ring's Store TP, Swift Belt; Wolfandre: Peacock Charm
            Idle = { Stats = { EVA = 0.25 } },                                                            -- Solo Guide: the evasion pieces are what there is
            Dt = { Stats = { EVA = 0.3 } },
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { ACC = 0.8, ATT = 0.35, DEX = 0.4, STR = 0.3, STORETP = 1.8, HASTE_GEAR = 3, MARTIAL_ARTS = 0.5 } }, -- Zhecks: Optical Hat, Potent Belt, Chivalrous Chain; Solo Guide: Swift Belt
            Idle = { Stats = { EVA = 0.25 } },                                                            -- Solo Guide: Boxer's Mantle
            PetDT = { Pet = { REGEN = 1.5 } },                                                            -- Wolfandre: Pantin Taj "auto regen, which is very handy"
        } },
        { To = 99, Tweaks = {
            Tp_Default = { Stats = { DOUBLE_ATTACK = 2.5, TRIPLE_ATTACK = 3, QUAD_ATTACK = 4, STORETP = 2, ACC = 0.7, ATT = 0.4, MARTIAL_ARTS = 0.5, HASTE_GEAR = 3 } }, -- String Theory: the master TP order
            PetTP = { Pet = { HASTE_GEAR = 4, STORETP = 1.5, DOUBLE_ATTACK = 2.2, ACC = 0.8 } },         -- String Theory: pet haste to its cap, Store TP, double attack
            PetAtk = { Pet = { PET_TP_BONUS = 0.02, TP_BONUS = 0.01, DOUBLE_ATTACK = 1.5, ACC = 0.8, ATT = 0.8 } }, -- String Theory: Daze and Arcuballista TP bonus, Bone Crusher double attack, Asuran Fists accuracy and attack
            PetDT = { Pet = { REGEN = 1.5, DMG = -6 } },                                                  -- String Theory: the pet tank set, damage taken and regen
        } },
    },
    -- Repair, Overdrive, Tactical Switch: their sets come from what the server reads on the press.
    -- The automaton's level is set as it is activated (petutils.cpp, AUTOMATON_LVL_BONUS); each Maneuver adds
    -- burden, and the overload threshold and suppression gear is read then (automaton_entity.cpp).
    -- (MANEUVER_BONUS is on gear but the server never reads it: M430.)
    Abilities = {
        ['Activate'] = { Stats = { AUTOMATON_LVL_BONUS = 3 } },
        ['Deus Ex Automata'] = { Stats = { AUTOMATON_LVL_BONUS = 3 } },
        ['Fire Maneuver'] = { Stats = { OVERLOAD_THRESH = 2, SUPPRESS_OVERLOAD = 3 } },
        ['Ice Maneuver'] = { Stats = { OVERLOAD_THRESH = 2, SUPPRESS_OVERLOAD = 3 } },
        ['Wind Maneuver'] = { Stats = { OVERLOAD_THRESH = 2, SUPPRESS_OVERLOAD = 3 } },
        ['Earth Maneuver'] = { Stats = { OVERLOAD_THRESH = 2, SUPPRESS_OVERLOAD = 3 } },
        ['Thunder Maneuver'] = { Stats = { OVERLOAD_THRESH = 2, SUPPRESS_OVERLOAD = 3 } },
        ['Water Maneuver'] = { Stats = { OVERLOAD_THRESH = 2, SUPPRESS_OVERLOAD = 3 } },
        ['Light Maneuver'] = { Stats = { OVERLOAD_THRESH = 2, SUPPRESS_OVERLOAD = 3 } },
        ['Dark Maneuver'] = { Stats = { OVERLOAD_THRESH = 2, SUPPRESS_OVERLOAD = 3 } },
    },
};
