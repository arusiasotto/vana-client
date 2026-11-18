## Character creator: random names by race (2026-11-11)

<!-- dll-build: 30261102_0 -->

Queue row 164, and what "Creator random names" really is: until now Num+ on the name step gave every race an
adjective + noun, which is retail's Galka generator only. Retail has one generator per race. This closes the "Not
built" bullet of the name filter entry (2026-11-11). Addresses are FFXiMain 30261102_0; polcore is the US viewer's.
Read in Ghidra, the FPU and calling details in Rizin, and the port was then run against FFXiMain's own code (below).

**The key and the message.** win_chmkname's per-frame key check (vtable +0x28, FUN_10239ae0) sends the window its
own message 0xc when DIK 0x4e (Num+) is pressed. FUN_10239b10 case 0xc: `rand() % 10 != 7` asks polcore for the
signed-in member's slot (common table +0x2f8, polcore FUN_10018f60) and that slot's 0x28-byte record (+0x2b4,
FUN_10018ff0), and prints the 15-character handle at record + 8 into a hint; one time in ten the hint stays empty.
Then `FUN_10239cc0(race, face, hint, out)` with the race window's and the face window's selections
(DAT_1066a164 + 0x14, DAT_1066a16c + 0x14; both 0..7). A 0 answer with a name under 16 bytes that the name filter
(FUN_101bb810) allows goes into the text input; anything else changes nothing.

**FUN_10239cc0, by race.** Cases 2..6 are tried twice while the name comes out empty.

- 0 / 1, Hume man / woman (FUN_10236a70): one 16-byte record of a name list, `rand() % count` (counts at 0x10388544,
  the files' sizes / 16). Men: file 0x7c01 for face 5, 0x7c03 for face 7, 0x7c05 for the rest. Women: 0x7c00 for
  face 6, 0x7c02 for face 5, 0x7c04 for the rest. The read is asynchronous (FUN_101c5df0, a thiscall on
  DAT_10663f84 with a buffer callback and a done callback); the window's draw (FUN_102397e0 → FUN_10239940) picks
  the name up when the done flag DAT_1066a198 is set, tests it the same way and sets the text.
- 7, Galka (the function Ghidra names after its "Error: Selected adj file not in range" string, 0x10236920): as
  built before. Noun `rand() % 981` of 0x7c07, its length class from the weights at 0x103884c0, an adjective class
  `floor(log2(rand() % (2 ^ (11 − class) − 1)))` (1 for a 0; retail computes ln × 1 / ln 2 through the FPU and
  truncates, which is the whole part of log2 at the CRT's 53-bit precision), adjective `rand() % count + first`
  of 0x7c06 (0x103884ec / 0x10388518). FUN_10239940 joins adjective + noun; 16 letters or more is cut to 16 and then
  fails the length test.
- 2, Elvaan man (FUN_102365d0): syllables from a 67-row, 7-column table (pointers 0x10387d50, rows used per column
  0x103884a4), `rand() % rows[column]` each. `rand() % 102` picks the columns: under 7 (1, 3, 5), 14 (1, 4, 6),
  21 (2, 3, 5), 28 (2, 4, 6), 35 (3, 0, 5), 42 (0, 1, 6), 62 (0, 1, 3, 5), 82 (0, 2, 3, 5), else (0, 2, 4, 6).
- 3, Elvaan woman (FUN_10236310): a 22-row, 6-column table (0x10387b28, rows 0x10387d38). `rand() % 100`: under 10
  (0, 1, 3), 20 (0, 1, 5), 30 (0, 2, 4), 40 (0, 2, 5), 70 (0, 1, 2, 4), else (0, 1, 2, 5).
- 4 / 5, Tarutaru: a 32 × 5 table of syllables, consonant row by vowel column (0x10388560; row 0 is the bare
  vowels), with a weight each (0x103887e0). FUN_102377c0 sums the weights: all, per row, per column.
  - A weighted cell is `r = rand() % total`, then the first cell whose running sum has `r <= sum` (so `<=`, not `<`);
    "mode 2" leaves row 0 out.
  - FUN_10237830, one syllable: the cell, then `rand() % 100` under 4 adds "h", under 8 adds the column's vowel
    again; then `rand() % 100` under 9 closes with "n", 11 "p", 12 "m", 13 "t".
  - FUN_10237af0, a rhyming pair: the first as above; the second's row is weighted within the first's column, and
    when that is the same row again its column is rolled within the row. `rand() % 100` then gives the second its
    "h" or doubled vowel: with a plain first, same cell under 45 "h", under 90 vowel, other cell under 5 / 10; with
    a lengthened first, under 10 (same cell) or 90 (other) nothing, exactly that number the other kind. The second's
    closing letter: with an open first `rand() % 100` (other cell), `% 12` (same cell, same lengthening) or `% 50`,
    under 9 "n", 9 "p", 10 "m", 11 "t"; with a closed first it keeps the first's letter unless a second roll
    (`% 100` from 40 up; same cell and lengthening `% 22`, or `% 6 + 9` after an "n") says otherwise. A second half
    that would repeat the first exactly closes with "l". A doubled vowel is the second's own, or one time in ten the
    first's when both close alike.
  - Man (FUN_102379a0), `rand() % 100`: under 40 FUN_10238070 (pair a b, syllable c: a c b c, b rolled again half
    the time, c's first letter doubled by small chances), under 55 FUN_102381b0 (a c b d c), under 58 FUN_102383b0
    (a b c d c), else FUN_102385f0 (two pairs and a syllable: a d c b e c; under 15 letters a 16-way weighted roll,
    0x10388a60, doubles first letters, never before a vowel). Over 15 letters: FUN_102383b0 again, and still over,
    a bare pair (FUN_10237a60).
  - Woman (FUN_10237410), `rand() % 100`: under 40 x z z, under 80 x y z z, then the same with a first letter
    doubled (85: x Z z z, 90: x Y y z z, 95: x y Z z z, 98: x z Z z, else x y z Z z); z is a "mode 2" syllable.
- 6, Mithra (FUN_10236ae0 on the hint's first 15 bytes): FUN_10236b20 keeps the lower-case letters only and, by
  how many are left, adds 0 to 3 syllables (FUN_10236c00: an unweighted cell with the "h" / vowel chance at 8 / 16
  and the usual closing, put in front, at a random place or at the end, the whole kept to 15). FUN_10236d40 then
  goes over it twice. First, three consonants in a row get a vowel pushed in after the first or the second (80 in
  100), two in a row one time in ten (a, e, i, o, u, or y / h). Second, every letter rolls `rand() % 100`: "a" and
  "i" double, take an "h" or a "y" before or after; "e", "o", "u" the same with other numbers; "c" turns to "k" or
  "ch"; "f" to "ff" or "ph"; any other letter is dropped on a 0, and the last letter of a name over 3 is dropped
  under 12 (doubled on a 10). A name equal to the hint or under 3 letters counts as empty.

**Ours.**

- `client/randname.rs`: `Tables` (parsed from the FFXiMain.dll the client already reads, `dat::ffximain`), the eight
  generators, `generate` (FUN_10239cc0 + FUN_10239940) and `roll` (message 0xc). `creator::roll_name` reads one
  record of a list at a time and puts the first letter in upper case as the text input does.
- Nothing of the tables is in the repository. The on-disk DLL has its data section in the clear; the block
  0x10387b28..0x10388aa0 is found by the Galka noun weights (the three small Galka number tables were already in
  our source, since the first random names) and read at fixed distances from them; the syllable pointers go through
  the PE section table. A DLL without that block (or with it twice) gives no tables: then only a Galka gets a
  name, from the lists and those numbers.
- Both callers (Num+ and the modern creator's random button) go through `creator::random_name`: the race, the face,
  and the name filter's check.
- There is no PlayOnline handle here, so the hint is always empty: what retail does when polcore has no member slot
  or record for it (FUN_10239b10: either lookup below 0 leaves the hint empty). A Mithra's name is then built from
  syllables alone. The account login never stands in for the handle: it is not public, and a Mithra roll keeps most
  of its letters.
- The tables load off the UI thread the first time the creator opens; the name step waits for them.
- Not built: retail's reads are asynchronous, so a list name lands a frame or more after the key; ours is there the
  same frame. Retail's fixed stack buffers (a Tarutaru man's 28 bytes) can overflow on names that only very rare
  rolls make; ours just builds the name and cuts it.

**Checked.** A Windows program under Wine maps FFXiMain.unpacked.dll at 0x10000000, replaces rand() (0x10315fe0) with
the CRT's generator on a known seed, the list read, the name filter and the text input with stubs, sets the FPU
to 53 bits and calls FUN_10239cc0 and FUN_10239940 themselves. 1,105,000 names (5,000 per Hume race and face,
200,000 per Elvaan and Tarutaru generator, 10,000 for each of 22 handles for the Mithra, 5,000 Galka) are the same
as ours letter for letter, and so is the count of rand() calls of every one (test `same_names_as_retail`, run with
`VANA_RANDNAME_RETAIL` set to the harness's output). Not checked live in the creator.
