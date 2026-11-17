--[[
    vanagear name lists (ported) the handlers sort actions by.

    The Blue Magic and blood pact lists are from GetAwayCoxn's Luashitacast-Profiles (common/gcinclude.lua,
    MIT licence, Copyright (c) 2022 GetAwayCoxn). The magical Ready moves are Ferrin's BST
    profile's list.
]]--

local lists = {};

local function set(t)
    local s = {};
    for _, v in ipairs(t) do s[v] = true; end
    return s;
end

-- Ready moves that use the pet's magic stats; every other Ready move is physical.
lists.MagicReady = set({
    'Cursed Sphere', 'Venom', 'Toxic Spit', 'Venom Spray', 'Bubble Shower', 'Fireball', 'Plague Breath', 'Snow Cloud',
    'Acid Spray', 'Silence Gas', 'Dark Spore', 'Charged Whisker', 'Purulent Ooze', 'Aqua Breath', 'Stink Bomb',
    'Nectarous Deluge', 'Nepenthic Plunge', 'Foul Waters', 'Dust Cloud', 'Sheep Song', 'Scream', 'Dream Flower', 'Roar',
    'Gloeosuccus', 'Palsy Pollen', 'Soporific', 'Geist Wall', 'Numbing Noise', 'Spoil', 'Hi-Freq Field', 'Sandpit',
    'Sandblast', 'Filamented Hold', 'Spore', 'Infrasonics', 'Chaotic Eye', 'Blaster', 'Intimidate', 'Noisome Powder',
    'TP Drainkiss', 'Jettatura', 'Spider Web', 'Corrosive Ooze', 'Molting Plumage', 'Swooping Frenzy', 'Pestilent Plume',
    'Gloom Spray',
});

-- Ready moves that only need to land (debuffs): the pet accuracy set.
lists.EnfeebleReady = set({
    'Sheep Song', 'Soporific', 'Dream Flower', 'Spore', 'Palsy Pollen', 'Filamented Hold', 'Spider Web', 'Chaotic Eye',
    'Numbing Noise', 'Infrasonics', 'Scream', 'Roar', 'Jettatura', 'Intimidate', 'Silence Gas', 'Sandpit', 'Gloeosuccus',
});

lists.BluePhysical = set({
    'Foot Kick', 'Sprout Smack', 'Wild Oats', 'Power Attack', 'Queasyshroom', 'Battle Dance', 'Feather Storm', 'Helldive',
    'Bludgeon', 'Claw Cyclone', 'Screwdriver', 'Grand Slam', 'Smite of Rage', 'Pinecone Bomb', 'Jet Stream', 'Uppercut',
    'Terror Touch', 'Mandibular Bite', 'Sickle Slash', 'Dimensional Death', 'Spiral Spin', 'Death Scissors', 'Seedspray',
    'Body Slam', 'Hydro Shot', 'Frenetic Rip', 'Spinal Cleave', 'Hysteric Barrage', 'Asuran Claws', 'Cannonball',
    'Disseverment', 'Ram Charge', 'Vertical Cleave', 'Final Sting', 'Goblin Rush', 'Vanity Dive', 'Whirl of Rage',
    'Benthic Typhoon', 'Quad. Continuum', 'Empty Thrash', 'Delta Thrust', 'Heavy Strike', 'Quadrastrike', 'Tourbillion',
    'Amorphic Spikes', 'Barbed Crescent', 'Bilgestorm', 'Bloodrake', 'Glutinous Dart', 'Paralyzing Triad',
    'Thrashing Assault', 'Sinker Drill', 'Sweeping Gouge', 'Saurian Slide',
});

-- The other blue spells by what they need (GetAwayCoxn's gcinclude.lua lists): the ones that have to
-- land, stuns, buffs (MP saved), the ones whose strength is blue magic skill, cures, hate.
lists.BlueDebuff = set({
    'Filamented Hold', 'Cimicine Discharge', 'Demoralizing Roar', 'Venom Shell', 'Light of Penance', 'Sandspray',
    'Auroral Drape', 'Frightful Roar', 'Enervation', 'Infrasonics', 'Lowing', 'CMain Wave', 'Awful Eye',
    'Voracious Trunk', 'Sheep Song', 'Soporific', 'Yawn', 'Dream Flower', 'Chaotic Eye', 'Sound Blast', 'Blank Gaze',
    'Stinking Gas', 'Geist Wall', 'Feather Tickle', 'Reaving Wind', 'Mortal Ray', 'Absolute Terror', 'Blistering Roar',
    'Cruel Joke',
    -- stuns: they have to land too
    'Head Butt', 'Frypan', 'Tail Slap', 'Sub-zero Smash', 'Sudden Lunge',
});
lists.BlueBuff = set({
    'Cocoon', 'Refueling', 'Feather Barrier', 'Memento Mori', 'Zephyr Mantle', 'Warm-Up', 'Amplification',
    'Triumphant Roar', 'Saline Coat', 'Reactor Cool', 'Plasma Charge', 'Regeneration', 'Animating Wail',
    'Battery Charge', 'Winds of Promy.', 'Barrier Tusk', 'Orcish Counterstance', 'Pyric Bulwark', 'Nat. Meditation',
    'Restoral', 'Erratic Flutter', 'Carcharian Verve', 'Harden Shell', 'Mighty Guard',
});
lists.BlueSkill = set({ 'Metallic Body', 'Diamondhide', 'Magic Barrier', 'Occultation', 'Atra. Libations' });
lists.BlueCure = set({ 'Pollen', 'Healing Breeze', 'Wild Carrot', 'Magic Fruit', 'Plenilune Embrace' });
lists.BlueEnmity = set({ 'Actinic Burst', 'Exuviation', 'Fantod', 'Jettatura', 'Temporal Shift' });

-- Blood pacts by what they need (GetAwayCoxn's gcinclude.lua lists).
lists.BPMagical = set({
    'Searing Light', 'Meteorite', 'Holy Mist', 'Inferno', 'Fire II', 'Fire IV', 'Meteor Strike', 'Conflag Strike',
    'Diamond Dust', 'Blizzard II', 'Blizzard IV', 'Heavenly Strike', 'Aerial Blast', 'Aero II', 'Aero IV', 'Wind Blade',
    'Earthen Fury', 'Stone II', 'Stone IV', 'Geocrush', 'Judgement Bolt', 'Thunder II', 'Thunder IV', 'Thunderstorm',
    'Thunderspark', 'Tidal Wave', 'Water II', 'Water IV', 'Grand Fall', 'Howling Moon', 'Lunar Bay', 'Ruinous Omen',
    'Somnolence', 'Nether Blast', 'Night Terror', 'Level ? Holy', 'Flaming Crush', 'Burning Strike',
});
lists.BPDebuff = set({
    'Diamond Storm', 'Sleepga', 'Shock Squall', 'Slowga', 'Tidal Roar', 'Pavor Nocturnus', 'Ultimate Terror', 'Nightmare',
    'Mewing Lullaby', 'Eerie Eye',
});
lists.BPBuff = set({
    'Shining Ruby', 'Glittering Ruby', 'Crimson Howl', 'Inferno Howl', 'Frost Armor', 'Crystal Blessing', 'Aerial Armor',
    'Hastega II', 'Fleet Wind', 'Hastega', 'Earthen Ward', 'Earthen Armor', 'Rolling Thunder', 'Lightning Armor',
    'Soothing Current', 'Ecliptic Growl', 'Heavenward Howl', 'Ecliptic Howl', 'Noctoshield', 'Dream Shroud',
    'Altana\'s Favor', 'Reraise', 'Reraise II', 'Reraise III', 'Raise', 'Raise II', 'Raise III', 'Wind\'s Blessing',
    'Healing Ruby', 'Healing Ruby II', 'Whispering Wind', 'Spring Water',
});

-- Gear used from the slot, by the word a player types: /vg warp, /vg xp. Any other usable piece
-- answers to the first word of its name.
lists.UseWords = {
    ['Empress Band'] = 'xp', ['Emperor Band'] = 'xp', ['Chariot Band'] = 'xp', ['Kupofried\'s Ring'] = 'xp',
    ['Resolution Ring'] = 'xp', ['Capacity Ring'] = 'cp', ['Trizek Ring'] = 'cp', ['Vocation Ring'] = 'vocation',
    ['Tavnazian Ring'] = 'tav', ['Dim. Ring (Holla)'] = 'holla', ['Dim. Ring (Dem)'] = 'dem', ['Dim. Ring (Mea)'] = 'mea',
};

return lists;
