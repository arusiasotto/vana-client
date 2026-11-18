## Celestite windows: fe_main, fe_equip, fe_inven and s2c 0x08F (2026-11-15)

<!-- dll-build: 30261102_0 -->

Queue rows 153 and 155 to 159, left open by "Re-baseline to 30261102_0" (2026-11-10). They are one feature: the
Status menu's row 13 no longer opens Alter Ego Points directly but a new menu, with the points list as its first
row and six celestite sets under it. Row 152 (list cell kind 0x4d) found the last piece of it. Built in
`client/celestite.rs`. All addresses are build 30261102_0. Row 154 (the Mog House layout's Move keys,
FUN_101cf930) is not part of this and stays open.

**statcom2 row 13 (row 153).**
- FUN_1014a0b0 (statcom2's frame) enables child 13 once the main job's level is above 98 (DAT_104867f1 > 0x62) and
  key item 0xd21 or, new in this build, 0xd2f is held (FUN_10097e80).
- Enter on it (FUN_1014a1e0, k 12) opens "menu    fe_main" where 30261006_0 opened fp_cat, and shows no page.
- The row's sprite is windowps 845, "Trust Ascension".

**fe_main (row 157).** Object DAT_105795f4, vtable 0x10335680, made in FUN_10147740 with the other Status windows
and freed in FUN_10148100. Layout (384, 48) 112 x 122, in statcom2's place, seven children 16 apart with help
strings 1096 and 1100..1105 (group 0xe); registry flags 0x20000, group 0x81 (so statcom2 is suspended under it).
- Open hook FUN_1014caa0: every child disabled (FUN_10119ff0(5, n)), then, with the level above 98, child 1
  enabled with key item 0xd21 and children 2..7 with 0xd2f (FUN_10119ff0(0xb, n)).
- Key handler FUN_1014cb50, message 5 only: child 1 opens fp_cat, children 2..7 call FUN_10117360(set 0..5). The
  rows read Alter Ego Points, Tank, Melee Fighter, Ranged Fighter, Offensive Caster, Healer, Support (windowps
  843..858). Message 6 is not handled: the generic close with SE 0003, as the registry flags lack bit 2.
- The close hook FUN_1014cb40 closes "menu    fe_main" by name, which does nothing by then.
- The other class the row names (vtable 0x10335638, DAT_10579600, destructor FUN_101480d0) is fp_info, the
  points / 1000 window of Alter Ego Points (draw FUN_1014d780). It is the previous build's class (vtable
  0x10334538 there) at a new address and is already drawn by `aepoints.rs`.

**s2c 0x08F (row 155).** FUN_100e5290 copies 0x2b dwords from the packet's +4 to session +0x2d67c, calls the
callback at +0x2d728 when one is set, and sets bit 5 of +0x40e65. The session's table set-up FUN_100e4340 and its
two resets (FUN_100e4420, FUN_100e44e0) zero the block and clear the bit, so every map connection starts without
it. The block, as its readers use it (FUN_10117af0 returns it only while bit 5 is set):
- +0x00, 8 dwords: bit n is set when celestite n (item 0x72f0 + n) is owned (FUN_10118110).
- +0x20, seven 0x14-byte records by set number. FUN_10117b10 maps set 0..5 to record 1..6; record 0 is never
  read. A record is ten slot bytes (FUN_10117a90: 0 a closed slot, else the slot's label) and the ten celestites
  worn (FUN_10117a30, 0 = none).

**c2s 0x0C5 and 0x0C6 (row 156).**
- 0x0C6 (FUN_100e5260, 4 bytes, no body) asks for the block. fe_equip's open sends it while bit 5 is clear.
- 0x0C5 (FUN_100e5200, 0x10 bytes): the record number (set + 1) at +4, ten celestites at +5, a zero byte.
  FUN_10117b70(set, slot, n) builds it from the block's record: with n not 0 the first slot already holding n is
  emptied, then the slot takes n (0 takes the celestite off). It fails without the block. Nothing changes on the
  client until the next 0x08F.
- Both are queued with FUN_100fc510(id, 1, 1).

**fe_equip (row 158).** Object DAT_104e2d20, vtable 0x10333fe8, constructor FUN_101170f0 (which also makes
fe_inven). The generic list class (FUN_101f7de0): ten rows shown, two cell columns from DAT_1036d18c (x 0 and 36),
rows 18 apart from y 0x13, the cursor band keytops3 428 at y 0x15 drawn whether or not the window has the keys
(+0x49 = 0). Layout (16, 48) 182 x 206, help 0xe 1106, title 0xd 201; registry flags 0x30002, group 0x1c.
- FUN_10117360(set) stores the set (+0x58), opens bluehelp at (16, 256), then fe_inven, then fe_equip on top.
- Open (FUN_101173d0): c2s 0x0C6 as above; +0x50 = sets may change, true in the Mog House (FUN_101cd640(0)) and
  not in Monstrosity (FUN_10097d50); +0x54 (the slot picked) = -1; title 0xd 0xc9.
- Each frame (FUN_101174b0 and FUN_10117580): the ten rows are rebuilt. A row with a slot byte holds cell kind 0xe
  with keytops3 565 + the byte (a 32 x 16 label) and cell kind 0x19 with item 0x72f0 + the celestite worn, both
  0x80808080; its help is 0xe 0x452 + set (FUN_101179d0). The list's count is the number of open slots. With the
  keys, bluehelp shows the cursor row's item (FUN_101ed8c0) or nothing (FUN_101ed990). The draw hook FUN_101176e0
  puts the set's caption, frames 211 + set, at (5, 2).
- Keys (FUN_10117750 under the list handler FUN_101f8280). Left / Right page only with Ctrl or Alt held (+0x47 =
  0), and the pre-filter FUN_10117980 takes Alt+Right / Alt+Left (key functions 0xb5 / 0xb6) for the next /
  previous set, (set + 1) % 6 and (set + 5) % 6, without a sound. The tenth child's Down link is child 1, so Down
  wraps there. Enter: a closed slot is the buzzer. With no celestite picked in fe_inven, the slot is picked, its
  celestite becomes fe_inven's wanted row (+0x54 there) and fe_inven takes the keys (SE 0002). With one picked, a
  change is refused outside the Mog House (system message 0xb2, buzzer); else 0x0C5 goes with that celestite, or 0
  when the slot already wears it, the pick is dropped and fe_inven takes the keys. Escape drops fe_inven's pick
  and hands it the keys (SE 0003), or closes the window. Message 8 (Num+, and the pointer over fe_inven while the
  mouse drives the menus, FUN_10127770) hands fe_inven the keys with SE 0013 when nothing is picked on either
  side, else the buzzer.
- Close (FUN_10117480): bluehelp, the title and fe_inven go.

**fe_inven (row 159).** Object DAT_104e2d24, vtable 0x10334058, constructor FUN_10117c30. The same list class:
eleven rows shown, columns from DAT_1036d194 (x 0 and 18), rows 18 apart from y 4, the band at y 6 only with the
keys (+0x49 = 1), Left / Right always page (+0x47 = 1). Layout (200, 48) 182 x 206; registry flags 0x10002, group
0.
- Rows (FUN_10117e60, see "List cell kind 0x4d"): one per owned celestite n = 1..0xff. Cell 0 is kind 0x4d, the
  half-size icon of item 0x72f0 + n; cell 1 is kind 0x19, its name. The name is 0x80804020 on the picked row (+0x50
  is the row's position), 0x80509050 when the current set wears n (FUN_10118150), and otherwise 0x80808080 only
  when fe_equip's +0x50 is set, the item's level byte (the first byte of its record's +0x14 block) is not above
  the main job's level (FUN_101181a0) and bit set + 1 of the block's second byte is set (FUN_101181d0); else
  0x80404040. A wanted celestite (+0x54) moves the cursor to its row (FUN_101f8690) once.
- Keys (FUN_10118260). Enter: refused outside the Mog House (message 0xb2, buzzer); a grey row is the buzzer. With
  no slot picked in fe_equip the row is picked, the celestite becomes fe_equip's wanted one (+0x60, the cursor
  goes to the slot that wears it) and fe_equip takes the keys. With a slot picked, 0x0C5 goes for that slot with
  the celestite, or 0 when the slot already wears it, the slot pick is dropped and fe_equip takes the keys. Escape
  with nothing picked closes fe_equip (and so both); with a slot picked it drops that pick and hands fe_equip the
  keys. Message 8 hands fe_equip the keys with SE 0013 when nothing is picked.
- bluehelp in item mode (FUN_101edad0) draws the item's description lines from (4, 4), 16 apart, in a frame 16 a
  line + 8 high and at least its layout's height.

**Ours.**
- `net.rs` reads 0x08F into `CelData`; the zone-in handler drops it with the party roster, as the session's zeroing
  does. `celestite.rs` sends 0x0C6 and 0x0C5.
- `status.rs`: child 13's gate takes either key item, and Enter opens fe_main. With game files older than
  30261102 there is no fe_main layout and the row opens fp_cat as before.
- fe_main, fe_equip, fe_inven and bluehelp are drawn from their layouts with the rules above; the mouse follows
  the other list windows (hover moves the cursor, a click is Enter, a right click Escape). The pointer anywhere
  over the other list is message 8 every frame (FUN_101174b0 / FUN_10117d90, FUN_10127770, FUN_1011a0a0), resting
  or not, as retail: after Num+ the keys come straight back, and with a pick held the refusal buzzes each frame.
- The modern layer shows the same state as a panel (docs/modern-ui.md, "Trust Ascension").
- Tests: the block's layout, 0x0C5's body, the name colours, both pick orders, the refusals, the cursors and set
  switch, and the layouts in the game files (`layouts`, real files only).

**Open.** LandSandBoat registers 0x0C5, 0x0C6 and 0x08F but answers nothing yet, so the lists stay empty on it and
the windows were not checked against a server. Which key (if any) besides Num+ and the pointer sends message 8 to
these two windows was not traced further. What the fifteen slot labels (keytops3 566..580) say is drawn, not read.
