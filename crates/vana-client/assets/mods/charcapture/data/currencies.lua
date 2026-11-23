-- Currency packet layouts (s2c 0x113 / 0x118), from vanadreams-launcher charcapture.
local M = {}

M._store = nil

M.CURRENCY_1 = {
    { 4, 'i', 'sandoria_cp' }, { 8, 'i', 'bastok_cp' }, { 12, 'i', 'windurst_cp' }, { 16, 'H', 'beastman_seal' },
    { 18, 'H', 'kindred_seal' }, { 20, 'H', 'kindred_crest' }, { 22, 'H', 'high_kindred_crest' },
    { 24, 'H', 'sacred_kindred_crest' }, { 26, 'H', 'ancient_beastcoin' }, { 28, 'H', 'valor_point' },
    { 30, 'H', 'scyld' }, { 32, 'i', 'guild_fishing' }, { 36, 'i', 'guild_woodworking' },
    { 40, 'i', 'guild_smithing' }, { 44, 'i', 'guild_goldsmithing' }, { 48, 'i', 'guild_weaving' },
    { 52, 'i', 'guild_leathercraft' }, { 56, 'i', 'guild_bonecraft' }, { 60, 'i', 'guild_alchemy' },
    { 64, 'i', 'guild_cooking' }, { 68, 'i', 'cinder' }, { 72, 'B', 'fire_fewell' }, { 73, 'B', 'ice_fewell' },
    { 74, 'B', 'wind_fewell' }, { 75, 'B', 'earth_fewell' }, { 76, 'B', 'lightning_fewell' },
    { 77, 'B', 'water_fewell' }, { 78, 'B', 'light_fewell' }, { 79, 'B', 'dark_fewell' },
    { 80, 'i', 'ballista_point' }, { 84, 'i', 'fellow_point' }, { 88, 'H', 'chocobuck_sandoria' },
    { 90, 'H', 'chocobuck_bastok' }, { 92, 'H', 'chocobuck_windurst' }, { 96, 'i', 'research_mark' },
    { 100, 'B', 'tunnel_worm' }, { 101, 'B', 'morion_worm' }, { 102, 'B', 'phantom_worm' },
    { 104, 'i', 'moblin_marble' }, { 108, 'H', 'infamy' }, { 110, 'H', 'prestige' }, { 112, 'i', 'legion_point' },
    { 116, 'i', 'spark_of_eminence' }, { 120, 'i', 'shining_star' }, { 124, 'i', 'imperial_standing' },
    { 128, 'i', 'leujaoam_assault_point' }, { 132, 'i', 'mamool_assault_point' },
    { 136, 'i', 'lebros_assault_point' }, { 140, 'i', 'periqia_assault_point' }, { 144, 'i', 'ilrusi_assault_point' },
    { 148, 'i', 'nyzul_isle_assault_point' }, { 152, 'i', 'zeni_point' }, { 156, 'i', 'jetton' },
    { 160, 'i', 'therion_ichor' }, { 164, 'i', 'allied_notes' }, { 168, 'H', 'aman_vouchers' },
    { 170, 'H', 'login_points' }, { 172, 'i', 'cruor' }, { 176, 'i', 'resistance_credit' },
    { 180, 'i', 'dominion_note' }, { 184, 'B', 'fifth_echelon_trophy' }, { 185, 'B', 'fourth_echelon_trophy' },
    { 186, 'B', 'third_echelon_trophy' }, { 187, 'B', 'second_echelon_trophy' }, { 188, 'B', 'first_echelon_trophy' },
    { 189, 'B', 'cave_points' }, { 190, 'B', 'id_tags' }, { 191, 'B', 'op_credits' }, { 192, 'i', 'traverser_stones' },
    { 196, 'i', 'voidstones' },
    { 200, 'i', 'kupofried_corundums' }, { 204, 'B', 'pheromone_sacks' }, { 206, 'B', 'rems_ch1' },
    { 207, 'B', 'rems_ch2' }, { 208, 'B', 'rems_ch3' }, { 209, 'B', 'rems_ch4' }, { 210, 'B', 'rems_ch5' },
    { 211, 'B', 'rems_ch6' }, { 212, 'B', 'rems_ch7' }, { 213, 'B', 'rems_ch8' }, { 214, 'B', 'rems_ch9' },
    { 215, 'B', 'rems_ch10' }, { 224, 'H', 'reclamation_marks' }, { 228, 'i', 'unity_accolades' },
    { 232, 'H', 'fire_crystals' }, { 234, 'H', 'ice_crystals' }, { 236, 'H', 'wind_crystals' },
    { 238, 'H', 'earth_crystals' }, { 240, 'H', 'lightning_crystals' }, { 242, 'H', 'water_crystals' },
    { 244, 'H', 'light_crystals' }, { 246, 'H', 'dark_crystals' }, { 248, 'H', 'deeds' },
};
M.CURRENCY_2 = {
    { 4, 'i', 'bayld' }, { 8, 'H', 'kinetic_unit' }, { 10, 'B', 'imprimaturs' }, { 11, 'B', 'mystical_canteen' },
    { 12, 'i', 'obsidian_fragment' }, { 16, 'H', 'lebondopt_wing' }, { 18, 'H', 'pulchridopt_wing' },
    { 20, 'i', 'mweya_plasm' }, { 24, 'B', 'ghastly_stone' }, { 25, 'B', 'ghastly_stone_1' },
    { 26, 'B', 'ghastly_stone_2' }, { 27, 'B', 'verdigris_stone' }, { 28, 'B', 'verdigris_stone_1' },
    { 29, 'B', 'verdigris_stone_2' }, { 30, 'B', 'wailing_stone' }, { 31, 'B', 'wailing_stone_1' },
    { 32, 'B', 'wailing_stone_2' }, { 33, 'B', 'snowslit_stone' }, { 34, 'B', 'snowslit_stone_1' },
    { 35, 'B', 'snowslit_stone_2' }, { 36, 'B', 'snowtip_stone' }, { 37, 'B', 'snowtip_stone_1' },
    { 38, 'B', 'snowtip_stone_2' }, { 39, 'B', 'snowdim_stone' }, { 40, 'B', 'snowdim_stone_1' },
    { 41, 'B', 'snowdim_stone_2' }, { 42, 'B', 'snoworb_stone' }, { 43, 'B', 'snoworb_stone_1' },
    { 44, 'B', 'snoworb_stone_2' }, { 45, 'B', 'leafslit_stone' }, { 46, 'B', 'leafslit_stone_1' },
    { 47, 'B', 'leafslit_stone_2' }, { 48, 'B', 'leaftip_stone' }, { 49, 'B', 'leaftip_stone_1' },
    { 50, 'B', 'leaftip_stone_2' }, { 51, 'B', 'leafdim_stone' }, { 52, 'B', 'leafdim_stone_1' },
    { 53, 'B', 'leafdim_stone_2' }, { 54, 'B', 'leaforb_stone' }, { 55, 'B', 'leaforb_stone_1' },
    { 56, 'B', 'leaforb_stone_2' }, { 57, 'B', 'duskslit_stone' }, { 58, 'B', 'duskslit_stone_1' },
    { 59, 'B', 'duskslit_stone_2' }, { 60, 'B', 'dusktip_stone' }, { 61, 'B', 'dusktip_stone_1' },
    { 62, 'B', 'dusktip_stone_2' }, { 63, 'B', 'duskdim_stone' }, { 64, 'B', 'duskdim_stone_1' },
    { 65, 'B', 'duskdim_stone_2' }, { 66, 'B', 'duskorb_stone' }, { 67, 'B', 'duskorb_stone_1' },
    { 68, 'B', 'duskorb_stone_2' }, { 69, 'B', 'pellucid_stone' }, { 70, 'B', 'fern_stone' },
    { 71, 'B', 'taupe_stone' }, { 74, 'H', 'escha_beads' }, { 76, 'i', 'escha_silt' }, { 80, 'i', 'potpourri' },
    { 84, 'i', 'current_hallmarks' }, { 88, 'i', 'total_hallmarks' }, { 92, 'i', 'gallantry' },
    { 96, 'i', 'crafter_points' }, { 100, 'B', 'fire_crystal_set' }, { 101, 'B', 'ice_crystal_set' },
    { 102, 'B', 'wind_crystal_set' }, { 103, 'B', 'earth_crystal_set' }, { 104, 'B', 'lightning_crystal_set' },
    { 105, 'B', 'water_crystal_set' }, { 106, 'B', 'light_crystal_set' }, { 107, 'B', 'dark_crystal_set' },
    { 108, 'B', 'mc_s_sr01_set' }, { 109, 'B', 'mc_s_sr02_set' }, { 110, 'B', 'mc_s_sr03_set' },
    { 111, 'B', 'liquefaction_spheres_set' }, { 112, 'B', 'induration_spheres_set' },
    { 113, 'B', 'detonation_spheres_set' }, { 114, 'B', 'scission_spheres_set' },
    { 115, 'B', 'impaction_spheres_set' }, { 116, 'B', 'reverberation_spheres_set' },
    { 117, 'B', 'transfixion_spheres_set' }, { 118, 'B', 'compression_spheres_set' },
    { 119, 'B', 'fusion_spheres_set' }, { 120, 'B', 'distortion_spheres_set' },
    { 121, 'B', 'fragmentation_spheres_set' }, { 122, 'B', 'gravitation_spheres_set' },
    { 123, 'B', 'light_spheres_set' }, { 124, 'B', 'darkness_spheres_set' }, { 128, 'i', 'silver_aman_voucher' },
    { 132, 'i', 'domain_points' }, { 136, 'i', 'domain_points_daily' }, { 140, 'i', 'mog_segments' },
    { 144, 'i', 'gallimaufry' }, { 148, 'H', 'is_accolades' }, { 152, 'i', 'temenos_units' },
    { 156, 'i', 'apollyon_units' },
};

-- The five 9-bit counts packed into the 64 bits at 216 of 0x113 (Bloodshed, Umbrage, Ritualistic,
-- Tutelary and Primacy plans), low bits first.
M.PLANS = { { 0, 'bloodshed_plans' }, { 9, 'umbrage_plans' }, { 18, 'ritualistic_plans' }, { 27, 'tutelary_plans' }, { 36, 'primacy_plans' } };

local function unpack_at(data, fmt, off)
  local size = (fmt == "B") and 1 or ((fmt == "H") and 2 or 4)
  if #data < off + size - 1 then return nil end
  if fmt == "B" then return string.byte(data, off) end
  if fmt == "H" then return string.unpack("<I2", data, off) end
  return string.unpack("<i4", data, off)
end

function M.read_currency_table(data, rows)
  for _, r in ipairs(rows) do
    local off, fmt, col = r[1], r[2], r[3]
    local v = unpack_at(data, fmt, off + 1)
    if v ~= nil then M._store.currencies[col] = v end
  end
end

function M.read_currencies_1(data)
  M.read_currency_table(data, M.CURRENCY_1)
  if #data >= 224 then
    local lo = string.unpack("<I4", data, 217)
    local hi = string.unpack("<I4", data, 221)
    if lo and hi then
      for _, p in ipairs(M.PLANS) do
        local shift, col = p[1], p[2]
        local v
        if shift + 9 <= 32 then
          v = (lo >> shift) & 0x1FF
        elseif shift >= 32 then
          v = (hi >> (shift - 32)) & 0x1FF
        else
          v = ((lo >> shift) | (hi << (32 - shift))) & 0x1FF
        end
        M._store.currencies[col] = v
      end
    end
  end
  M._store.currencies1_at = os.time()
end

function M.read_currencies_2(data)
    M.read_currency_table(data, M.CURRENCY_2);
    M._store.currencies2_at = os.time();
end


return M
