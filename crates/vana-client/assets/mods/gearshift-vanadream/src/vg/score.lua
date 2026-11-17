--[[
    Ported from vanagear's vg/score.lua (the same weights, caps, set bonuses and latents, the same rounds); only the
    plumbing differs: its Ashita calls are the mod's, and the long loops call the builder's pace.

    vanagear: scoring gear and building a set.

    A mode is a table of weights (how much one point of a stat is worth) and caps (the most of a
    stat gear can usefully give). A set's score is the weighted sum of its stats, each stat cut
    off at its cap. The set is built by filling every slot with its best piece, then going round
    the slots again, trying every piece in each slot with the others held, until a round changes
    nothing. The caps are why it goes round: once gear haste is at 25%, another haste piece is
    worth nothing and its slot goes to something else.
]]--

local vdata = require('src.vg.data');
local pieces_of = require('src.vg.pieces');

local score = {};

-- Called in the long loops: the builder yields here when its share of the frame is used.
local function pace() require('src.build.pick').pace(); end

-- Server units are not the units players think in: haste and damage taken are kept in hundredths
-- of a percent. Weights and caps in the job files are written per point as players read them
-- (1% haste, 1% damage taken), and this converts.
local unit = {
    HASTE_GEAR = 100, HASTE_MAGIC = 100,
    DMG = 100, DMGPHYS = 100, DMGPHYS_II = 100, DMGMAGIC = 100, DMGMAGIC_II = 100, DMGBREATH = 100, DMGRANGE = 100,
    UDMGPHYS = 100, UDMGMAGIC = 100,
    PDT = 100, MDT = 100,
};

-- Stats that are a sum of server mods and share one cap: physical damage taken is general
-- damage taken plus physical damage taken, both against the same -50%.
local virtual = {
    PDT = { 'DMG', 'DMGPHYS' },
    MDT = { 'DMG', 'DMGMAGIC' },
};
score.Unit = unit;
score.Virtual = virtual;

-- Weights and caps by stat name -> by key, in server units. Keys: 'm<mod id>' for the player's
-- stats, 'p<mod id>' for the pet's, 'v<NAME>' for a virtual stat.
score.Compile = function(mode)
    local c = { w = {}, cap = {}, parts = {}, Name = mode.Name };
    local function key(name, pet)
        if (virtual[name] ~= nil) and (not pet) then
            return 'v' .. name;
        end
        local id = vdata.ModId(name);
        return id and ((pet and 'p' or 'm') .. id) or nil;
    end
    local function weights(from, pet)
        for name, weight in pairs(from or {}) do
            local k = key(name, pet);
            -- a stat no item carries (Innin's nuke bonus, Deep Breathing) has nothing to dress for:
            -- it is skipped, not reported. tests\stat_names.py catches names the server lacks.
            if (k ~= nil) then
                c.w[k] = (c.w[k] or 0) + weight / (unit[name] or 1);
            end
        end
    end
    local function caps(from, pet)
        for name, cap in pairs(from or {}) do
            local k = key(name, pet);
            if (k ~= nil) then c.cap[k] = cap * (unit[name] or 1); end
        end
    end
    weights(mode.Stats, false);
    weights(mode.Pet, true);
    caps(mode.Caps, false);
    caps(mode.PetCaps, true);
    -- which server mods feed each virtual stat
    for name, mods in pairs(virtual) do
        if (c.w['v' .. name] ~= nil) then
            for _, modName in ipairs(mods) do
                local id = vdata.ModId(modName);
                if (id ~= nil) then
                    c.parts[id] = c.parts[id] or {};
                    table.insert(c.parts[id], 'v' .. name);
                end
            end
        end
    end
    c.HasPet = (mode.Pet ~= nil) and (next(mode.Pet) ~= nil);

    -- set bonuses that give a stat this set values (data\gearsets.lua): each piece of such a set
    -- counts toward it, and the bonus for the pieces worn is added before caps
    c.sets, c.setOf = {}, {};
    for setId, s in pairs((vdata.GearSets ~= nil) and vdata.GearSets() or {}) do
        local mods = {};
        for _, m in ipairs(s.mods) do
            local keys = {};
            if (c.w['m' .. m.mod] ~= nil) then keys[#keys + 1] = 'm' .. m.mod; end
            for _, vk in ipairs(c.parts[m.mod] or {}) do keys[#keys + 1] = vk; end
            if (#keys > 0) then mods[#mods + 1] = { keys = keys, v = m.v }; end
        end
        if (#mods > 0) then
            local members = {};
            for _, itemId in ipairs(s.items) do members[itemId] = true; end
            c.sets[#c.sets + 1] = { id = setId, min = s.min or 2, max = s.max or 17, req = s.req, mods = mods, members = members };
            for _, itemId in ipairs(s.items) do
                c.setOf[itemId] = c.setOf[itemId] or {};
                table.insert(c.setOf[itemId], c.sets[#c.sets]);
            end
        end
    end
    c.Drawn = mode.Drawn;
    return c;
end

-- A latent stat holds for this set and this player when its condition is one a set can be built
-- for and is true now (data\latents.lua): job, level, zone, Dynamis, weapon drawn or sheathed.
local dynamis = { [39] = true, [40] = true, [41] = true, [42] = true, [134] = true, [135] = true, [185] = true,
    [186] = true, [187] = true, [188] = true, [294] = true, [295] = true, [296] = true, [297] = true };
local function latentHolds(l, mode, who)
    if (who == nil) then return false; end
    if (l.latent == 8) then return who.Sub == l.param; end
    if (l.latent == 62) then return who.Job == l.param; end
    if (l.latent == 50) then return (who.Level or 99) < l.param; end
    if (l.latent == 51) then return (who.Level or 0) > l.param; end
    if (l.latent == 23) then return who.Zone == l.param; end
    if (l.latent == 48) then return dynamis[who.Zone or 0] == true; end
    if (l.latent == 10) then return mode.Drawn == true; end
    if (l.latent == 11) then return mode.Drawn == false; end
    return false;
end

-- The weighted stats one piece gives in one slot: { [key] = value }.
local function vector(piece, slot, mode, petTypes)
    local v = {};
    local function add(mods, prefix)
        for mod, value in pairs(mods or {}) do
            local k = prefix .. mod;
            if (mode.w[k] ~= nil) then
                v[k] = (v[k] or 0) + value;
            end
            if (prefix == 'm') and (mode.parts[mod] ~= nil) then
                for _, vk in ipairs(mode.parts[mod]) do
                    v[vk] = (v[vk] or 0) + value;
                end
            end
        end
    end
    local s = piece.Server;
    add(s.mods, 'm');
    if (s.inslot ~= nil) then
        add(s.inslot[slot - 1], 'm');
    end
    if (piece.Aug ~= nil) then
        add(piece.Aug.mods, 'm');
    end
    if (mode.HasPet) then
        for _, t in ipairs(petTypes or {}) do
            add(s.pet and s.pet[t], 'p');
            add(piece.Aug and piece.Aug.pet[t], 'p');
        end
    end
    -- latent stats whose condition holds for this set
    for _, l in ipairs(((vdata.Latents ~= nil) and vdata.Latents() or {})[piece.Id] or {}) do
        if (latentHolds(l, mode, mode.Who)) then add({ [l.mod] = l.v }, 'm'); end
    end
    -- membership of a set whose bonus this set values, and the item a set may require
    for _, st in ipairs((mode.setOf ~= nil) and mode.setOf[piece.Id] or {}) do
        v['s' .. st.id] = 1;
        if (st.req == piece.Id) then v['q' .. st.id] = 1; end
    end
    return v;
end
score.Vector = vector;

local function total(mode, totals)
    -- set bonuses for the pieces worn, added to their stats before the caps
    local all = totals;
    for _, st in ipairs(mode.sets or {}) do
        local count = totals['s' .. st.id] or 0;
        if (count >= st.min) and ((st.req == nil) or ((totals['q' .. st.id] or 0) > 0)) then
            local tier = math.min(count, st.max) - st.min;
            if (all == totals) then
                all = {};
                for k, value in pairs(totals) do all[k] = value; end
            end
            for _, m in ipairs(st.mods) do
                local value = m.v[tier + 1] or 0;   -- a tier the set gives no value for adds nothing
                for _, k in ipairs(m.keys) do all[k] = (all[k] or 0) + value; end
            end
        end
    end
    local sum = 0;
    for k, value in pairs(all) do
        local w = mode.w[k];
        if (w ~= nil) then
            local cap = mode.cap[k];
            if (cap ~= nil) then
                if (cap > 0) and (value > cap) then value = cap; end
                if (cap < 0) and (value < cap) then value = cap; end
            end
            sum = sum + w * value;
        end
    end
    return sum;
end
score.Total = total;

local function apply(totals, v, sign)
    for k, value in pairs(v) do
        totals[k] = (totals[k] or 0) + sign * value;
    end
end

-- Builds one set over the given slots. Returns { [slot] = piece }, the ranked candidates per
-- slot from the last round (for /vg why), the set's score and its stat totals.
-- withSub: the support job's gear counts too (Vanadreams lets you and your trusts wear it).
score.Build = function(mode, pieces, who, slots, petTypes, withSub)
    mode.Who = who;   -- for latent stats that depend on the player (job, level, zone)
    local cands = {};
    for _, slot in ipairs(slots) do
        pace();
        cands[slot] = {};
        for _, piece in ipairs(pieces) do
            if (piece.Equippable) and (pieces_of.can_wear(piece, slot, who, withSub)) then
                local v = vector(piece, slot, mode, petTypes);
                if (next(v) ~= nil) then
                    cands[slot][#cands[slot] + 1] = { piece = piece, v = v };
                end
            end
        end
    end

    local choice, used, totals, ranks = {}, {}, {}, {};
    local slotBlocks = (vdata.SlotBlocks ~= nil) and vdata.SlotBlocks() or {};

    -- A piece can take other slots as well as its own (a Tunic takes the head: the server's rslot), so
    -- nothing can be worn there with it. The slots already filled that clash with putting c in slot:
    local function blocks(piece, slot)
        return ((piece.Server.rslot or slotBlocks[piece.Id] or 0) & vdata.SlotBit[slot]) ~= 0;
    end
    local function clashes(c, slot)
        local list = {};
        for t, held in pairs(choice) do
            if (t ~= slot) and (blocks(held.piece, slot) or blocks(c.piece, t)) then
                list[#list + 1] = t;
            end
        end
        return list;
    end

    local function rounds()
    for round = 1, 8 do
        local changed = false;
        for _, slot in ipairs(slots) do
            pace();
            local held = choice[slot];
            if (held ~= nil) then
                apply(totals, held.v, -1);
                used[held.piece] = nil;
            end
            local base = total(mode, totals);
            local ranked = {};
            for _, c in ipairs(cands[slot]) do
                if (not used[c.piece]) then
                    -- worth what it adds less what it pushes out of the slots it clashes with
                    local out = clashes(c, slot);
                    for _, t in ipairs(out) do apply(totals, choice[t].v, -1); end
                    apply(totals, c.v, 1);
                    ranked[#ranked + 1] = { c = c, gain = total(mode, totals) - base, out = out };
                    apply(totals, c.v, -1);
                    for _, t in ipairs(out) do apply(totals, choice[t].v, 1); end
                end
            end
            -- best gain first; on a tie the piece already held stays, so the rounds settle
            table.sort(ranked, function(a, b)
                if (math.abs(a.gain - b.gain) > 1e-9) then return a.gain > b.gain; end
                if (a.c == held) ~= (b.c == held) then return a.c == held; end
                return a.c.piece.Id < b.c.piece.Id;
            end);
            ranks[slot] = ranked;
            local best = (ranked[1] ~= nil) and (ranked[1].gain > 1e-9) and ranked[1].c or nil;
            if (best ~= nil) then
                for _, t in ipairs(ranked[1].out) do
                    apply(totals, choice[t].v, -1);
                    used[choice[t].piece] = nil;
                    choice[t] = nil;
                    changed = true;
                end
                apply(totals, best.v, 1);
                used[best.piece] = true;
            end
            if (best ~= held) then
                changed = true;
            end
            choice[slot] = best;
        end
        if (not changed) then
            break;
        end
    end
    end
    rounds();

    -- A set bonus that needs several pieces is never reached one slot at a time (no single piece of
    -- it beats the best piece alone), so each set this set values is tried whole: its pieces put in
    -- every slot they can fill, the rest kept, and the result kept when it scores higher.
    local function trySets()
        local improved = false;
        for _, st in ipairs(mode.sets or {}) do
            local trial, taken, placed = {}, {}, 0;
            for _, slot in ipairs(slots) do
                for _, c in ipairs(cands[slot]) do
                    if (st.members[c.piece.Id]) and (not taken[c.piece]) then
                        trial[slot] = c; taken[c.piece] = true; placed = placed + 1;
                        break;
                    end
                end
            end
            if (placed >= st.min) then
                for _, slot in ipairs(slots) do
                    local c = choice[slot];
                    if (trial[slot] == nil) and (c ~= nil) and (not taken[c.piece]) then trial[slot] = c; taken[c.piece] = true; end
                end
                local t, fits = {}, true;
                for slot, c in pairs(trial) do
                    apply(t, c.v, 1);
                    for other, d in pairs(trial) do
                        if (other ~= slot) and blocks(d.piece, slot) then fits = false; end
                    end
                end
                if (fits) and (total(mode, t) > total(mode, totals) + 1e-9) then
                    choice, used, totals, improved = trial, taken, t, true;
                end
            end
        end
        return improved;
    end
    if (trySets()) then rounds(); end

    local set = {};
    for slot, c in pairs(choice) do
        set[slot] = c.piece;
    end
    return set, ranks, total(mode, totals), totals;
end

return score;
