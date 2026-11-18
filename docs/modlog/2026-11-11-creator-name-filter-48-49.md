## Character creator: the name filter (2026-11-11)

<!-- dll-build: 30261102_0 -->

modlog-gaps items 48 and 49: the creator's local name filter and the check on random names. FFXiMain addresses are
30261102_0 (the code comments beside older creator notes keep their 30261006_0 ones, given here in brackets);
polcore is the US viewer's POLCore.DLL as in the Friend List entries (re-notes/builds/polcore). Everything below was
read in Ghidra and checked in Rizin (Ghidra drops the operands of the 64-bit shift helper in the block cipher), and
the port was then run against polcore itself: a small Windows program under Wine loads polcore.dll and calls
FUN_1004a110 / FUN_1004a200 and the four parts directly; over 352,706 names (every word of the dictionary alone,
with letters and skipped characters added, cut and changed, joined in pairs, plus random ASCII, random bytes and
two-byte text) all five answers per name are the same as ours.

**FFXiMain.**

- The filter is the object DAT_10663f70 [DAT_10662db8]. Load FUN_101bb7f0 → FUN_101bba50 [FUN_101ba480] reads
  "entryz.dic" from PlayOnline's file category 0x13 into a buffer tagged "VulgarName" and gives it to polcore
  +0x1154; a read that fails or a 0 from polcore is a failed load (−1). Test FUN_101bb810 → FUN_101bbaf0
  [FUN_101ba240 → FUN_101ba520]: −1 with nothing loaded or no name, else `polcore +0x1158(matcher, name, strlen) == 1`.
- The creator loads it when it opens (FUN_10244c00 [FUN_102435f0]) and unloads it on every way out.
- World step, Enter on the pass (FUN_1023ad30 [FUN_10239720], the call at 0x1023b905 [0x1023a2f5]): after the pass
  length (FFXI-3111) and the name length (under 3: FFXI-3110), any answer but 0 is error 0x142, FFXI-3322, and the
  name step. So a refused name and a dictionary that did not load both refuse. Only a 0 goes on to the comparisons
  with the earlier checks and the request.
- Random names (Num+, FUN_10239940 [FUN_10238330], the call at 0x10239a30 [0x10238420]): the composed name is put in
  the text input only when it is under 16 bytes and the filter answers 0. Otherwise nothing changes, and the next
  Num+ rolls again.
- Events: op 0x71 sub 3 (FUN_100b7e10 case 3) writes `FUN_10094160(text) != 1` to its operand, where FUN_10094160
  loads the filter, tests the input window's 16 bytes and unloads it, and answers "allowed" when the load fails. So
  the operand is 1 for a refused name and 0 otherwise.
- Not built: the name step's window message 0xc (FUN_10239b10 [FUN_10238500] case 0xc) makes a name another way
  (FUN_10239cc0 [FUN_102386b0]) and tests it the same way; nothing of ours sends that message yet.

**The dictionary file (polcore FUN_1004a110).** 8 u32, then four sections: offset (from 0x20) and size of each. The
sizes plus 0x20 must be the file's size. Retail's is 626,608 bytes: sections of 0x9640, 0x73ff8, 0xdca8, 0xdcb0.

- Every section is packed (FUN_10001fd0, sizes a multiple of 8). Key setup FUN_100019b0: 8 bytes from the key's two
  u32 (the second rotated right 16, then the first rotated left 8), byte 0 + 0x45, then for i = 1..7
  `b[i] = (b[i-1] << 2) ^ (b[i] + b[i-1] − 0x2c) ^ 0x45`; that u64 and 31 more, each 5 × the one before. Block n uses
  key n & 0x1f. FUN_10001eb0: each byte xor the packed byte before it (the first xor `(n as u8) ^ 0x45`), then 8
  rounds of `x + 0x78 − key byte` (the table at 0x100c5b7c is x + 0x78). FUN_10001df0: the 8 bytes as a u64, minus
  the key, xor a position word (the byte position repeated at 10-bit steps, + 0xa1652347), xor the key, halves
  swapped. FUN_10001f20: the last block is the result word and a sum, bytes 0 and 4 of every block before it; a wrong
  sum or a negative result word fails the load.
- Section 0, key (0, 0), is the exact-name table (FUN_10049db0): 0x400 u32 buckets (the offset of an entry, −1
  none), an entry being the offset of its name and of the next entry. Lookup FUN_10049e40: characters in a fixed bit
  set (DAT_100f5934: NUL, 0x20..0x2f, 0x3a..0x40, 0x5b..0x5f, 0x7b..0x7e, 0x81, 0x84, 0x87) are dropped and A..Z
  lowered; the bucket is ((first kept as a base-36 digit) << 5 xor (second as one)) + every kept character (as
  signed chars), low 10 bits; the name matches an entry when the kept characters are the entry's, all of them.
- Sections 1..3, key (1, 0), are word engines (FUN_10049100), the same engine the chat's "vulgar2.dic" uses. After
  unpacking: +0x00 the mask mode and +0x04 the mask characters (the name dictionary overwrites these 8 bytes with
  mode 0 and 'X'; only the mask modes read them), +0x10 / +0x30 bit sets of skipped characters (single or first
  byte / second byte), +0x50 / +0x150 the classes of a two-byte character's first / second byte (0: not one),
  +0x250 the two-byte fold table (u16 by first class + second class × 0x30), +0x4930 the single-byte fold table
  (retail's lowers A..Z), +0x4a30 / +0x4a34 the offsets of the word tree and of a tree of allowed words.
- A tree: four offsets (from the tree + 0x48f4) to the child table (u16), the keys (u16, stored negated), the
  strings (bytes, stored negated) and the nodes; +0x10 "fold two-byte characters"; +0x14 the first node by two-byte
  character; +0x46f4 the first node by folded single byte. A node is 8 bytes: kind, key count, child base (u16),
  key or string offset (u32). Kind 1 branches on the next character (binary search of its sorted keys,
  FUN_10049910; the child is `children[base + index]`, and no base or a 0 child ends a word). Kind 2 is a run of
  characters that must follow (then `children[base]`, the same rule). Skipped characters in the text are stepped
  over inside a word (FUN_100495f0).
- Matching FUN_100491e0(engine, text, length, mode): at each position, a skipped character is stepped over; a word of
  the allowed tree is stepped over whole; a word of the word tree answers by mode. 3: yes. 1: yes when only
  skipped characters came before it. 2: yes when only skipped characters follow it. Modes 1 and 2 answer at the
  first word found, so a later word in the right place does not count. (Modes 0 and 4 are the chat mask, FUN_10049960;
  not built.) One oddity kept: after a match the width of "the first character" is read at the end of the match, not
  at its start.
- The test FUN_1004a200, in this order: engine 1 in mode 3 (a word anywhere), the exact names, engine 2 in mode 1 (a
  word at the start), engine 3 in mode 2 (a word at the end). Retail's file holds about 19,500 words and names;
  its allowed tree is what lets a name through that merely contains a short word.

**Ours.**

- `poldic.rs`: `unpack`, `Engine` (`matches` with `Place::Anywhere / Start / End`), `NameDic` (`parse`, `refuses`)
  and `NameFilter` (`load`, `test`, `creator_refuses`, `event_refuses`). The engine is its own type so the chat mask
  (modlog-gaps item 75) can add the mask modes to it.
- The dictionary is the player's own file and is not in the repository. `vana-client install` copies "entryz.dic"
  out of the setup's PlayOnline/PlayOnlineViewer.msi (its one cabinet is the stream "simple.cab" inside the MSI; the
  file's MD5 is checked against MsiFileHash) to `<game folder>/PlayOnlineViewer/data/dic/entryz.dic`, which is
  where a Windows install has it beside "FINAL FANTASY XI". The first-start download does the same.
  `vana-client dictionary SOURCE` does only that, for an install made before (SOURCE: the setup's part 1, an
  extracted copy, or the MSI). ffxi-wrapper installs through `vana-client install`, so it needs no change.
- Creator: FFXI-3322 and the name step after the length checks; a refused random name is dropped. Event op 0x71
  sub 3 answers through `Host::name_refused`.
- The filter loads off the UI thread when the creator opens (the name step waits for it) and is dropped on every way
  out, as retail unloads it.
- The copy takes the "entryz.dic" File row whose component installs and whose directory resolves to
  SquareEnix\PlayOnlineViewer\data\dic under INSTALLDIR, as `install` picks rows (the US viewer has one).
- A node with no keys still compares key 0 (polcore's caller passes count − 1 as the signed upper bound). A run node
  with no characters uses no byte; more of them in a row than the section can hold nodes is a damaged tree, where
  polcore recurses without end, and ours gives no match.
- Deviation: with no dictionary file at all, retail would refuse every name (the load fails). Installs made before
  this change have no file, so there the creator lets the name through, logs a warning that names the `dictionary`
  command, and leaves the check to the server. A file that is there and does not load refuses, as retail.
- `cabx::extract_all` takes entries that share bytes (same folder offset and size, WiX's stored-once copies) as one
  run: the bytes are streamed once, to the first wanted entry of the run, and every other wanted one is copied from
  it, whichever entry comes first (the viewer's cabinet has such runs; before, an unwanted first copy stopped the
  extraction). An entry that overlaps another's bytes without being a copy still fails, wanted or not.
