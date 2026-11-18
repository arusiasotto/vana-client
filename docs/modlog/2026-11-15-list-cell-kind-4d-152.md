## List cell kind 0x4d: the celestite list's icon (2026-11-15)

<!-- dll-build: 30261102_0 -->

Queue row 152, left open by "Re-baseline to 30261102_0" (2026-11-10): build 30261102_0 added a 78th list cell
kind, and the open points were which window sets it and what it means for our list cells. This is an audit: the
cell has one user, the new window "menu    fe_inven", which is not built (queue rows 155 to 159). No drawing code
changes; a test holds the records the cell reads. All addresses are build 30261102_0.

**The cell.**
- The setter FUN_101f60f0(column, kind, value, colour) takes columns 0..7 and kinds 0..0x4d (`cmp dl, 0x4e` at
  0x101f6105; the bound was 0x4d in 30261006_0's FUN_101f4b20). A row is 0x54 bytes: kind bytes at +0, colours at
  +8, values at +0x28, a row id at +0x48, a help string at +0x4c, +0x50 cleared by every set.
- The draw FUN_101f6180(this = row, window, column, x, y, width, alpha) switches on kind - 1 through the 77-entry
  table at 0x101f7b98 (`cmp eax, 0x4c; ja` at 0x101f61a4). Kind 0x4d is the last entry, 0x101f7b57:
  FUN_1015d340(the value's low word, x, y + 2, 0.5, 0, the cell's colour, 0).
- FUN_1015d340(id, x, y, scale, count, colour, flag) is the item icon: FUN_1015cfb0(id) returns the item record
  from the 100-slot store, or 0 while its 0x1400 bytes are still being read, and FUN_1015cb50 then draws the
  record's 32x32 icon at the scale (FUN_10026ad0 for a scale other than 1.0), so here 16x16. The first call after
  the record arrives only makes the texture. With count 0 no stack number is drawn.
- Three older kinds end in the same call and differ only in the place: 0x15 at (x, y), 0x42 at (x + 3, y + 3),
  and 0x45 at (x, y + 2) after the frame FUN_10120ff0(x, y + 2, 0x80808080) when FUN_10222300(4, 0x219) is set.
  Kind 0x4d is 0x45 without the frame.

**Who sets it.** A scan of all 211 call sites of FUN_101f60f0 (the pushes read in Rizin; Ghidra drops the
arguments at most of them) finds kind 0x4d pushed once, at 0x1011802d in FUN_10117e60. That is the row builder of
fe_inven (object DAT_104e2d24, vtable 0x10334058), called from its vtable function FUN_10117d90.
- It walks n = 1..0xff and keeps each n whose bit is set in the 0x08F block (FUN_10118110: bit n of the dwords at
  FUN_10117af0()), counts them into +0x58 and allocates that many rows at +0x5c.
- Each row: column 0 is kind 0x4d, value 0x72f0 + n, colour 0x80808080; column 1 is kind 0x19 (the item's name,
  fitted to the column width - 8), value 0x72f0 + n; row id (+0x48) = n; help (+0x4c) = string 0x452 + set
  (FUN_101179d0, sets 0..5) of group 0xe (FUN_101544c0).
- The name's colour: 0x80804020 on the row whose position is +0x50; 0x80509050 when n is already one of the
  current set's ten slot bytes (FUN_10118150); else 0x80404040 unless all of these hold, which give 0x80808080:
  fe_equip's byte +0x50 is set, the row is within ten rows of the cursor (FUN_101f8710) and its record is loaded
  (only those rows ask FUN_1015cfb0 for it), the record's level byte (the first byte of its +0x14 block, record
  store +0x1530) is not above the main job's level (FUN_101181a0, DAT_104867f1), and bit `set` + 1 of the block's
  second byte is set (FUN_101181d0: 1 shifted by FUN_10117b10(set), which maps sets 0..5 to 1..6).
- FUN_101f8630(rows, count, 1) hands the rows to the list; a pending row id at +0x54 then moves the cursor to its
  row (FUN_101f8690).

**The records.** Items 0x72f0..0x73ef are in the 0x7000..0x7400 range (parser FUN_1015de30, our `Kind::K7000`;
the range table DAT_10373198 is unchanged from the one `dat/items.rs` holds). The 30261102_0 files hold 31
celestites at 0x72f1..0x730f ("Celestite (Acc.)" to "Celestite (Weaken)", each with an icon and level byte 99),
"nullitem" at 0x72f0 and empty records after.

**Ours.** There is no shared cell table: each window draws its own rows, and the half-size item icon is already
drawn that way by the windows that have one (the auction list, the shop, the automaton and Monstrosity lists). So
nothing draws kind 0x4d until fe_inven exists, and it is built with that window (queue row 159). The item store
reads the celestite records and their icons from 30261102_0 files today; `celestite_records` holds that.
