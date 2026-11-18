## Map session: 0x00E names, index ranges, slot resets, reserved actors, a held actor's despawn (2026-11-14)

<!-- dll-build: 30261102_0 -->

Queue row 147, the "Not done in ours" list of "Map session details LSB does not check" (2026-11-01). Addresses are
build 30261102_0 (FUN_1009b550 and FUN_10099ae0 did not move). client/net.rs (`npc_name`, `name_len`,
`EntityUpdate::reserved`, `in_range`, `name_for`), client/mod.rs (the `NetEvent::Entity` arm, `slot_resets`,
`drop_entity`, `name_update`), client/event.rs (op 0xac, `respawned`, `unbind`), dat/npc.rs.

**0x00E names (asm 0x1009b666..0x1009b7b5).** Read before the despawn and first-update tests, in this order:
1. SubKind 0 / 1 / 5 / 6 / 7 with mask 0x08 at an index from 0x700: the text @0x34. Doors, lifts and ships
   (SubKinds 2..4) never take it: their id words sit there. Ours took @0x34 for every SubKind and dropped an empty
   or odd one; retail writes what is there, an empty name too.
2. SubKind 1 with mask 0x40: the text @0x44, at an index from 0x700 always, below 0x400 only when its first byte
   is above a space (LSB sends mask 0x57 for every equipped NPC, with nothing there). Ours had no such rule.
3. Below 0x400 with mask 0x08, a byte 1 @0x34 and a byte above a space @0x35: the text from @0x35. This one is not
   sized: FUN_10093430 copies 24 bytes from the packet.
4. Else below 0x700 the zone list's name by UniqueNo (FUN_1008a930, the first record with the id), else "NPC"
   (0x1035cb44), on every update. Ours looked the list up for any index and wrote "NPC" only into an empty name.
   From 0x700 the name stays.
- Rules 1 and 2 go through FUN_100dde40(dst, 0x10, src, limit, size): the sub-packet's size less the limit (0x38 /
  0x48, 4 past the text's start), 15 at most. The compare is unsigned (`ja`, 0x100dde59), so a packet that ends
  before the limit still copies 15. Ours read 16.
- FUN_10093430 writes nothing while the actor has a Monstrosity word (+0x210).
- 0x00D (0x10099e36): the name @0x5A with 0x08, limit 0x5c, after the first-update test and never on a despawn.
- Ours named entities again from the zone list once it loaded; now only the ones that took "NPC" before the list
  was there (retail has the list before any packet).

**Index ranges.** FUN_1009ceb0: an 0x00E for an index of 0x400..0x6ff or from 0x900 is dropped (after the mask-0
test); FUN_1009aad0: an 0x00D for an index outside 0x400..0x6ff is dropped. The wrappers (0x017 asks) run first and
only refuse an index above 0x8ff. Ours had no test.

**Slots.** The actor table is by index. An update whose UniqueNo is not the slot's resets the slot (FUN_1008ee30,
FUN_10092900, FUN_1008a350(0)), and FUN_10099a40 resets every other slot holding the update's id: for 0x00E
whenever its slot held another id or none, and again at each full update; for 0x00D only when its slot held
another id, or with the full mask 0x1f. Ours keys entities by id: an id arriving under an index that another
entity held left that entity behind, and an id arriving under a new index moved the entity. Now the old holder
goes, and a moved id is a new actor there (a partial update asks for it; an 0x00D that may not sweep leaves the
old one until the full update).

**Reserved actors.** Entity +0x138 bit 31, set by event op 0xac sub 2 and cleared by sub 3 (which then asks for
the actor, c2s 0x016) or by the slot's reset; an event's end leaves it. FUN_1009b550 reads it once (0x1009b632):
- the name rules run as for any actor;
- a despawn (0x20) is not taken (0x1009b7f0): no hide, no +0x145 = 0;
- a first update needs no full mask (0x1009b963);
- mask 0x01 writes the position, heading, speeds, counter and @0x18's bits 13..15, unless +0x13c bit 0 is set
  (0x1009b9f3); the face target (@0x18 bits 17..) and @0x20's bits 0..2 are skipped (0x1009bc29);
- mask 0x02's claim is skipped (0x1009bcf3), and the handler returns before the general fields (0x1009bda9) and
  the look switch (0x1009c8f5).
- 0x00D has no such test.
- Op 0xac (FUN_100bb180): subs 2 / 3 act on actor@2 (FUN_100afac0(2) / FUN_100afb00), not on the running actor,
  and only when its slot exists. Sub 4: actor@2's +0x13c |= val@6 & 3; bit 0 is the position hold above, bit 1 has
  no reader, the slot's reset clears both (FUN_1008a350). Census (`dat::event::status_census::reserve_census`):
  1,434 uses, all in zone 280 (Mog Garden): sub 2 1,377 times (29 on the running actor), sub 3 53 times (1), sub
  4 four times, each with value 0.
- Ours already took actor@2 for subs 2 / 3 and kept bit 0 of sub 4 (`Entity::keep_event_pos`); the update rules
  above are new (`EntityUpdate::reserved`).

**A despawn while an event holds the actor.** 0x1009b8f6..0x1009b93a (0x00D: 0x10099c6a..0x10099cab): every
despawn sets the mark +0x124 bit 12 and +0x145 = 0 (0x00E also puts +0x124's sub-animation fields back to 0x880); the hide
bit (+0x120 bit 14) only when no event holds the actor (+0x120 bit 8, set by the start scan FUN_100aeea0 and
cleared with bit 7 by FUN_1008ee30). The frame pass FUN_10096640 frees a marked actor that is not bound, not held
and not ours. Any later update for the slot clears the mark first (0x1009b7db / 0x10099c07). So a held actor
stays through its event, and:
- a full update before the end keeps it for good. Ours removed it at the end all the same.
- a partial one finds +0x145 = 0: the slot is reset at once, which unbinds it from the event, and the actor is
  asked for again (+0x12c bit 15). Ours applied the partial update. *(inf: after the unbind ours keeps the actor out
  of the VM's poses until the event ends, `detached`.)*
- a plain despawn (no event holds the actor) never calls FUN_1008ee30, so it does not unbind: an actor the VM
  drives that respawns mid-event is posed again (ours: `drop_entity`; only the slot resets use `reset_entity`).
- with no update it goes at the event's end, as before.
`Entity::awaiting_full`, `event::respawned`, `event::unbind` (from `reset_entity`).

**SubKind 7.** FUN_1009b3f0 writes all nine words @0x32..@0x42 into the look slots (+0xfc..+0x10c); ours zeroed
the main, sub and ranged words @0x3E..@0x42.

**Checked.** Unit tests `npc_name_rules`, `index_ranges_and_reserved_view`, `slot_reset_rules`, `looks`. Live
against LSB: zone-list names as before; a static NPC renamed with `renameEntity` shows the sent name (rule 3,
"Renamed Static N": LSB sends 16 bytes); dynamic NPCs (index from 0x700) show their packet names by rules 1 and 2.

**Not done.** Retail keeps a despawned actor's slot, with its look and flags, until the zone changes; ours drops
the entity. So op 0xac sub 2 on a despawned actor does nothing in ours, where retail reserves the hidden slot (the
server's next update then only moves it, and the event shows it with the look it had). The Mog Garden scripts are
the only users.
