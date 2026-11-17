--[[
    vanagear: the modes every job's sets are built from.

    Each mode is Stats (weight of one point of a stat, in the units players read: 1% haste, 1%
    damage taken, 1 point of STR) and Caps (the most gear can usefully give). Pet modes weigh
    the pet's stats under Pet and PetCaps. The job files in jobs\ pick which of these a job gets
    and change any weight; a weight set to 0 there turns that stat off for the job.

    Stat names are the server's mod names (scripts/enum/mod.codegen.lua). PDT and MDT are
    damage taken plus physical or magical damage taken, which share the -50% limit.
]]--

local roles = {};

local DT = { PDT = -50, MDT = -50 };

roles.Modes = {
    -- standing around
    Idle = {
        Stats = { PDT = -3, MDT = -2, REFRESH = 6, REGEN = 2, MOVE_SPEED_GEAR_BONUS = 1, HP = 0.01, MEVA = 0.02 },
        Caps = DT,
    },
    Idle_Regen = { Stats = { REGEN = 5, PDT = -0.5 }, Caps = DT },
    Idle_Refresh = { Stats = { REFRESH = 5, PDT = -0.5 }, Caps = DT },
    Resting = { Stats = { HPHEAL = 1, MPHEAL = 2 } },
    Dt = { Stats = { PDT = -10, MDT = -8, HP = 0.05, MEVA = 0.1, DEF = 0.02 }, Caps = DT },
    -- /vg dt pdt and /vg dt mdt (the Settings tab): one kind of damage first, the general damage taken that
    -- counts for both (DMG) with it
    Dt_Physical = { Stats = { PDT = -10, DMG = -10, HP = 0.05, DEF = 0.03, MDT = -2 }, Caps = { PDT = -50, DMG = -50, MDT = -50 } },
    Dt_Magic = { Stats = { MDT = -10, DMG = -10, MEVA = 0.15, MDEF = 0.5, HP = 0.05, PDT = -2 }, Caps = { MDT = -50, DMG = -50, PDT = -50 } },
    Movement = { Stats = { MOVE_SPEED_GEAR_BONUS = 10 }, Caps = { MOVE_SPEED_GEAR_BONUS = 18 } },

    -- fighting
    Tp_Default = {
        Stats = { ACC = 0.5, ATT = 0.25, STORETP = 1.5, DOUBLE_ATTACK = 2, TRIPLE_ATTACK = 3, QUAD_ATTACK = 4,
                  HASTE_GEAR = 3, CRITHITRATE = 1, STR = 0.25, DEX = 0.35, PDT = -0.3, MDT = -0.2 },
        Caps = { HASTE_GEAR = 25, PDT = -50, MDT = -50 },
    },
    Tp_Hybrid = {
        Stats = { ACC = 0.5, ATT = 0.2, STORETP = 1.2, DOUBLE_ATTACK = 1.6, TRIPLE_ATTACK = 2.4, QUAD_ATTACK = 3.2,
                  HASTE_GEAR = 3, CRITHITRATE = 0.8, DEX = 0.3, PDT = -3, MDT = -2 },
        Caps = { HASTE_GEAR = 25, PDT = -50, MDT = -50 },
    },
    Tp_Acc = {
        Stats = { ACC = 1.5, STORETP = 1, DOUBLE_ATTACK = 1.2, TRIPLE_ATTACK = 1.8, QUAD_ATTACK = 2.4,
                  HASTE_GEAR = 2.5, DEX = 0.6, AGI = 0.1, PDT = -0.3 },
        Caps = { HASTE_GEAR = 25, PDT = -50 },
    },
    -- the fallback for a weaponskill with no stats of its own in the server's script
    Ws_Default = {
        Stats = { ATT = 0.5, ACC = 0.35, STR = 1, DEX = 0.4, ALL_WSDMG_ALL_HITS = 3, ALL_WSDMG_FIRST_HIT = 2.5,
                  ANY_FTP_BONUS = 0.08, TP_BONUS = 0.008, CRIT_DMG_INCREASE = 0.5 },
    },

    -- casting
    Precast = { Stats = { FASTCAST = 3, UFASTCAST = 2, PDT = -0.1 }, Caps = { FASTCAST = 80, PDT = -50 } },
    Cure_Precast = { Stats = { CURE_CAST_TIME = 3, FASTCAST = 2 }, Caps = { FASTCAST = 80, CURE_CAST_TIME = 80 } },
    Song_Precast = { Stats = { SONG_SPELLCASTING_TIME = 3, FASTCAST = 2 }, Caps = { FASTCAST = 80, SONG_SPELLCASTING_TIME = 80 } },
    Interim = { Stats = { SPELLINTERRUPT = 1, PDT = -2, MDT = -1.5 }, Caps = { SPELLINTERRUPT = 102, PDT = -50, MDT = -50 } },
    Cure = {
        Stats = { CURE_POTENCY = 3, CURE_POTENCY_II = 2, MND = 0.5, VIT = 0.15, HEALING = 0.6, CONSERVE_MP = 0.2, ENMITY = -0.3 },
        Caps = { CURE_POTENCY = 50, CURE_POTENCY_II = 30 },
    },
    Cursna = { Stats = { ENHANCES_CURSNA = 3, HEALING = 1 } },
    Enhancing = { Stats = { ENHANCE = 1, ENH_MAGIC_DURATION = 2, CONSERVE_MP = 0.2 } },
    Stoneskin = { Stats = { STONESKIN_BONUS_HP = 1, MND = 0.3, ENHANCE = 0.4 } },
    Phalanx = { Stats = { PHALANX_RECEIVED = 5, ENHANCE = 0.5 } },
    Regen = { Stats = { REGEN_DURATION = 2, ENH_MAGIC_DURATION = 1, ENHANCE = 0.2 } },
    Refresh = { Stats = { ENHANCES_REFRESH = 3, ENH_MAGIC_DURATION = 1, ENHANCE = 0.2 } },
    -- worn over the spell above when it lands on you, or when its strength is skill (the templates,
    -- M419): what the server reads for a spell received and for skill-scaled enhancing
    Cure_Self = { Stats = { CURE_POTENCY_RCVD = 3, CURE_POTENCY = 1, MND = 0.3 }, Caps = { CURE_POTENCY = 50 } },
    Enhancing_Self = { Stats = { ENH_MAGIC_DURATION = 2, PHALANX_RECEIVED = 2, ENHANCES_PROT_SHELL_RCVD = 1, ENHANCE = 0.3 } },
    Refresh_Self = { Stats = { ENHANCES_REFRESH = 3, ENH_MAGIC_DURATION = 1.5 } },
    Enhancing_Skill = { Stats = { ENHANCE = 2, BARSPELL_AMOUNT = 2, BARSPELL_MDEF_BONUS = 1 } },
    Enhancing_Precast = { Stats = { FASTCAST = 3, UFASTCAST = 2 }, Caps = { FASTCAST = 80 } },
    Helix = { Stats = { MATT = 2, INT = 1, MACC = 0.6, MAGIC_DAMAGE = 1.2, HELIX_DURATION = 1 } },
    -- the job effects the templates lay over a phase while they are up (M419)
    Saboteur = { Stats = { ENHANCES_SABOTEUR = 3, MACC = 1, ENFEEBLE = 0.5 } },
    Enspell = { Stats = { ENSPELL_DMG_BONUS = 3, ENSPELL_DMG_PCT = 3, ACC = 0.5, DOUBLE_ATTACK = 0.5 } },
    SneakAttack = { Stats = { SNEAK_ATK_DEX = 3, DEX = 1, CRITHITRATE = 1, CRIT_DMG_INCREASE = 1 } },
    TrickAttack = { Stats = { TRICK_ATK_AGI = 3, AGI = 1, CRITHITRATE = 1, CRIT_DMG_INCREASE = 1 } },
    -- both waiting at once: one hit takes both bonuses (GetAwayCoxn's THF.lua SATA set)
    SneakTrickAttack = { Stats = { SNEAK_ATK_DEX = 3, TRICK_ATK_AGI = 3, DEX = 1, AGI = 1, CRITHITRATE = 1, CRIT_DMG_INCREASE = 1 } },
    Cure_Solace = { Stats = { AFFLATUS_SOLACE = 3, CURE_POTENCY = 1, MND = 0.3 }, Caps = { CURE_POTENCY = 50 } },
    -- the Dark Knight's (the DRK template): Souleater and Last Resort while they are up, the Absorb
    -- spells, Dread Spikes
    Souleater = { Stats = { SOULEATER_EFFECT = 3, STALWART_SOUL = 1, ATT = 0.5, ACC = 0.3 } },
    LastResort = { Stats = { DESPERATE_BLOWS = 3, ATT = 0.5, HASTE_GEAR = 1 }, Caps = { HASTE_GEAR = 25 } },
    Absorb = { Stats = { ENHANCES_ABSORB_EFFECTS = 3, AUGMENTS_ABSORB = 2, ABSORB_EFFECT_DURATION = 1, DARK = 1, MACC = 1 } },
    DreadSpikes = { Stats = { DREAD_SPIKES_EFFECT = 3, HP = 0.05, DARK = 0.3 } },
    -- the Samurai's (the SAM template, GetAwayCoxn's SAM.lua): fighting under Hasso values Zanshin
    -- (the server reads it for Hasso's extra swing, battle_entity), under Seigan Third Eye's counter;
    -- Third Eye's own and Sengikori's are single pieces laid over (weaponskills.lua reads
    -- SENGIKORI_BONUS on the weapon skill, not on the press)
    Hasso = {
        Stats = { ACC = 0.5, ATT = 0.25, STORETP = 1.5, DOUBLE_ATTACK = 2, TRIPLE_ATTACK = 3, QUAD_ATTACK = 4,
                  HASTE_GEAR = 3, CRITHITRATE = 1, STR = 0.25, DEX = 0.35, ZANSHIN = 1, ZANSHIN_DOUBLE_DAMAGE = 1, PDT = -0.3 },
        Caps = { HASTE_GEAR = 25, PDT = -50 },
    },
    Seigan = {
        Stats = { ACC = 0.5, STORETP = 1.2, DOUBLE_ATTACK = 1.6, TRIPLE_ATTACK = 2.4, HASTE_GEAR = 3, THIRD_EYE_COUNTER_RATE = 2,
                  THIRD_EYE_RETENTION_RATE = 1, ZANSHIN = 0.5, PDT = -3, MDT = -2 },
        Caps = { HASTE_GEAR = 25, PDT = -50, MDT = -50 },
    },
    -- the Monk's (the MNK template, GetAwayCoxn's MNK.lua "Footwork"): fighting under Footwork, every
    -- kick does the weapon's damage (attack.cpp, KICK_DMG), so the kick stats come up
    FootworkTP = {
        Stats = { ACC = 0.8, ATT = 0.25, STORETP = 1.5, DOUBLE_ATTACK = 2, TRIPLE_ATTACK = 3, HASTE_GEAR = 3, MARTIAL_ARTS = 0.5,
                  KICK_DMG = 2, KICK_ATTACK_RATE = 2, EXTRA_KICK_ATTACK = 1.5, STR = 0.25, DEX = 0.35, PDT = -0.3 },
        Caps = { HASTE_GEAR = 25, PDT = -50 },
    },
    ThirdEye = { Stats ={ THIRD_EYE_RETENTION_RATE = 3, THIRD_EYE_COUNTER_RATE = 2 } },
    Sengikori = { Stats = { SENGIKORI_BONUS = 3 } },
    -- a tank's: enmity over a job ability or Flash, and spell interruption down while the monster hits
    -- you mid-cast (the PLD and RUN templates)
    Enmity = { Stats = { ENMITY = 3, PDT = -1, MDT = -0.5, HP = 0.02 }, Caps = { PDT = -50, MDT = -50 } },
    -- fighting as the tank (GetAwayCoxn's PLD.lua Tank_Main, Tank_MEVA, picked with /vg fwd tank): damage
    -- taken capped and hate kept, or magic evasion first against a caster
    Tank_Main = { Stats = { PDT = -4, MDT = -2.5, DMG = -2, ENMITY = 1, HP = 0.04, SHIELDBLOCKRATE = 1, DEF = 0.03, MEVA = 0.03 }, Caps = { PDT = -50, MDT = -50, DMG = -50 } },
    Tank_MEVA = { Stats = { MEVA = 0.12, MDT = -4, PDT = -2, DMG = -2, ENMITY = 0.5, HP = 0.03 }, Caps = { PDT = -50, MDT = -50, DMG = -50 } },
    -- while Cover is up: the server reads these when a covered hit lands on you (battleutils.cpp)
    Covering = { Stats = { COVER_TO_MP = 3, COVER_MAGIC_AND_RANGED = 10, PDT = -1, MDT = -0.5, HP = 0.02 }, Caps = { PDT = -50, MDT = -50 } },
    SpellInterrupt = { Stats ={ SPELLINTERRUPT = 2, PDT = -1, MDT = -0.5, ENMITY = 0.5 }, Caps = { SPELLINTERRUPT = 102, PDT = -50, MDT = -50 } },
    -- the obi: a waist piece that makes the day and weather bonus apply every time. Hachirin-no-Obi
    -- does it for every element (FORCE_DW_BONUS_PENALTY), the elemental obis for their own one
    Obi = { Stats = { FORCE_DW_BONUS_PENALTY = 10 } },
    Obi_Fire = { Stats = { FORCE_FIRE_DWBONUS = 10, FORCE_DW_BONUS_PENALTY = 9 } },
    Obi_Ice = { Stats = { FORCE_ICE_DWBONUS = 10, FORCE_DW_BONUS_PENALTY = 9 } },
    Obi_Wind = { Stats = { FORCE_WIND_DWBONUS = 10, FORCE_DW_BONUS_PENALTY = 9 } },
    Obi_Earth = { Stats = { FORCE_EARTH_DWBONUS = 10, FORCE_DW_BONUS_PENALTY = 9 } },
    Obi_Thunder = { Stats = { FORCE_LIGHTNING_DWBONUS = 10, FORCE_DW_BONUS_PENALTY = 9 } },
    Obi_Water = { Stats = { FORCE_WATER_DWBONUS = 10, FORCE_DW_BONUS_PENALTY = 9 } },
    Obi_Light = { Stats = { FORCE_LIGHT_DWBONUS = 10, FORCE_DW_BONUS_PENALTY = 9 } },
    Obi_Dark = { Stats = { FORCE_DARK_DWBONUS = 10, FORCE_DW_BONUS_PENALTY = 9 } },
    Enfeebling = { Stats = { MACC = 1.5, ENFEEBLE = 1, MND = 0.6, INT = 0.6, CONSERVE_MP = 0.1 } },
    Macc = { Stats = { MACC = 2, ENFEEBLE = 1.2, INT = 0.5, MND = 0.5 } },
    Nuke = { Stats = { MATT = 2, INT = 1, MACC = 0.6, MAGIC_DAMAGE = 1.2, ELEM = 0.3 } },
    NukeACC = { Stats = { MACC = 2, ELEM = 0.8, MATT = 1, INT = 1, MAGIC_DAMAGE = 0.6 } },
    Burst = {
        Stats = { MAGIC_BURST_BONUS_CAPPED = 4, MAGIC_BURST_BONUS_UNCAPPED = 4, MATT = 1, INT = 0.7, MACC = 0.5, MAGIC_DAMAGE = 0.6 },
        Caps = { MAGIC_BURST_BONUS_CAPPED = 40 },
    },
    -- Death does its base plus three times the MP you have when it lands (damage_spell.lua), so the set
    -- is MP first; the BLM template holds it on with /vg fwd death so the MP is not lost (GetAwayCoxn)
    Death = { Stats = { MP = 3, MATT = 1, MAGIC_DAMAGE = 0.6, MACC = 0.6, INT = 0.3, MAGIC_BURST_BONUS_CAPPED = 1 }, Caps = { MAGIC_BURST_BONUS_CAPPED = 40 } },
    Drain = { Stats ={ ENH_DRAIN_ASPIR = 3, DARK = 1, MACC = 1 } },
    Dark = { Stats = { DARK = 1, MACC = 1.5, INT = 0.5 } },
    Divine = { Stats = { DIVINE = 1, MACC = 1, MND = 1, MATT = 1 } },
    -- NIN_NUKE_BONUS_GEAR is added to the nuke's magic attack (damage_spell.lua, Koga Hatsuburi type gear)
    Ninjutsu = { Stats = { NINJUTSU = 1, MACC = 1, MATT = 1.5, INT = 0.5, NIN_NUKE_BONUS_GEAR = 2 } },
    -- over an elemental ninjutsu under Futae: its multiplier reads ENHANCES_FUTAE (damage_spell.lua)
    Futae = { Stats = { ENHANCES_FUTAE = 3 } },
    NinjutsuDebuff = { Stats = { MACC = 2, NINJUTSU = 1.5, INT = 0.3 } },
    NinjutsuBuff = { Stats = { NINJUTSU = 1, FASTCAST = 1, PDT = -0.3 }, Caps = { FASTCAST = 80, PDT = -50 } },
    Utsusemi = { Stats = { UTSUSEMI_BONUS = 10, FASTCAST = 2, HASTE_GEAR = 2, PDT = -0.5, MDT = -0.3 }, Caps = { FASTCAST = 80, HASTE_GEAR = 25, PDT = -50, MDT = -50 } },
    Song = { Stats = { SINGING = 1, STRING = 0.5, WIND = 0.5, ALL_SONGS_EFFECT = 4, SONG_DURATION_BONUS = 2, CHR = 0.4, MACC = 0.5 } },
    -- the debuff songs (Elegy, Lullaby, Requiem, Threnody, Finale...) have to land: Ghlin's Endgame
    -- Barding Guide puts their resist value at "Macc = 1, Skill = .9, and CHR = .5" (M401)
    SongDebuff = { Stats = { MACC = 1, SINGING = 0.9, STRING = 0.9, WIND = 0.9, CHR = 0.5, SONG_DURATION_BONUS = 0.5 } },
    BluePhysical = { Stats = { STR = 1, DEX = 0.7, ATT = 0.5, ACC = 0.5, BLUE = 0.5 } },
    BlueMagical = { Stats = { MATT = 2, INT = 1, MACC = 0.7, BLUE = 0.3 } },
    -- the rest of the blue spells by what they need (GetAwayCoxn's BLU.lua): landing, skill, MP, HP
    BlueDebuff = { Stats = { MACC = 2, BLUE = 1, MND = 0.3, INT = 0.3 } },
    BlueSkill = { Stats = { BLUE = 3, CONSERVE_MP = 0.3 } },
    BlueBuff = { Stats = { CONSERVE_MP = 2, BLUE = 0.5, ENH_MAGIC_DURATION = 0.5 } },
    WhiteWind = { Stats = { HP = 0.1, CURE_POTENCY = 2, BLUE = 0.3, MND = 0.2 }, Caps = { CURE_POTENCY = 50 } },
    -- over a physical spell under Chain Affinity, a magical one under Burst Affinity (bluemagic.lua reads both)
    -- the Scholar's (the SCH template): Sublimation's gear stores more MP each tick while it charges
    -- (effects\sublimation_activated.lua); Rapture and Ebullience gear is read on the spell they strengthen
    -- (magic.lua, damage_spell.lua)
    Sublimation = { Stats = { SUBLIMATION_BONUS = 3 } },
    Stratagem = { Stats = { RAPTURE_AMOUNT = 3, EBULLIENCE_AMOUNT = 3 } },
    ChainAffinity = { Stats = { ENHANCES_CHAIN_AFFINITY = 3 } },
    BurstAffinity = { Stats = { ENHANCES_BURST_AFFINITY = 3 } },
    Geomancy = { Stats = { GEOMANCY_SKILL = 1, HANDBELL_SKILL = 1, GEOMANCY_BONUS = 4, INDI_DURATION = 2, CONSERVE_MP = 0.2 } },
    -- an Indi spell: its duration is read only for Indi (job_utils\geomancer.lua), so it weighs more here
    -- (GetAwayCoxn's GEO.lua Indi set)
    Indi = { Stats = { GEOMANCY_SKILL = 1, HANDBELL_SKILL = 1, GEOMANCY_BONUS = 4, INDI_DURATION = 3, CONSERVE_MP = 0.2 } },

    -- shooting. Luck of the Draw (FFXIAH node 326): Snapshot to its 70% cap first, then Rapid
    -- Shot; in the shot itself ranged accuracy and Store TP come first, damage a distant second.
    -- After the shot LuAshitacast puts Idle or the fighting set back on by itself.
    Preshot = { Stats = { SNAPSHOT = 3, RAPID_SHOT = 1.5 }, Caps = { SNAPSHOT = 70 } },
    -- under Flurry (15 Snapshot) or Flurry II (30) less Snapshot gear reaches the cap, and the slots
    -- it frees go to Rapid Shot (GetAwayCoxn's RNG.lua: Preshot_FlurryI, Preshot_FlurryII)
    Preshot_Flurry = { Stats = { SNAPSHOT = 3, RAPID_SHOT = 1.5 }, Caps = { SNAPSHOT = 55 } },
    Preshot_FlurryII = { Stats = { SNAPSHOT = 3, RAPID_SHOT = 1.5 }, Caps = { SNAPSHOT = 40 } },
    Midshot = { Stats = { RACC = 1.5, STORETP = 2, AGI = 0.4, RATT = 0.4, CRITHITRATE = 0.3 } },
    -- the Corsair's shot under Triple Shot: the rate gear only counts while it is up (battle_entity.cpp)
    TripleShot = { Stats = { TRIPLE_SHOT_RATE = 3, RACC = 1.5, STORETP = 1.5, AGI = 0.4, RATT = 0.5 } },
    -- with /vg tp acc: the shot for a monster you keep missing
    Midshot_Acc = { Stats = { RACC = 3, AGI = 0.8, STORETP = 0.5, RATT = 0.2 } },
    -- the Ranger's (the RNG template), each a whole shot set with the effect on top. The server reads
    -- True Shot gear on every shot (physical_utilities), Velocity Shot's snapshot and ranged attack,
    -- Barrage's accuracy and extra shot (battleutils), Double Shot's rate (battle_entity)
    TrueShot = { Stats = { TRUE_SHOT_EFFECT = 2, RACC = 1.5, STORETP = 2, AGI = 0.4, RATT = 0.4 } },
    Velocity = { Stats = { VELOCITY_RATT_BONUS = 3, RACC = 1.5, STORETP = 2, AGI = 0.4, RATT = 0.5 } },
    Velocity_Preshot = { Stats = { VELOCITY_SNAPSHOT_BONUS = 3, SNAPSHOT = 3, RAPID_SHOT = 1.5 }, Caps = { SNAPSHOT = 70 } },
    DoubleShot = { Stats = { DOUBLE_SHOT_RATE = 3, RACC = 1.5, STORETP = 1.5, AGI = 0.4, RATT = 0.5 } },
    Barrage = { Stats = { BARRAGE_ACC = 3, BARRAGE_COUNT = 30, RACC = 2, RATT = 0.6, AGI = 0.4 } },

    -- Corsair abilities (Luck of the Draw)
    PhantomRoll = {
        Stats = { PHANTOM_ROLL = 10, PHANTOM_DURATION = 0.5, PHANTOM_RECAST = 2, PDT = -1, MDT = -1, MEVA = 0.05 },
        Caps = { PDT = -50, MDT = -50 },
    },
    QuickDraw = { Stats = { MATT = 2, AGI = 1, MACC = 0.6, MAGIC_DAMAGE = 1.2, QUICK_DRAW_DMG = 1, QUICK_DRAW_DMG_PERCENT = 3 } },
    QuickDrawAcc = { Stats = { MACC = 2, QUICK_DRAW_MACC = 2, AGI = 0.5 } },

    -- Summoner: blood pact delay on the press (Blood Pact Delay II caps at -15 s), the summoning
    -- skill and Blood Boon for wards (Summoner Guide by Lunareticc, FFXIAH node 245)
    BPDelay = { Stats = { BP_DELAY = 3, BP_DELAY_II = 3 }, Caps = { BP_DELAY = 15, BP_DELAY_II = 15 } },
    -- the avatar out and standing by: the upkeep down (status_effect_container.cpp reads PERPETUATION_REDUCTION)
    -- and MP back (GetAwayCoxn's SMN.lua Pet_Idle)
    PetIdle = { Stats = { PERPETUATION_REDUCTION = 5, HALF_PERPETUATION_DAY = 1, HALF_PERPETUATION_WEATHER = 1, REFRESH = 3, SUMMONING = 0.3, PDT = -0.3 }, Caps = { PDT = -50 } },
    -- calling an avatar: its level is set as it arrives (petutils.cpp reads AVATAR_LVL_BONUS), and the cast is long
    Summoning = { Stats = { AVATAR_LVL_BONUS = 3, SPELLINTERRUPT = 1, SUMMONING = 0.3 }, Caps = { SPELLINTERRUPT = 102 } },
    BPWard = { Stats = { SUMMONING = 1, BLOOD_BOON = 1 }, Pet = { TP_BONUS = 0.01 } },

    -- Beastmaster abilities (Killer Instinct: The Beastmaster Compendium, FFXIAH node 227)
    ReadyPrecast = { Stats = { SIC_READY_RECAST = 5 } },
    Reward = { Stats = { REWARD_HP_BONUS = 2, MND = 1, REWARD_RECAST = 1 } },
    Charm = { Stats = { CHR = 1, CHARM_CHANCE = 2, MACC = 0.4, CHARM_TIME = 0.5 } },
    Call = { Stats = { JUG_LEVEL_RANGE = 10, CALL_BEAST_DELAY = 2 } },

    -- treasure hunter, laid over whatever else is on with /vg th
    TH = { Stats = { TREASURE_HUNTER = 10 } },
    -- under Doom, and using Holy Water: what makes the cure land (Purity Ring, Gishdubar Sash; cursna.lua
    -- reads ENHANCES_CURSNA_RCVD, flask_of_holy_water.lua ENHANCES_HOLYWATER). GetAwayCoxn's Doomed, Holy_Water
    Doomed = { Stats = { ENHANCES_CURSNA_RCVD = 3, ENHANCES_HOLYWATER = 1 } },
    HolyWater = { Stats = { ENHANCES_HOLYWATER = 3, ENHANCES_CURSNA_RCVD = 1 } },

    -- pets
    PetTP = {
        Pet = { ACC = 0.6, ATT = 0.5, HASTE_GEAR = 3, DOUBLE_ATTACK = 2, STORETP = 1, DMGPHYS = -0.5 },
        PetCaps = { HASTE_GEAR = 25 },
        Stats = { PDT = -0.5 },
        Caps = DT,
    },
    PetDT = {
        Pet = { DMG = -5, DMGPHYS = -5, DMGMAGIC = -3, DMGBREATH = -2, DMGRANGE = -1, DEF = 0.05 },
        PetCaps = { DMG = -50, DMGPHYS = -50, DMGMAGIC = -50 },
        Stats = { PDT = -0.5 },
        Caps = DT,
    },
    -- a wyvern's breath, healing or damage: the master's Wyvern Breath gear, capped at 64 (job_utils\dragoon.lua),
    -- and breath accuracy for the damage ones (the DRG template)
    Breath = { Stats = { WYVERN_BREATH = 3, WYVERN_BREATH_MACC = 1 }, Caps = { WYVERN_BREATH = 64 } },
    PetAtk = { Pet = { ATT = 1, ACC = 0.6, STR = 0.5, DOUBLE_ATTACK = 1, PET_TP_BONUS = 0.01, ALL_WSDMG_ALL_HITS = 2 } },
    -- an automaton's ranged weapon skill (Arcuballista, Armor Piercer): worn ahead of it in the PUP template
    PetRangedWS = { Pet = { RATT = 1, RACC = 0.8, AGI = 0.4, PET_TP_BONUS = 0.02 } },
    PetMab = { Pet = { MATT = 2, MACC = 1, INT = 0.5 } },
    PetAcc = { Pet = { ACC = 2, MACC = 1.5, ATT = 0.3 } },
};

-- Mode names each kind of job gets.
roles.Fighter = { 'Idle', 'Idle_Regen', 'Resting', 'Dt', 'Dt_Physical', 'Dt_Magic', 'Movement', 'Tp_Default', 'Tp_Hybrid', 'Tp_Acc', 'Ws_Default' };
-- a support job (WHM, BLM, SCH, GEO, SMN, BRD: Lee, 22 Oct 2026, "their guides will be about maxing
-- that support") gets the standing sets but no fighting or weaponskill set unless a band adds them
roles.Support = { 'Idle', 'Idle_Regen', 'Resting', 'Dt', 'Dt_Physical', 'Dt_Magic', 'Movement' };
roles.Caster = { 'Idle_Refresh', 'Precast', 'Interim' };
roles.Shooter = { 'Preshot', 'Preshot_Flurry', 'Preshot_FlurryII', 'Midshot', 'Midshot_Acc' };
roles.Pet = { 'PetTP', 'PetDT', 'PetAtk', 'PetMab', 'PetAcc' };
roles.Always = { 'TH', 'Doomed', 'HolyWater' };

-- The midcast sets each kind of magic gets, by the skill name LuAshitacast reports.
roles.SkillSets = {
    ['Healing Magic'] = { 'Cure', 'Cure_Precast', 'Cursna', 'Cure_Self' },
    ['Enhancing Magic'] = { 'Enhancing', 'Stoneskin', 'Phalanx', 'Regen', 'Refresh', 'Enhancing_Self', 'Refresh_Self',
        'Enhancing_Skill', 'Enhancing_Precast' },
    ['Enfeebling Magic'] = { 'Enfeebling', 'Macc' },
    ['Elemental Magic'] = { 'Nuke', 'NukeACC', 'Burst' },
    ['Dark Magic'] = { 'Dark', 'Drain' },
    ['Divine Magic'] = { 'Divine' },
    ['Ninjutsu'] = { 'Ninjutsu' },
    ['Singing'] = { 'Song', 'SongDebuff', 'Song_Precast' },
    ['Blue Magic'] = { 'BluePhysical', 'BlueMagical' },
    ['Geomancy'] = { 'Geomancy' },
};

-- The magic a support job brings when it is the subjob.
roles.SubSkills = {
    WHM = { 'Healing Magic', 'Enhancing Magic', 'Divine Magic' },
    RDM = { 'Healing Magic', 'Enhancing Magic', 'Enfeebling Magic', 'Elemental Magic' },
    BLM = { 'Elemental Magic', 'Enfeebling Magic', 'Dark Magic' },
    SCH = { 'Healing Magic', 'Enhancing Magic', 'Enfeebling Magic', 'Elemental Magic', 'Dark Magic' },
    PLD = { 'Healing Magic', 'Enhancing Magic', 'Divine Magic' },
    DRK = { 'Dark Magic', 'Elemental Magic', 'Enfeebling Magic' },
    NIN = { 'Ninjutsu' },
    BLU = { 'Blue Magic' },
    GEO = { 'Geomancy', 'Elemental Magic' },
    RUN = { 'Enhancing Magic', 'Divine Magic' },
};

-- Each kind of song has a family set (the templates wear it over Song): the song set's stats with the
-- server's own effect stat for that kind on top (MARCH_EFFECT...). The debuff songs build on SongDebuff.
roles.SongFamilies = {
    { set = 'March', mod = 'MARCH_EFFECT' }, { set = 'Minuet', mod = 'MINUET_EFFECT' },
    { set = 'Madrigal', mod = 'MADRIGAL_EFFECT' }, { set = 'Ballad', mod = 'BALLAD_EFFECT' },
    { set = 'Paeon', mod = 'PAEON_EFFECT' }, { set = 'Minne', mod = 'MINNE_EFFECT' },
    { set = 'Scherzo', mod = 'SCHERZO_EFFECT' }, { set = 'Prelude', mod = 'PRELUDE_EFFECT' },
    { set = 'Etude', mod = 'ETUDE_EFFECT' }, { set = 'Carol', mod = 'CAROL_EFFECT' },
    { set = 'Mazurka', mod = 'MAZURKA_EFFECT' }, { set = 'Hymnus', mod = 'HYMNUS_EFFECT' },
    { set = 'Lullaby', mod = 'LULLABY_EFFECT', debuff = true }, { set = 'Elegy', mod = 'ELEGY_EFFECT', debuff = true },
    { set = 'Requiem', mod = 'REQUIEM_EFFECT', debuff = true }, { set = 'Threnody', mod = 'THRENODY_EFFECT', debuff = true },
    { set = 'Finale', mod = 'FINALE_EFFECT', debuff = true },
};
for _, f in ipairs(roles.SongFamilies) do
    local base = roles.Modes[f.debuff and 'SongDebuff' or 'Song'];
    local stats = {};
    for k, v in pairs(base.Stats) do stats[k] = v; end
    stats[f.mod] = 3;
    roles.Modes[f.set] = { Stats = stats };
    table.insert(roles.SkillSets['Singing'], f.set);
end

return roles;
