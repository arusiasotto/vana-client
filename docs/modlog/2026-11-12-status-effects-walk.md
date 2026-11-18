## Status effects: what the client does by effect id (2026-11-12)

Every reader of our own effect list in FFXiMain 30261102_0, and what ours does. The list is `DAT_10486be0` (32 x u16,
0xffff empty; written by s2c 0x037 in FUN_1009d0f0 as `id & 0x3ff`, reset by FUN_10093720). Its readers: FUN_1021fc80
(has effect, 9 callers, all below), FUN_10101e50 (MP cost), FUN_101021a0 (job rule), FUN_10102430 (valid targets),
the buff window FUN_10229200 and the cancel FUN_100a0590. The ids are `dat::effect`.

### Bind: speed 0
- The client never reads Bind (11). The server roots a player with Speed 0 (LSB's bind sets the base speed 0, so
  0x037 carries 0 into actor +0x15c). FUN_100a6240 takes vt+0x1a0 as it is (x2 riding, at most 30); the move vector
  is the input times it, so at 0 it is the no-input path: +0x598 = 0, no step, and FUN_100a8000's locked / strafe
  speeds scale the same zero vector. Autorun's vector is first cut to the tick's move (zero) and the
  `|vector| <= 0.001` test ends it. The tail after LAB_100a6e57 still turns a free, unlocked third-person heading to
  the input by the camera.
- Ours took Speed 0 as "not set" (5.0). Now 0 is 0 (`run_speed`), autorun and /follow end (`autorun_ends`), no step
  in any mode and the keys turn us in place (`rooted_step`). Live: bound, autorun stayed put for 3 s; the build
  before moved 5.3 units.

### The other readers
- Log-out / shut-down prompts (FUN_10161fc0 / FUN_10161f30, main menu rows 0xb / 0xc, callers FUN_10160960 /
  FUN_101609f0) open only when FUN_10096270 passes: K.O. 0, sleep 2, petrification 7, stun 10, terror 28
  (`prompt_held`; they opened under any effect).
- Recast at our cast's end (FUN_1022b330 / FUN_1022c940): none under Chainspell 48 or Spontaneity 230.
- The magic check FUN_1022e540, job rule FUN_101021a0 (`Actions::can_cast_now`): +0x44 bit 5 GEO main only; bit 3 on
  SCH needs Tabula Rasa 377; bit 4 needs Elemental Seal 79 unless the main job is RUN (23); bit 2 on SCH needs the
  addendum of the spell's school (White 401, Black 402) or Enlightenment 416. A job failing its rule leaves the spell
  to the other job (bits 4 and 5 are main-job tests only), then to the job points.
- MP cost FUN_10101e50 / FUN_10102050, rounded up each step by FUN_10102180 (`dat::actions::mp_cost`; magic check,
  magic list, ability check and list for cost kind 6): Manafont 47 or Manawell 229: 0. White under Light Arts 358 or
  Addendum: White 401: 90 %, Penury 360 50 %, Accession 366 x2 on +0x44 bit 0; without the arts Tabula Rasa 377 90 %,
  else Dark Arts 359 / Addendum: Black 402 120 %. Black mirrored (Parsimony 361, Manifestation 367 on bit 1).
  Abilities (type 99): Apogee 583 150 %.
- Valid targets at the magic list's pick FUN_10102430 (`dat::actions::spell_targets`): Pianissimo 409 widens a
  self-only song to the party, Entrust 584 a self-only geomancy spell without +0x44 bit 5.
- Ability check FUN_10224b70: Saber Dance 410 refuses the row opening list 0xc, Fan Dance 411 list 0xb (code 0xc ->
  table 0x10386124[0xc] = 0x1e -> 0x103763b0[0x1e] = message 7 0xbd). The caller refuses before the row's +0xe
  sub-list test, so the Waltz / Samba list does not open. Trance 376 skips the TP cost (kind 3, 0x178), Manafont 47
  the MP cost (kind 6).

### Not built
- The area display (config 0xc0; FUN_1022cef0 for spells, FUN_10224ac0 for abilities) and its effect rules
  (Pianissimo, Convergence, Divine Seal, Diffusion, Accession, Manifestation, Theurgic Focus, Elemental Seal, Majesty,
  Widened Compass, Entrust, Contradance): ours has no area display.
- `can_cast` is called with 0 job points everywhere, so the job-point branch never passes. Retail also takes our
  Speed from a 0x00D with our own index (FUN_10099ae0); ours from 0x00A and 0x037 only.
