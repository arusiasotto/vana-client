## Zone-in flags, the forced follow, the filtered-line icon, /lsmes (2026-11-11)

<!-- dll-build: 30261102_0 -->

Modlog-gaps queue rows 15, 19, 20, 42 and 55 (the easy tier's leftovers that touch packets and the move step).
Addresses are 30261102_0; the character data block moved +0xb0 from 30261006_0 (old +0x40dac = +0x40e5c, old
+0x40db2 = +0x40e62).

- **Zone-in flags (row 19).** s2c 0x00A carries our own flags in 0x00D's layout: Flags0 u32 @0x18, Flags1 @0x20,
  Flags2 @0x24, Flags3 @0x28. Its handler FUN_100faf90 packs them into the character data and the zone-in
  FUN_10094190 writes them on our new entity before any 0x037 comes:
  - +0x40e5c: bits 10 / 11 / 12 = Flags1 bits 0 / 1 / 2, bit 13 = Flags0 bit 15 (GroundFlag, entity +0x120 bit 20),
    bits 0..2 = u8 @0x2a & 7, bit 7 = Flags2 bit 31 (auto-party, +0x124 bit 21), bits 8 / 9 = Flags2 bits 29 / 30,
    bit 3 = Flags3 bit 1 (+0x140 bit 3), bits 5 / 4 = Flags3 bits 4 / 5 (+0x12c bits 25 / 27), bit 6 = u8 @0xaf bit 0.
  - +0x40e60: bits 2 / 3 = Flags1 bits 11 / 12 (seeking, anonymous: +0x124 bits 20 / 23), bit 5 = bit 13 (+0x124 bit
    24), bit 4 = bit 14 (away, +0x124 bit 22), bit 6 = bit 15, bits 7 / 8 / 9 = bits 16 / 17 / 18 (PlayOnline,
    LinkShellFlag, link dead: +0x124 bits 26 / 27 / 28), bits 10 / 11 = bits 19 / 20 (+0x128 bits 4 / 5), bits 13..15
    = u8 @0x23 & 7 (the GM level, +0x128 bits 11..13).
  - +0x40e62: bit 0 = Flags1 bit 28 (+0x128 bit 16), **bit 1 = Flags1 bit 29 (InvisFlag, +0x128 bit 6)**, bit 3 =
    bit 31 (bazaar, +0x128 bit 9), bit 4 = Flags2 bit 25 (+0x12c bit 10), bit 7 = Flags2 bit 28 (GmIconFlag, +0x12c
    bit 18); +0x40e94 = Flags1 bit 27 (HackMove, +0x128 bit 14); +0x40e90..92 = the linkshell colour @0x24..0x26.
  - The entity is new, so the flags the zone-in does not write start clear (frozen +0x128 bit 15, charmed +0x12c
    bit 13, sneak, New Adventurer, mentor, allegiance).
  - Ours: `net::zone_in_plate` reads them from the 0x00A and the ZoneIn handler makes them our plate; the model
    radius, the Monstrosity fields and the zone's pool flag, which only 0x037 carries, stay until it comes. Before
    this our plate kept the last zone's 0x037 until the new one arrived. LSB's 0x00A sets none of these bits (its
    Flags1 holds only size and gender), so on LSB the flags are clear for the frame or two before its 0x037.
- **/lsmes (row 55).** FUN_100805f0 prints 7 0x71 unless linkshell 1 is worn **and** our entity's +0x124 bit 27
  (LinkShellFlag: 0x037 u32 @0x28 bit 25, at zone-in 0x00A Flags1 bit 17) is set; /ls2mes (FUN_100807d0) tests only
  the worn shell. Ours: `linkshell::lsmes` now needs `my_plate.marks.ls` for linkshell 1. The other two parts of the
  row were already as retail: Escape on link2..4 is the generic close with the focus back on link5, and "/lsmes
  level" sends c2s 0x0E4 (LSB only logs it, so nothing is printed there).
- **The filtered line's icon (row 20).** The "icon-bearing filtered shout / yell" is the Misc. 4 chat filter's
  second verdict. In the 0x017 handler FUN_100e37a0, FUN_100da5e0 returning 2 on kinds 1, 0x1a, 0x22 and 0x23 swaps
  the text for group 9 0x159 and sets a flag; the line builders then put the icon pair 0xEF 0x4D in front of the
  name: the shout FUN_100da170 "%s%c%c%s : %s", the yell FUN_100da200 "%s%c%c%s[%s]: %s" (both printed through
  FUN_100d9e50, the printer without the whole-line cut, with the name and the text cut on their own by
  FUN_10191210), the assist lines FUN_100da380 "%s%c%c%s(%c) : %s" and, with a rank, FUN_100da2a0
  "%s%c%c%c%c%s(%c) : %s" (rank icon first). Ours: `chat_line` takes `filtered` from `spamfilter::screen` and adds
  the pair. Our cut is already per field (net.rs chat_text), so nothing else changes.
- **The forced follow (row 42).** s2c 0x037 u16 @0x46 goes to our entity +0x2a2 (0x1009d846; LSB's
  `warp_target_index`, which it never sets), cleared at entity init. FUN_10097a40 resolves it through the actor
  table. Its readers:
  - FUN_100a6240 (our move step), first thing: with a live target T, d = T's position - ours; the move is d x 0.25
    (FUN_100272e0), or none when the horizontal distance less our radius (FUN_100aaef0) is under 0. It is added
    to the frame's move and the function returns, before the input, the bump test and every turn. Third person:
    yaw = -atan2(z, x) of the move when it has an x or a z. First person (DAT_10489130): our yaw goes a quarter of
    the wrapped difference toward T's yaw (+0x18).
  - FUN_100cd040: in first person T is not drawn (already noted in "The near-camera fade's tail").
  - FUN_100d0510: in first person T has no name plate.
  - FUN_100c63d0 (the actor frame): our turn toward the move direction is skipped while T exists.
  - FUN_10084aa0 (drawobj vtable +0x12c) returns T's drawobj; no caller found.
  - The move step runs only where our input would (FUN_100a57f0 / FUN_100a5dc0): not dead, resting, seated,
    synthesising or in a chair, not in an event, not charmed.
  - Ours: client/forced.rs (`step`, `face`, `ease`), `World::my_pull` from SelfStatus, the move step in mod.rs
    (one quarter per 2-tick step, through the ground walk, no bump), `near_fade_tail`'s `led` and the plate gate.
    The run motion while pulled is ours *(inferred)*. Not seen live: no server we have sends the field.
- **Scheduler ops 0x11..0x14 (row 15).** The "other movement modes" of FUN_100a57f0 (+0x103 FUN_100a9fc0 close in
  on an actor, +0x104 FUN_100aa1f0 back to its own point, both ahead of the knockback) are set only by scheduler
  ops 0x11 / 0x13 (FUN_100aa380) and 0x12 / 0x14 (FUN_100aa3b0). The op histogram of every scheduler in every DAT
  (`light_op_census`, 2026-11-10) has no op 0x11, 0x12, 0x13 or 0x14 at all, so no game file can start either mode.
  Not built; closed as dead in the data.
