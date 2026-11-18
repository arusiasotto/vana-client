## Effect draw order: equal keys draw newest element first (2026-11-15)

<!-- dll-build: 30261102_0 -->

Queue row 150, left open by "Camera shake" (2026-11-10). It replaces the tie rule of "Effect draw order: equal
clamped keys draw in insertion order (Port Bastok's harbour, 2026-10-29)": that entry had the table right and the
insertion order wrong. All addresses are build 30261102_0.

**The table.**
- FUN_100555d0 makes it: FUN_10055300(0x200, 0.0, 512.0) and the draw task FUN_10055620 at task priority 0xc
  (FUN_10046380, the walk FUN_10055520, the reset FUN_100554b0). 0x201 sentinels of 0x20 bytes, sentinel i with
  key i x 512 / 0x200, chained from the last down to the first (+4), so the whole table is one list from far to
  near. Scale +0x14 = 0x201 / 512.
- FUN_100553c0(node): keys FUN_1006ca20 refuses (NaN, an infinity, a denormal) are not inserted. A node already in
  this frame (+0x14 != 0) only counts up. Else k = the key clamped to [0, 512], bucket = round(k x scale) capped at
  0x200, and from that sentinel the walk passes every node whose *raw* key is >= k; the node goes after the last
  one passed.
- So: farther first; equal clamped keys in insertion order, which covers every key past 512; and a key below 0
  (k = 0) goes after the nodes at 0 and above but before every node already below 0, so those draw last, the last
  inserted first.
- One table for all: elements (FUN_100458f0 -> FUN_100555b0, node = element +0x34, key +0x12c), the after-image
  (FUN_1001bc80), and the nodes of FUN_100c63d0 (the actor's frame) and FUN_10042020.

**The insertion order.**
- An element inserts in its own update (vtable +0x20 FUN_10045a40 -> FUN_100458f0), so in task-walk order.
- The element factory FUN_1004e8d0 ends every kind with (0x1005119c..0x100511ba) `FUN_100749b0(elem,
  FUN_10054410())`. FUN_10054410 returns DAT_10354710 = 0xb in the image; its setter 0x10054400 has no caller and
  no reference. FUN_100749b0 -> FUN_10074f80 unlinks the task and puts it right after bucket 0xb's sentinel, the
  front. So the elements update, and insert, newest first, whatever generator made them.
- Generators: the loader FUN_10073430 links a file's resources in file order (+8 = the next one: FUN_100711e0 on
  the previous resource's +8) and runs FUN_10073a60 over that list in three passes; the third runs a generator's
  init FUN_10047ce0, which starts an auto-start unattached one (FUN_100531d0). Its proxy task goes in by
  FUN_10074a00 -> FUN_10075120: before the running task, or the end of bucket 8. So a zone's generators run in
  file order, and their first elements are made in that order.
- The after-image's task (ctor FUN_1005e800, from scheduler op 0x2c in FUN_10057fb0) keeps the base placement
  FUN_100750b0, right after the scheduler's task *(inf: no scheduler task sits in bucket 0xb or later, so it
  inserts before every element)*.

**Ours.**
- `Effects::insert_order` sorted ties by the generator's start and then the element's serial, oldest first. It
  took FUN_10075120 (2019's FUN_10074170), the path only generator proxies use, for the elements' own.
- Now `Effects::table_order` (fx/mod.rs) does the table: keys that are no number are left out, nodes are put in
  walk order (after-images, then elements by `run_order`, newest first), then sorted by clamped key, with keys
  below 0 last and reversed. `draw_order` and `draw_items_keyed` both go through it.
- Port Bastok's harbour (DAT 336 t_ba/effe/esea): `col1` (key 4500, y 9.87), `1sea` (4000, y 9.84), `down` (5000, y
  9.9) in file order, all with depth writes, one persistent element each. Retail draws `down`, `1sea`, `col1`: the
  additive sea over the black layer, and `col1` (the time-of-day colour) fails the depth test under `1sea`. Ours
  drew `col1`, `1sea`, `down`. The water is now near black at every hour: (11, 12, 13) at noon from above, where
  it was (33, 47, 58); (9, 7, 6) at 18:00, where it was (71, 73, 64).
- Retail picture: the Port Bastok opening ("FFXI - Immigration Cutscene: Port Bastok", YouTube C2t1Lp1PfRk, a
  dusk sky) at 21 s, 28 s and 33 s shows the harbour water black, about (20, 20, 18) in the video. That is the
  only retail picture checked; none at noon.
- Port San d'Oria (DAT 332 t_sa/effe): `col1` 0.2, `down` 0, `sea2` and `sea1` -100. The two below 0 draw last,
  `sea2` (made first, inserted last) before `sea1`. Same order as before, by the other rule.
- Tests: `table_ties_draw_as_inserted`, `harbour_draws_newest_first` (both harbours, from the game files).

**Not changed.**
- Still open from "Camera shake": ours runs op 0x5f before the frame's emissions, so a new element's first kick
  comes a frame after retail's.
- *(inf)* A scheduler started from an element's update would put its after-image inside bucket 0xb; ours always
  inserts after-images first.
