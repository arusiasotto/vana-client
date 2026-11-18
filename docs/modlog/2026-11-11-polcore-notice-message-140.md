## Friend List: polcore's notice status and message format (2026-11-11)

<!-- dll-build: 30261102_0 -->

The rest of modlog-gaps item 140 ("polcore's message format and status mapping"), from polcore.dll itself (the US
viewer's POLCore.DLL, PDB path ...\POLCore\MasterUS_UNICODE, 1,066,240 bytes, not packed; Ghidra project and
decompile in re-notes/builds/polcore). FFXiMain addresses are 30261102_0. polcore's shifts and the notice handler
checked in Rizin (Ghidra folds the 64-bit shifts into `__allshl` and missed 689 functions that only the tables
reach).

- The function table FFXiMain calls (DAT_10457bdc, from IPOLCoreCom::GetCommonFunctionTable) is polcore's
  DAT_100c4180; MODLOG's "slot n" is offset n x 4 in it. Used here: +0x30c ChangeMyStatus (FUN_10019b90), +0x338 our
  open status (FUN_10018ec0), +0x438 make header (FUN_100150e0), +0x43c read data (FUN_10015400), +0x440 write
  data (FUN_10015260), +0x490 turn a header round (FUN_10015050), +0x10bc a type's title (FUN_10015820), +0x10c0
  set a title (FUN_10015730).
- Status notice -> friend entry (FUN_10017560, called through FUN_1001c9b0 from the notice handler at
  0x100160a0..; polcore's entry is 200 x 0xb0 at DAT_10109288, the same +8 / +0xc words FFXiMain reads). The
  handler passes the block (header +0x10) only when the extension's flag byte has bit 0, and only for a notice
  newer than the entry's age (+0x10, u64; an equal age is dropped). Then:
  - +0x10 connected: 0 clears entry bits 11 and 12, 1 sets both, 2 sets 11 and clears 12; any other value clears
    both and leaves the rest of the block unread.
  - +0x11 Status: bits 13..15 = (Status - 1) & 7, and 5 or more becomes 0 (0x1001762e `dec eax; and eax, 7`, then
    `cmp ecx, 0xa000`). So 1 offline -> 0, 2 online -> 1, 3 away -> 2, as ours had it; 0 and 6 up are offline.
    Nothing in this build sends 4 or 5 (entry 3 and 4, FFXiMain's third online icon and its "Ignore List" bar).
  - +0x12: bit 0 -> entry bit 16 (playing), bits 1..3 -> bits 17..19 (the character slot). +0x13 low nibble ->
    +0xc bits 11..14; +0x14 u16 & 0x3ff -> +0xc bits 1..10.
  - Extension flag 8: a 16-byte character primitive, kept in the entry's record of the active slot (+0x18 + slot x
    16, bit 0 "present"); flags 0x10 / 0x20 / 0x40 carry more blocks (16, 0x68 bytes) FFXiMain's list does not show.
  - The header's ids are XORed with 0x1C273E4567891133 and a session value (FUN_100148e0, DAT_100ffa30); the
    receiver id is left alone for type 17.
- Message data (FUN_10015260): the title up to its NUL (at most 0x80 bytes), 0x07, the text up to its NUL (at most
  0xfff), NUL, then an attachment (at most 0x100000). The reader (FUN_10015400) ends the title at 0x07 (at most 0x7f
  bytes, or the header's length) and the text at the NUL; nothing after the title, or no NUL, returns 0 and
  FFXiMain's read job reports error 0x10.
- What FFXiMain puts in it (FUN_100f3190(title, text, attachment, size, n)): the title through FUN_100f2a10(title,
  n), the text through FUN_100f2ad0 (300 bytes), both never ending on half a two-byte character. n = 0x32: at most
  50 bytes. A smaller n: exactly n bytes, the title over n spaces. n is 0x10 for a friend request (FUN_100f3ba0,
  type 1) and for an accept (FUN_100f39a0, type 9), 0x32 for the rest (FUN_100f3670 / 3730 / 3800 / 38d0).
  - Request (msgline mode 2): title = polcore's title 1, text = the other character's name; the typed name is only
    the entry's name, and a 0x07 typed into it ends it. English "Let's be friends!" is 17 bytes, so the data says
    "Let's be friends"; the Japanese title is 16 bytes exactly.
  - Accept (mode 7): title 9 in 16 bytes ("Friend registrat"), an empty text; the job also builds a second data
    with title 1 and an empty text (kept at the engine's +0xa8.., sent by a later step of the job table 0x10363218;
    not followed further).
  - Decline (FUN_10201690): title 10, text = msgline's buffer. Plain and reply: FFXiMain's own titles (group 9 0x1c /
    0x1f) and the typed text.
  - polcore's titles (10 x 0x80 at DAT_100c8970, by type through DAT_100c8e78: 1, 9, 10, 11, 12, 14, 15, 16, 18,
    19) are Japanese in the file; the viewer sets its language's through +0x10c0. Ours are xiloader's English.
- The header (FUN_100150e0): ids, sender (15 bytes), title (15 bytes, half a two-byte character dropped; +0x42 bit
  12 when the title given was longer), +0x30 a running counter (FUN_10015f00), +0x34 the time (FUN_10052050: the
  sign-on's clock plus elapsed seconds), +0x38 the data's length, +0x3c / +0x3d the two handle numbers *(inf)*, +0x3e
  type << 7 with bit 15, +0x42 bits 1..7 FUN_10012920's value *(inf: the area code)*. The title FFXiMain gives it
  is cut from the data itself
  (FUN_100f4ff0(out, 0x20, data)): bytes up to the first NUL, every run of bytes at or under a space, the 0x07
  among them, as one space, at most 31 bytes: "Let's be friends Bob" in the list reads "Let's be friend". An accept
  or a decline does not build a header: +0x490 swaps the ids and the handle numbers of the request's own header,
  stamps the counter and the time, and FFXiMain sets the type and the length; the title stays the request's.
- Ours (net/profile.rs, client/friends.rs): `encode_body` / `decode_body` are polcore's layout (data this client
  wrote before, title NUL text NUL, still reads), `body_title` and `sjis_cut` FFXiMain's limits, `header_title` the
  list title with its cut flag; requests and accepts send 16-byte titles, an accept an empty text (ours sent the
  typed name), titles and names go out as Shift-JIS; an accept's or a decline's header keeps the request's title.
  `entry_status` caps the status; a notice changes the status only with extension flag 1 and a connected byte of
  0..2, the character only with flags 1 and 8 together (FUN_1001c9b0 stores the primitive inside the status
  block's branch, 0x1001c9f6 `je 0x1001ca7f`), shown only while the playing bit is set; an equal age is dropped.
  Ours keeps one character per friend, not one per slot.
- The type-31 handler's gates (FUN_100160c0; header +0x18 handle number, +0x19 extension, +0x1a message,
  +0x1b legacy, +0x1c list index), built in `profile::notice`:
  - +0x1b set: the sign-on only when +0x10 == 1 and +0x18 == +0x1c == 0xff (LSB's profile-available notice sets
    exactly these); otherwise the header's status block applies to entry +0x1c with no extension (FUN_1001c970,
    newer only, through the same FUN_10017560). Ours took any +0x10 == 1 as the sign-on, so a friend's
    "connected 1" never reached the status.
  - +0x1a set: a message notice for the viewer (title up to 0x07 and text to callback 1); no entry change.
  - The extension only with +0x19 bit 0, +0x1a and +0x1b clear and a length under 0x158. Its flag byte, then 7
    bytes, then the blocks in order: flag 2 16 bytes, flag 4 8 bytes, flag 8 the 16-byte primitive (the character
    id at its +8: 0x10, or 0x18 after a flag-4 block), flag 0x10 16, flag 0x20 0x68. Flag 2 sends the notice to
    FUN_100200a0 and not to the entry.
  - An index of 200 or more changes nothing (polcore's list is 200 entries). With the list loaded (DAT_10111c30)
    polcore also needs the entry's account and handle number (entry bits 13..18 == +0x18) to match; ours matches
    the account and index (client/friends.rs `notice`).
- Older builds: a client from before this change splits message data on NUL, so it shows the new data's
  `title 07 text` as the title and no text. This build reads both.
- Tests: message_body, title_from_data, notice_status, notice_paths. Not checked live.
- Not built: the legacy path's data block (FUN_1001acf0, a length 1..0xae); flag 2's FUN_100200a0; the accept's
  second data; the handle numbers and the area code in ours' header (zero); the counter
  (ours: the clock's nanoseconds).
