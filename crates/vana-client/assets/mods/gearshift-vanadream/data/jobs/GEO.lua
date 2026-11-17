--[[
    vanagear: Geomancer - a support job (Lee, 22 Oct 2026).

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks. No
    fighting set: "semi gimp DD", no melee gear section in any guide.

    Read 22 Oct 2026 against:
    - BG-wiki, Geomancer's Thought Bubble (2019, level 99; the Community Geomancer Guide is
      an empty stub): levelled "mostly solo with Trusts"; at 99 buff with Indi-, debuff with
      Geo-, "nuking and spot healing are secondary". Geomancy: "the first priority is
      reaching 900 combined Geomancy and Handbell skill. Potency stops increasing past that
      point", then Conserve MP and Indicolure duration; only the highest Geomancy+ piece
      counts. The Luopan: keeping it alive is "the top idle goal"; it has -50% damage taken
      natively, pet damage taken caps at -87.5%, "so the GEO needs 37.5% more", with pet regen
      about 22; the older Refresh and Regen idles are rejected for it. Fast cast is capped
      from gear. Nuking is Idris and magic attack; bursts stack burst damage and magic attack.
    - FFXIclopedia Geomancer (the job page, read in full for when things arrive: Indi-Refresh
      30, Indi-Fury 34, Conserve MP 25, the burst trait 79) and Geomancy Skill: "Geomancer's
      base JSE gearsets aren't equippable until level 99" and every skill booster is 99-era,
      so no band below 99 has a stated priority: the base weights apply there.
    - The Magic Burst pages: Static Earring at 72 is the first burst gear GEO can wear; the
      40% gear cap; Mujin Band at 88 outside it.
    - Earlier (M382): Bubble Trouble (FFXIAH 112). Bolster, Life Cycle, Full Circle, Theurgic
      Focus and the rest: their sets come from what the server reads on the press.
]]--

return {
    Support = true, Pet = true, Skills = { 'Geomancy', 'Elemental Magic', 'Enfeebling Magic', 'Dark Magic', 'Healing Magic', 'Enhancing Magic' },
    Tweaks = {
        Idle = { Stats = { REFRESH = 7, REGEN = 3 } },
        Geomancy = { Stats = { GEOMANCY_SKILL = 1.5, HANDBELL_SKILL = 1.5, CONSERVE_MP = 0.3 } },
        Indi = { Stats = { GEOMANCY_SKILL = 1.5, HANDBELL_SKILL = 1.5, CONSERVE_MP = 0.3 } },
        PetDT = { Pet = { REGEN = 2, DMG = -5 } },
    },
    Bands = {
        { To = 30, Tweaks = {} },                                                                           -- no guide covers GEO gear below 99; the base weights apply
        { To = 60, Tweaks = {} },
        { To = 75, Tweaks = {} },
        { To = 99, Tweaks = {
            Geomancy = { Stats = { GEOMANCY_SKILL = 1.5, HANDBELL_SKILL = 1.5, CONSERVE_MP = 0.4, INDI_DURATION = 1.5 } }, -- Thought Bubble: 900 skill first, then Conserve MP and Indicolure duration
            Indi = { Stats = { GEOMANCY_SKILL = 1.5, HANDBELL_SKILL = 1.5, CONSERVE_MP = 0.4, INDI_DURATION = 2.5 } },     -- the same, Indicolure duration counting for Indi spells
            PetDT = { Pet = { DMG = -5, REGEN = 4 }, PetCaps = { DMG = -37.5 } },                          -- Thought Bubble: the Luopan has -50% natively and caps at -87.5%; pet regen about 22
            Idle = { Stats = { REFRESH = 2, REGEN = 0.5, PDT = -4, MDT = -3 } },                            -- Thought Bubble: the Refresh and Regen idles rejected, the Luopan first; 29% PDT and 18% MDT on the GEO
            Precast = { Stats = { FASTCAST = 3.5 } },                                                       -- Thought Bubble: fast cast capped from gear
            Nuke = { Stats = { MATT = 2, MACC = 0.8, INT = 0.8 } },                                          -- Thought Bubble: magic attack, Idris; a secondary role
            Burst = { Stats = { MAGIC_BURST_BONUS_CAPPED = 4, MAGIC_BURST_BONUS_UNCAPPED = 3, MATT = 1.2 } }, -- Thought Bubble: burst damage and magic attack; the burst pages: the 40% gear cap
        } },
    },
};
