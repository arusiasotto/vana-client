--[[
    vanagear: Ranger.

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Ranger Equipment Guide (1-75 chart with stats), Ranger: Hunter's Handbook
      by Tyson (2010) and Ranger Guide by Radiënt (Job, Stats and Equipment pages), all read
      to the end. "A Ranger's primary role is the damage dealer" through ranged attacks;
      "for EXP, you shouldn't be meleeing". Ranged accuracy is "without a doubt" the most
      important stat ("You don't hit, you don't deal damage"; "each bit has an unusually
      MASSIVE effect"; -10 for +20 ranged attack "not worth the sacrifice"); then STR, "a must
      for bow users", worth 3-4 ranged attack each and "the most important modifier when it
      comes to weapon skills"; ranged attack "you can ignore this when gearing up"; AGI gives
      accuracy at 2 to 1 and is a weaponskill modifier; crits "don't bother". Haste and slow
      do not touch ranged delay: only Velocity Shot, Snapshot and Rapid Shot do; Rapid Shot
      matters most on the slow weapons (Hunter's Beret at 54); the first Snapshot gear is
      Zha'Go's Barbut at 71 and the merit at 75. At 61-75 "start off with too much [ranged
      accuracy] and slowly build down, focussing on more Strength for your weapon skills".
    - BG-wiki, User:Favre/Sandbox/RangerGuide (level 99; the Community Ranger Guide is
      empty): Snapshot to its 70% cap then Rapid Shot; the shot AGI, Store TP, ranged
      accuracy and attack.
    - Earlier (M382): the RNG Guide by kunami (FFXIAH 365). Sharpshot, Camouflage, Scavenge,
      Shadowbind and Bounty Shot come from what the server reads on the press; it reads no
      gear for Barrage.
]]--

return {
    Fighter = true, Shooter = true,
    Tweaks = {
        Midshot = { Stats = { STORETP = 2.5 } },
    },
    -- Eagle Eye Shot is a ranged weaponskill with no stat modifier (job_utils\ranger.lua): ranged
    -- attack, accuracy and weaponskill damage are all it reads
    Abilities = {
        ['Eagle Eye Shot'] = { Stats = { RATT = 1, RACC = 1.5, ALL_WSDMG_ALL_HITS = 2, ALL_WSDMG_FIRST_HIT = 1.5, CRITHITRATE = 0.3 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Midshot = { Stats = { RACC = 2, STR = 0.5, RATT = 0.2, CRITHITRATE = 0, STORETP = 1 } },       -- Tyson: ranged accuracy first, STR next, ranged attack least; crits "don't bother"
            Preshot = { Stats = { RAPID_SHOT = 2, SNAPSHOT = 1 } },                                        -- Tyson: Rapid Shot from 15; no Snapshot gear before 71
        } },
        { To = 60, Tweaks = {
            Midshot = { Stats = { RACC = 2, STR = 0.6, RATT = 0.2, CRITHITRATE = 0, STORETP = 1.5 } },     -- Tyson: ranged accuracy's "MASSIVE effect"; Radiënt: ignore ranged attack
            Preshot = { Stats = { RAPID_SHOT = 2, SNAPSHOT = 1 } },                                        -- the Equipment Guide: Hunter's Beret at 54
            Ws_Default = { Stats = { RACC = 0.8, STR = 1, AGI = 0.5, RATT = 0.25, ACC = 0, DEX = 0 } },    -- Radiënt: STR the top weaponskill modifier, AGI 30% on Marksmanship; Tyson: Sidewinder needs accuracy
        } },
        { To = 75, Tweaks = {
            Midshot = { Stats = { RACC = 1.5, STR = 0.8, RATT = 0.2, CRITHITRATE = 0, STORETP = 2 } },     -- Radiënt: start with too much accuracy and build down toward STR
            Preshot = { Stats = { SNAPSHOT = 3, RAPID_SHOT = 2 }, Caps = { SNAPSHOT = 70 } },               -- the Equipment Guide: Zha'Go's Barbut at 71, the Snapshot merit at 75
            Ws_Default = { Stats = { RACC = 0.8, STR = 1, AGI = 0.5, RATT = 0.25, ACC = 0, DEX = 0 } },    -- Radiënt
        } },
        { To = 99, Tweaks = {
            Preshot = { Stats = { SNAPSHOT = 3, RAPID_SHOT = 1.5 }, Caps = { SNAPSHOT = 70 } },             -- Favre: Snapshot to 70, then Rapid Shot
            Midshot = { Stats = { AGI = 0.4, STORETP = 2.5, RACC = 1.5, RATT = 0.4 } },                      -- Favre: "AGI, STP, R.Acc/R.Att"
        } },
    },
};
