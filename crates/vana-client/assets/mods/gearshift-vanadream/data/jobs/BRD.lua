--[[
    vanagear: Bard - a support job (Lee, 22 Oct 2026).

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks. The
    fighting set comes in at 76, where the one guide that has a melee section is. Song is the
    buff songs; SongDebuff (Elegy, Lullaby, Requiem, Threnody, Finale) is the songs that must
    land, split off for this job.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Bard: Guide to Weapons and Armor (1-90), Bard/Equipment Guide, Bard Guide
      by Tattersail, How-To Guide: Bard, Endgame Barding Guide by Ghlin (2010), Itazura's Bard
      Puller Guide, and three thinner guides, all read to the end. Early: an instrument with
      +song and CHR, then MP and haste (Fiye); "CHR is not an important stat to bard in the
      early levels", an MP and enmity-down build for parties (Ghlin). From Elegy at 41 "you
      really need to worry about CHR": CHR "determines the success with which you can land a
      debuff song... nothing to do with buffing" (Tattersail, "Wind > Singing > CHR > -song
      casting time or Fast Cast"); Chanter's Staff at 40, Minstrel's Ring's casting time at
      50, Choral Cuffs at 60, haste belts for the recast. At 75 (Ghlin) buff potency is
      "purely from Singing Skill + Instrument Skill"; for resists "Macc = 1, Skill = .9, and
      CHR = .5" (about 500 skill plus magic accuracy and 100 CHR); precast gear worn only for
      the start of the cast, then swapped; "Finale's favorite stat is haste"; idle Terra's
      Staff and Vermillion Cloak.
    - BG-wiki, Community Bard Guide and Obamiwannabuffya (Funkworkz, 2022, level 99): song+
      first, duration second, debuff accuracy from CHR, singing, instrument skill and magic
      accuracy; real fast cast to 80 then song casting time; idle damage taken -50% then
      magic evasion; engaged is multi-attack and Store TP.
    - Earlier (M382): You Spoony Guide (FFXIAH 58).
]]--

return {
    Support = true, Skills = { 'Singing', 'Healing Magic', 'Enhancing Magic', 'Enfeebling Magic' },
    Tweaks = {
        Song = { Stats = { ALL_SONGS_EFFECT = 5, SONG_DURATION_BONUS = 2.5, SINGING = 0.6, CHR = 0.3, MACC = 0, STRING = 0.4, WIND = 0.4 } },
        Cure = { Stats = { ENMITY = -0.5 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Song = { Stats = { CHR = 0.3, MP = 0.05, ENMITY = -0.3, ALL_SONGS_EFFECT = 5 } },                 -- Fiye: an instrument with +song and CHR, then MP; Ghlin: "CHR is not an important stat early", MP and enmity down
            SongDebuff = { Stats = { CHR = 0.5, MACC = 1 } },
            Idle = { Stats = { MP = 0.03 } },
        } },
        { To = 60, Tweaks = {
            Song = { Stats = { SINGING = 0.8, WIND = 0.7, STRING = 0.5, CHR = 0.3, HASTE_GEAR = 0.3 } },     -- Tattersail: "Wind > Singing > CHR"; Fiye: haste secondary
            SongDebuff = { Stats = { CHR = 0.8, SINGING = 0.8, WIND = 0.8, MACC = 1 } },                    -- Ghlin: from Elegy at 41 CHR matters; Tattersail: CHR lands the debuff songs
            Song_Precast = { Stats = { SONG_SPELLCASTING_TIME = 3, FASTCAST = 2 } },                        -- the Weapons guide: Minstrel's Ring at 50; Tattersail: casting time or fast cast last
        } },
        { To = 75, Tweaks = {
            Song = { Stats = { SINGING = 1, WIND = 0.9, STRING = 0.9, CHR = 0, MACC = 0, HASTE_GEAR = 0.5 } }, -- Ghlin: buff potency is skill alone; haste for the Finale and Lullaby recasts
            SongDebuff = { Stats = { MACC = 1, SINGING = 0.9, WIND = 0.9, STRING = 0.9, CHR = 0.5 } },      -- Ghlin's resist gear: "Macc = 1, Skill = .9, and CHR = .5"
            Song_Precast = { Stats = { SONG_SPELLCASTING_TIME = 3, FASTCAST = 3 } },                        -- Ghlin's precast macro; Itazura: fast cast "same effect as SST"
        } },
        { To = 99, Tweaks = {
            Song_Precast = { Stats = { FASTCAST = 3, SONG_SPELLCASTING_TIME = 2, PDT = -0.2 } },             -- Community guide: real fast cast to 80 first, song casting time fills the gap
            Song = { Stats = { ALL_SONGS_EFFECT = 5, SONG_DURATION_BONUS = 2.5, PDT = -0.2, MEVA = 0.02 } }, -- Community guide: song+ first, duration second, spare slots damage taken and magic evasion
            SongDebuff = { Stats = { MACC = 1.2, SINGING = 0.9, STRING = 0.9, WIND = 0.9, CHR = 0.5 } },    -- Community guide: debuff accuracy from CHR, singing, instrument skill and magic accuracy
            Tp_Default = { Stats = { STORETP = 1.5, DOUBLE_ATTACK = 2, TRIPLE_ATTACK = 3, QUAD_ATTACK = 4 } }, -- Community guide, engaged: the only melee section, 99 only
            Idle = { Stats = { PDT = -3, MDT = -3, MEVA = 0.05, REFRESH = 1.5, REGEN = 0.5 } },              -- Community guide and Funkworkz: damage taken then magic evasion
        }, Modes = { 'Tp_Default', 'Ws_Default' } },
    },
};
