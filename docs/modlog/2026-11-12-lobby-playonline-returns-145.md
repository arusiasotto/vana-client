## Lobby: what the PlayOnline calls return, error 0x68, and the PlayOnline-coded popup (2026-11-12)

<!-- dll-build: 30261102_0 -->

Queue row 145, the three "Unclear" points "Lobby: netwait and netbar" (2026-10-26) left. None was built. FFXiMain
addresses are build 30261102_0 (FUN_1023be30 of the older entry is FUN_1023d440); polcore's are the US viewer's
polcore.dll (the common function table at 0x100c4180, FFXiMain's DAT_10457bdc).

net/lobby.rs, net/pol/mod.rs, net/pol/polpro.rs, client/mod.rs, client/game_ui.rs (`lobby_error_text`),
client/netwait.rs (comment only).

**Step 3 from sub 0xe (FUN_100ee2a0): the calls are polcore's character list and ChangeMyStatus.**
- polcore keeps 0x40 character entries of 0x68 bytes (0x104533e0; table slot 0xb1, FUN_1001d8b0, copies one out):
  +0 bit 0 in use, +2 a u16 product (1 = FINAL FANTASY XI), +4 the world key, +8 / +0xc the content id, +0x10 a
  u32 whose low byte is the entry's index, **bit 0x8000 "linked to a handle"** and bits 16..21 the handle. The
  viewer fills it from LoadCharacterList (1/3, FUN_1001d340).
- FUN_100efee0(slot) -> FUN_100eff30 looks for the entry in use with product 1, the slot's content id, +0xc zero
  and key = u16 +0x13828 | u16 +0x1382a << 16 | u8 +0x1382f << 24 of the lobby's record (the 0x20 record's +4, +6
  and +0xb). None: the state's +0x136ac = -1 and the step fails.
- Sub 0xe (text 8 0x10), flag 0x8000 set: slot 0xc3 = ChangeMyStatus (FUN_10019b90 -> FUN_10019bc0) with (the
  handle, the entry's index, 0, -2, -1, 1); the ticket goes to +0x136a8, a negative one to +0x136ac and the step
  fails. Sub 0xf (text 8 0x11) polls slot 0xc4 (FUN_1001a2f0 -> FUN_10019f70) once a frame: 0 wait, negative to
  +0x136ac and fail, positive the step is done (sub 0x16). So the path is 14 -> 15 -> 22, as ours took it *(inf)*
  before; it is now read.
- Flag 0x8000 clear: sub 0x10 (8 0x12) picks the first handle with a free slot (FUN_100efe60: slot 0xad entries
  with bit 0 and one of 8 slot bytes free), unlinks and links (slots 0xb8 / 0xb7, FUN_1001deb0 / FUN_1001dee0) and
  starts the list's store (0xb3); 0x11 (8 0x13) polls it (0xb4); 0x12 (8 0x14) starts a second store (0xb5); 0x13
  (8 0x15) polls; 0x14 / 0x15 are 0xe / 0xf again, and an entry still not linked there fails with no code (the
  popup then shows 0x71). Not built: ours refuses a character that is not linked yet (queue row 146).
- The poll's own failures (FUN_10017480): -0x203 when polcore is not signed in (DAT_100ffab0), -0x104 once the
  transaction is 100 s old. The 3600-call count of row 144 does not run here (step 3 counts only below sub 10).
  A refused transaction gives -0x1450 - status through FUN_10017cb0's mapping (ours: `polpro::error_code`).

**Under xiloader.** The loader stands in for the viewer, so the returns are what it wrote into polcore:
- It calls FUN_100143f0 (its "INET mutex" pattern), which sets the signed-in flag DAT_100ffab0.
- It finds the list through slot 0xd3 and writes one entry per character of LSB's data message 0x03 (count @1,
  16-byte entries from 0x10: the content id, then u16 character id, u8 world, u8 the id's high byte): +0 = 1, +2 =
  1, +4 the key, +8 the content id, +0x10 = the index, +0x11 = 0x80. So **every entry is linked to handle 0**
  and FFXiMain's lookup is against the data link's list: a character the 0x20 lists and the 0x03 does not (or under
  another key) fails the log-in with -1.
- ChangeMyStatus then really runs. The stock loader resolves pp000.pol.com to 127.0.0.1 and answers on port 51220
  itself: a 24-byte connect reply, a 24-byte header (length 0x20, the address 127.0.0.1) and the request echoed
  with its first 32 bytes zeroed, which polcore takes as a good reply with a zero session value. Steven's fork
  relays the transaction to xi_profile instead. Either way sub 0xf ends positive after a few frames.

Ours: `Lobby` keeps the 0x03's entries (`pol_entries`) and `select` fails with `Failed(-1)` when the picked
character is not among them, after the 0x0B as retail (the lobby has closed the link by then). On the PlayOnline
path `Profile::select` already made the linked entry the active character with the same arguments; its failures now
carry the codes: -1 for no entry, polcore's code for a refused ChangeMyStatus or a bad checksum
(`polpro::local_code`). A socket failure there has no polcore code in ours and still shows as 0x65 (polcore's
socket codes were not read).

**Error 0x68 (FUN_10115ea0 case 5).** The wait for the 0x0B first takes the reply (FUN_10116f30: the map and search
addresses, the key counter), then tests data +0x144, which is the count of the last 0x20 (its u32 @0x1c): zero
fails the wait with the link's code 0x68, FFXI-3104. The link's state is only zeroed, so the link stays up. It is
not in the popup table: the text is "Error code: FFXI-3104" alone. Ours: `select` with no list held sends the 0x07
from an empty record, reads the 0x0B and fails with `Failed(0x68)`. The select screen cannot reach this (no list,
nothing to pick).

**The popup, FUN_1023d440(code, wait) (was FUN_1023be30).**
- A code that is not 0x6c and not negative: FUN_100182e0(3000 + code), the FFXI popup ours had.
- 0x6c or a negative code, with the start switch -POLCON off (the state's +0xa4, FUN_10102490; set only with
  `-net` above 2 and the switch) and the PlayOnline job runner there (DAT_104e0ab8, the normal case):
  FUN_100182e0(code) unchanged. FUN_10018310 then shows 0x6c as the FFXI code 108 ("Error code: FFXI-0108", not in
  the table), and a negative code through FUN_10018180: a PlayOnline job (table 0x103632c8) fetches polerr.bin's
  message for it, and FUN_100181d0 shows group 7 id 0, "Error code: POL-%04d", with the code's magnitude, a line
  break and that message; with no message the first line alone. FUN_1023d440 waits for the job (FUN_10018270).
- Otherwise (the switch on, or no job runner): the same first line, a line break and group 7 id 0x3e ("Unable to
  acquire error messages. / Switching to direct numerical display mode.").

Ours: `GameUi::lobby_error_text`: 0x6c as FFXI code 108, a negative code as "Error code: POL-nnnn" with no second
line (no polerr.bin on a client without the viewer), the rest as before. `failure_code` is signed now.

**A failed log-in shows the popup.** Ours sent every failed log-in (a refusal such as FFXI-3201, a broken reply)
to the login screen with its own text. Retail (FUN_1023cb60 LAB_1023d116, FUN_10241200's -1): the windows close,
the popup, then the title menu; FFXI-3331 leaves the lobby. Now: `Task::SelectFailed` hands the link back when it
is still up (a refusal, the 0x68; `link_kept`), the popup shows over the log-in's backdrop and OK goes to the
title menu. With the link gone (a broken reply, or PlayOnline's part, which runs after the lobby closed it) the
popup shows the same, and the lobby is left on OK: retail connects again in the next run's step 1, which ours does
not have yet (the gaps row of 2026-11-12, "a broken link").

**Checked.** 1009 tests pass. New: the loader list's entries, a character the list lacks (-1, link not kept), the
0x68 with the link kept, the codes of each failure, polcore's code of a refused transaction. Live on the test
server, classic UI: a log-in into Bastok Markets (LSB's 0x03 holds the character under the same content id and
key as its 0x20); a second log-in of the same character while the first is in the world: the run's windows close,
"Error code: FFXI-3201 / Same character is already logged in. ..." over the backdrop, OK, the title menu, and
Select Character works again on the same link.

**Not done, not checked.**
- The PlayOnline-coded popup ("Error code: POL-0001") and the 0x68 were not seen live: LSB gives no way to make
  them.
- polerr.bin's message on the popup's second line.
- ChangeMyStatus's place against LSB with xi_profile: retail asks it in step 3, before the map connection, and a
  failure there fails the log-in; ours sends it at the first zone-in (client/friends.rs) and logs a failure. New
  gaps row.
- Linking a character to a handle (subs 0x10..0x15): queue row 146.
- polcore's codes for a socket failure inside a transaction.
