--[[
    vanagear: Summoner - a support job (Lee, 22 Oct 2026) whose avatar is the damage dealer.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks. No
    fighting set for the master: no guide gives melee priorities ("don't be afraid when
    soloing to help your pet out with some melee" is all).

    Read 22 Oct 2026 against:
    - FFXIclopedia, Summoner Equipment Guide by Alamoth (1-75, per slot with reasons) and
      Kweh's guide to playing summoner and gear selection (level 90 era), both read in full.
      "+MP > Summoning Magic until 50"; Carbuncle early for the lowest perpetuation, Carbuncle
      Mitts at 20 halve it; Pilgrim's Wand for MP while healing. From 50 "start building a
      max Summoning Magic set"; the elemental staves at 51 cut the matching avatar's
      perpetuation, Dark staff first; the Austere set at 50 for blood pact delay, perpetuation
      and skill; Vermillion Cloak at 59 the first Refresh. 61-75 the relic pieces combine MP
      with perpetuation, blood pact delay and avatar attack, accuracy and crit; Bahamut's
      Staff +5 skill; Yinyang Robe, Yigit and Dalmatica for Refresh; Astral Pot and Sacrifice
      Torque for avatar magic attack and attack.
    - BG-wiki, The Heretical Art: Comprehensive Summoner Guide and its Equipment page (2017-
      2022, level 99): "primarily a damage dealer with support duties"; idle skill about 537,
      perpetuation -14 (the cap), Refresh 10-11, haste; blood pact delay I capped at -15 s and
      II at -6 s with skill for the Favor tiers; physical pacts accuracy, attack, pact damage,
      double attack, crit; magical pacts magic attack, magic damage, magic accuracy, pact
      damage; enfeebling pacts skill and magic accuracy; enhancing pacts skill; fast cast 80%
      on /RDM; cure potency 50%.
    - The Magic Burst pages: pacts can burst and SMN can wear Channeling Robe, Catalyst and
      Static Earring, but no SMN guide gives burst gear, so no Burst set.
    - Earlier (M382): the Summoner Guide by Lunareticc (FFXIAH 245).
]]--

return {
    Support = true, Pet = true, Skills = { 'Healing Magic', 'Enhancing Magic' },
    Modes = { 'BPDelay', 'BPWard' },
    Tweaks = {
        Idle = { Stats = { REFRESH = 8, PERPETUATION_REDUCTION = 6 } },
        PetTP = { Stats = { PERPETUATION_REDUCTION = 4, REFRESH = 3 } },
        PetAtk = { Stats = { BP_DAMAGE = 3 }, Pet = { ATT = 1, ACC = 0.5, CRITHITRATE = 1 } },
        PetMab = { Stats = { BP_DAMAGE = 3 }, Pet = { MATT = 2, MACC = 0.5 } },
        PetAcc = { Stats = { SUMMONING = 1, BLOOD_BOON = 0.5 }, Pet = { MACC = 2 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Idle = { Stats = { MP = 0.05, PERPETUATION_REDUCTION = 4, REFRESH = 8 } },                      -- Kweh: "+MP > Summoning Magic until 50"; Alamoth: Carbuncle Mitts at 20
            Resting = { Stats = { MPHEAL = 3 } },                                                           -- Alamoth: Pilgrim's Wand
            BPWard = { Stats = { SUMMONING = 0.5 } },                                                       -- Kweh: MP over skill until 50
        } },
        { To = 60, Tweaks = {
            BPWard = { Stats = { SUMMONING = 1.5 } },                                                       -- Kweh: from 50 "a max Summoning Magic set"; The Heretical Art 33-56: "skill and MP"
            Idle = { Stats = { REFRESH = 6, PERPETUATION_REDUCTION = 6, MP = 0.04 } },                       -- Alamoth: the staves and Austere set at 50-51; Vermillion Cloak at 59
            BPDelay = { Stats = { BP_DELAY = 3, BP_DELAY_II = 3 } },                                         -- Alamoth: the Austere set's blood pact delay
        } },
        { To = 75, Tweaks = {
            Idle = { Stats = { REFRESH = 8, PERPETUATION_REDUCTION = 6 } },                                  -- Alamoth: Yigit and Dalmatica Refresh; the relic set and Bahamut's Staff perpetuation
            BPDelay = { Stats = { BP_DELAY = 3, BP_DELAY_II = 3 } },                                         -- Alamoth: the relic set at 71-75, Yinyang Robe
            BPWard = { Stats = { SUMMONING = 1.5, BLOOD_BOON = 0.5 } },                                      -- Alamoth: Bahamut's Staff +5 skill, Evoker's Ring, Astute Cape
            PetAtk = { Pet = { ATT = 1, ACC = 0.6 } },                                                      -- Alamoth: Sacrifice Torque, the relic feet and bracers
            PetMab = { Pet = { MATT = 2 } },                                                                -- Alamoth: Astral Pot
        } },
        { To = 99, Tweaks = {
            Idle = { Stats = { REFRESH = 8, PERPETUATION_REDUCTION = 6, SUMMONING = 0.5, HASTE_GEAR = 1 } },   -- The Heretical Art, idle: skill about 537, perpetuation -14, Refresh 10-11, haste
            BPDelay = { Stats = { BP_DELAY = 3, BP_DELAY_II = 3, SUMMONING = 0.5 } },                         -- The Heretical Art: delay I capped at -15 s, II at -6 s, skill for the Favor tiers
            PetAtk = { Stats = { BP_DAMAGE = 3 }, Pet = { ATT = 1, ACC = 0.6, DOUBLE_ATTACK = 1, CRITHITRATE = 1 } }, -- The Heretical Art, physical pacts: accuracy, attack, pact damage, double attack, crit
            PetMab = { Stats = { BP_DAMAGE = 3 }, Pet = { MATT = 2, MACC = 0.5 } },                           -- The Heretical Art, magical pacts: magic attack, magic damage, magic accuracy, pact damage
            PetAcc = { Stats = { SUMMONING = 1 }, Pet = { MACC = 2 } },                                      -- The Heretical Art, enfeebling pacts: skill and magic accuracy
            BPWard = { Stats = { SUMMONING = 1.5, BLOOD_BOON = 0.5 } },                                      -- The Heretical Art, enhancing pacts: skill 595
            Precast = { Stats = { FASTCAST = 3.5 } },                                                       -- The Heretical Art: 80% on /RDM
            Cure = { Stats = { CURE_POTENCY = 3.5 } },                                                      -- The Heretical Art: 50%
        } },
    },
    Abilities = {
        ['Elemental Siphon'] = { Stats = { SUMMONING = 1, ENHANCES_ELEMENTAL_SIPHON = 2 } },
    },
};
