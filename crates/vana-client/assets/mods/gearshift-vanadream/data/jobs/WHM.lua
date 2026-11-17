--[[
    vanagear: White Mage - a support job (Lee, 22 Oct 2026).

    Which kinds of sets this job gets, and any weight that differs from vg\roles.lua. A weight
    here replaces the one in roles.lua for that stat; 0 turns the stat off for this job. Bands
    are level ranges (M401): the band the player's level falls in is laid over Tweaks. Support
    means the standing sets and the magic sets, no fighting set: every guide read says the
    job is a healer, and the one melee section (BG-wiki, 99) gives no priorities.

    Read 22 Oct 2026 against:
    - FFXIclopedia, White Mage/Equipment Guide (chart, 1-85), White Mage Equipment Guide by
      Eclipstic, White Mage Guide by XsiX (cure potency by level), White Mage Guide by Fredjan
      (level 90 era), all read in full. Early: "priority stats of MP and Mind or that reduce
      enmity"; MP recovered while healing "worth it to carry as much as you can". From 40 cure
      potency arrives (Dia Wand, Medicine Ring, Light Staff, Healing Staff) and is "a first
      priority", then enmity down and MND, "VIT and Healing Skill barely improve cures";
      "focus on fast casts, decreased recasts, and slot in as much MP as possible". The first
      idle Refresh piece is Vermillion Cloak at 59. 61-75 potency to its 50% cap (Healing
      Feather, Noble's Tunic, Templar Mace, Roundel Earring), the Blessed set's fast cast
      with MP and MND, Rostrum Pumps; Regen gear macroed in. At 90: MP "shouldn't be the stat
      you focus on in cure sets at higher levels. Enmity- has a much higher importance, as
      does even MND on Cure V+".
    - BG-wiki, Community White Mage Guide (Aug 2026) and Batcher's 99 WHM Gear Guide: fast
      cast to 80% with cure cast time counting; Cure to 50% potency, then Cure Potency II,
      then damage taken and Conserve MP; Curaga drops the Solace pieces for MND and potency
      II; Cursna wants Healing skill; enhancing +80 skill and 65% duration; idle "Refresh and
      MP recovery early, then add DT", at 99 damage taken capped with "Refresh less critical";
      enfeebling "a minor priority".
    - FFXIclopedia and BG-wiki Magic Burst pages: no WHM guide has a burst section, so no
      Burst set.
]]--

return {
    Support = true, Skills = { 'Healing Magic', 'Enhancing Magic', 'Divine Magic', 'Enfeebling Magic' },
    Tweaks = {
        Idle = { Stats = { REFRESH = 8 } },
        Cure = { Stats = { CURE_POTENCY = 3.5, MND = 0.6, ENMITY = -0.5, CONSERVE_MP = 0.3, HEALING = 0.4 } },
        Cursna = { Stats = { ENHANCES_CURSNA = 4, HEALING = 1.2 } },
        Regen = { Stats = { REGEN_DURATION = 2.5 } },
    },
    Bands = {
        { To = 30, Tweaks = {
            Cure = { Stats = { CURE_POTENCY = 3.5, MND = 0.6, ENMITY = -0.4, VIT = 0, HEALING = 0, MP = 0.02 } }, -- the chart's intro: MP, MND, enmity down; Fredjan: VIT and healing skill barely improve cures
            Resting = { Stats = { MPHEAL = 3 } },                                                                 -- Fredjan: as much MP recovered while healing as you can carry
            Idle = { Stats = { REFRESH = 8, MP = 0.02 } },                                                        -- no Refresh gear exists yet; MP
        } },
        { To = 60, Tweaks = {
            Cure = { Stats = { CURE_POTENCY = 4, MND = 0.5, ENMITY = -0.5, VIT = 0, HEALING = 0 } },              -- Fredjan: potency the first priority, then enmity down, MND; XsiX's potency table starts at 40
            Precast = { Stats = { FASTCAST = 3.5 } },                                                             -- Eclipstic: "focus on fast casts, decreased recasts"
            Resting = { Stats = { MPHEAL = 3 } },                                                                 -- Fredjan; Eclipstic: Qiqirn Sash for MP and hMP
            Idle = { Stats = { REFRESH = 6, MP = 0.01 } },                                                        -- Eclipstic: Vermillion Cloak at 59 is the first idle Refresh piece
        } },
        { To = 75, Tweaks = {
            Cure = { Stats = { CURE_POTENCY = 4, MND = 0.5, ENMITY = -0.5, CONSERVE_MP = 0.2, VIT = 0, HEALING = 0 } }, -- Fredjan: to the 50% cap, then enmity down and MND
            Precast = { Stats = { FASTCAST = 4 } },                                                               -- Eclipstic: the Blessed set, "haste gear for decreased recasts paired with extra MP and MND"; Rostrum Pumps
            Regen = { Stats = { REGEN_DURATION = 2.5 } },                                                         -- Eclipstic: the Regen body macroed in
        } },
        { To = 99, Tweaks = {
            Precast = { Stats = { FASTCAST = 3.5, CURE_CAST_TIME = 1.5 } },                                        -- Community guide: 80%, cure cast time counts toward it
            Cure_Precast = { Stats = { CURE_CAST_TIME = 3, FASTCAST = 2 } },
            Cure = { Stats = { CURE_POTENCY = 3.5, CURE_POTENCY_II = 2.5, MND = 0.6, ENMITY = -0.6, CONSERVE_MP = 0.2, VIT = 0, HEALING = 0.2 } }, -- Community guide: 50% then Cure Potency II; Fredjan: enmity down and MND over MP; Batcher: healing skill only +50
            Idle = { Stats = { REFRESH = 4, PDT = -4, MDT = -3 } },                                                -- Batcher: damage taken capped, "Refresh is less critical"
            Cursna = { Stats = { ENHANCES_CURSNA = 3, HEALING = 1.5 } },                                           -- Batcher: the Cursna set maximises healing skill
            Enhancing = { Stats = { ENHANCE = 1.2, ENH_MAGIC_DURATION = 2 } },                                     -- Batcher: +80 skill, 65% duration
            Enfeebling = { Stats = { MACC = 1.2, ENFEEBLE = 1, MND = 0.6, INT = 0.6 } },                            -- Batcher: skill, magic accuracy, MND and INT; "a minor priority"
        } },
    },
};
