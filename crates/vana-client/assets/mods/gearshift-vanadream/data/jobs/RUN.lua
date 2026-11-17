--[[
    vanagear: Rune Fencer - a tank (Lee, 22 Oct 2026).

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks.

    Read 22 Oct 2026 against:
    - FFXIclopedia, Rune Fencer: Strengths and Weaknesses and A guide to playing the Job (both
      marked outdated), the job page for when each tool arrives. No wiki gives RUN gear by
      level below 99: "Rune Fencer's base JSE gearsets aren't equippable until level 99". What
      there is: "a solid tanking set consisting of Evasion, Physical Damage Taken-%, and
      Enmity+ equipment on-hand for when Battuta drops and for when Swordplay is active";
      "extremely high parrying skill"; "has trouble maintaining enmity"; Inquartata at 15,
      Swordplay 20, Max HP Boost from 20, Battuta at 75. So the 1-30 band is empty and the
      base weights apply; 31-75 is that one sentence.
    - BG-wiki, Community Rune Fencer Guide, Rune Fencer End-Game Tank Guide (Shiraj, 2020)
      and Quiescence (Ruaumoko, 2022), level 99: "Hybrid Tank with emphasis on magic damage
      mitigation"; physical PDT then DT, magic MDT then DT, "aim to cap Damage Taken-%";
      magic evasion from the runes; parrying "completely negates damage", Inquartata 31%
      from gear and 81% under Battuta; enmity sets to +121 with care for HP dips; spell
      interruption to -102%, fast cast to 80%, Phalanx+ sets, a 50% cure set. DD, named as a
      side role for Omen only: an accurate five-hit build with Store TP 70, double attack 25%,
      triple attack 13%; Resolution STR, accuracy, attack, double attack; Dimidiation DEX,
      accuracy, attack, weaponskill damage.
    - Earlier (M382): Destiny's Device (FFXIAH 397). Swordplay, Liement, Vallation, Valiance,
      Pflug, Rayke, Gambit and Battuta: their sets come from what the server reads on the press.
]]--

return {
    Fighter = true, Tank = true, Skills = { 'Enhancing Magic', 'Divine Magic' },
    Tweaks = {
        Idle = { Stats = { PDT = -5, MDT = -5, HP = 0.04, MEVA = 0.1, ENMITY = 0.2 } },
        Dt = { Stats = { MEVA = 0.15, HP = 0.06, ENMITY = 0.3 } },
        Tp_Default = { Stats = { PDT = -2, MDT = -2, ENMITY = 0.5, PARRY = 0.3, INQUARTATA = 1 } },
    },
    Bands = {
        { To = 30, Tweaks = {} },                                                                        -- no guide gives RUN gear by level below 99; the base weights apply
        { To = 60, Tweaks = {
            Tp_Default = { Stats = { EVA = 0.15, PDT = -3, ENMITY = 0.5, PARRY = 0.3, INQUARTATA = 1 } }, -- Strengths and Weaknesses: "Evasion, Physical Damage Taken-%, and Enmity+" with Swordplay up; Inquartata from 15
            Idle = { Stats = { HP = 0.04, MEVA = 0.1 } },                                                 -- the Max HP Boost traits; "high elemental defense at mid to later levels"
        } },
        { To = 75, Tweaks = {
            Tp_Default = { Stats = { EVA = 0.15, PDT = -3, ENMITY = 0.5, PARRY = 0.4, INQUARTATA = 1.2 } }, -- Battuta at 75 makes parrying the physical defence
            Dt = { Stats = { MEVA = 0.15, HP = 0.06, ENMITY = 0.3 } },                                    -- magic defence is the job's strength; it is hard to hold enmity
        } },
        { To = 99, Tweaks = {
            Idle = { Stats = { PDT = -5, MDT = -5, HP = 0.04, MEVA = 0.1, ENMITY = 0.2 } },               -- Community guide: cap damage taken
            Dt = { Stats = { PDT = -12, MDT = -10, MEVA = 0.2, HP = 0.06, ENMITY = 0.3 } },               -- Community guide: PDT then DT, MDT then DT, magic evasion
            Tp_Default = { Stats = { PDT = -2, MDT = -2, ENMITY = 0.6, PARRY = 0.4, INQUARTATA = 1.2, HP = 0.03 } }, -- Community guide and Quiescence: the parry build, enmity, HP
            Tp_Hybrid = { Stats = { PDT = -4, MDT = -3, ACC = 0.8, ATT = 0.3, DOUBLE_ATTACK = 1.2, STORETP = 1 } }, -- Community guide and the tank guide: "Hybrid Tanking/DD", tank first
            Tp_Acc = { Stats = { ACC = 1.5, ATT = 0.5, STORETP = 1.5, DOUBLE_ATTACK = 2, TRIPLE_ATTACK = 2.5 } }, -- Quiescence, the Omen DD build: an accurate five-hit, Store TP 70, DA 25%, TA 13%
            Ws_Default = { Stats = { STR = 1, DEX = 0.5, ACC = 0.5, ATT = 0.5, DOUBLE_ATTACK = 1, ALL_WSDMG_ALL_HITS = 3 } }, -- the tank guide's DD section: Resolution and Dimidiation
            Precast = { Stats = { FASTCAST = 3 } },                                                       -- Community guide: fast cast to 80%
            Interim = { Stats = { SPELLINTERRUPT = 1.5, PDT = -2, MDT = -1.5 } },                         -- Community guide: spell interruption to -102%
            Phalanx = { Stats = { PHALANX_RECEIVED = 6, ENHANCE = 0.5 } },                                -- Community guide and the tank guide: Phalanx+ sets
        } },
    },
    -- Vivacious Pulse heals by Divine Magic skill (job_utils\rune_fencer.lua) and the AF3 head adds an ailment
    -- removal; Lunge and Swipe are magic hits that also want magic attack and accuracy (GetAwayCoxn's Swipe set)
    Abilities = {
        ['Vivacious Pulse'] = { Stats = { DIVINE = 1, AUGMENTS_VIVACIOUS_PULSE = 10 } },
        ['Lunge'] = { Stats = { SWIPE = 2, MAGIC_DAMAGE = 1.5, MATT = 2, MACC = 1, INT = 0.5 } },
        ['Swipe'] = { Stats = { SWIPE = 2, MAGIC_DAMAGE = 1.5, MATT = 2, MACC = 1, INT = 0.5 } },
    },
};
