## PlayOnline: registering a character to a handle, and the list reload after a change (2026-11-12)

<!-- dll-build: 30261102_0 -->

Queue row 146, the open points of "PlayOnline sign-in (net/pol)" (2026-11-01): characters not yet linked to a
handle, the handshake's bytes 0x0c..0x17, and the stale address bytes. FFXiMain addresses are build 30261102_0;
polcore's are the polcore.dll installed beside it (file version 1.18.12, the common function table at 0x100c4180;
table slot = FFXiMain's thunk offset / 4). The 2026-11-01 entry's polcore addresses are another build's.

net/pol/polpro.rs (`Tables`), net/pol/mod.rs (`Profile::select`, `register`, `reload_characters`, `unlinked`),
net/lobby.rs (`refresh`, `registers`, `failure_code`), client/netwait.rs (step 3's second path), client/mod.rs.

**A character no handle holds (FUN_100ee2a0 subs 0x10..0x15).** Ours stopped the log-in with "not registered to a
PlayOnline handle yet". Retail registers it on the way in:
- Sub 0xe finds polcore's entry (FUN_100eff30) and reads it (slot 0xb1); +0x10 bit 0x8000 clear sends it to sub
  0x10.
- Sub 0x10 (text 8 0x12): FUN_100efe60 takes the first handle (slot 0xad, FUN_10018ff0: 0x28-byte entries at
  0x1045b520, +0 bit 0 = exists) with a free slot byte among its 8 (+0x20.., bit 0 = taken, bits 1..6 the
  character's index). None: the step fails with code -1. Then polcore's unlink (slot 0xb8, FUN_1001deb0 ->
  FUN_1001dde0; the answer is ignored) and link (slot 0xb7, FUN_1001dee0): the character takes the handle's first
  free slot, its entry gets the handle in bits 16..21 (0x1001e00b), the slot in bits 22..24 (0x1001dfe6) and bit
  0x8000, and its bit in the changed map (0x104533c0, FUN_1001db20). Link answers: -0x1c03 / -0x1c16 an index
  past 0x3f, -0x1c04 no such handle, -0x1c05 no such entry, -0x1c00 linked already, -0x1c01 the handle is full;
  unlink's -0x1c06 when no slot of the handle names the character. A negative answer is the step's code. Then the
  store starts (slot 0xb3, FUN_1001e4e0 -> FUN_1001da90).
- Sub 0x11 (8 0x13) polls it (slot 0xb4, FUN_1001e500 -> FUN_1001db80). **StoreCharacterList is transaction
  1/10**, body 0x248: the 0x244-byte payload and its checksum, the reply a header alone. Payload: bytes 0..0x40
  every entry's order byte (+0x10's low byte, from the list record's byte 1); then 8 bytes an entry: byte 0 is 0
  for an entry that did not change, else 1 linked / 2 not linked, byte 1 the handle, byte 2 the slot, the rest
  zero (0x1001dc65..0x1001dcef). The buffer is the transaction's, not cleared: an unchanged entry's bytes 1 and 2,
  a changed but unused entry's 0..2 and the payload's last 4 bytes are what the last transaction left (ours:
  zeros). FUN_1001da90 first makes the order unique (FUN_1001d9d0: used entries claim their place in index order,
  any entry whose place is taken gets the lowest free one). With no changed entry and no moved place the poll
  ends without a connection (state 1). A good reply clears the changed map (state 6). polcore keeps the link in
  its tables whether or not the store goes through.
- Sub 0x12 (8 0x14) starts the handle list's store (slot 0xb5, FUN_1001a860 -> FUN_100191b0; 0/8, body 0x648),
  but sub 0x13 (8 0x15) polls it through slot 0xb4, **the character list's poll** (0x100ee6a9 calls the same
  thunk as 0x100ee61a; the handle list's own poll is slot 0xb6, FUN_1001a880 -> FUN_10019300). That poll runs
  the character store's states on the handle transaction: nothing changed since the store, so it ends at state
  1. Either poll would end there (a link changes no handle's own fields), so nothing is sent. Ours sends nothing.
- Subs 0x14 / 0x15 are 0xe / 0xf again: the entry is linked now, ChangeMyStatus (handle, index, 0, -2, -1, 1),
  whose body names the slot just taken (+0x11 = 1, +0x12 the slot).

Ours: `polpro::Tables` holds polcore's two tables as far as this needs them (the entries' used bit, product,
three dwords, order, linked bit, handle and slot; the handles' exists bit and slot bytes) with `load_handles`,
`load_characters`, `find`, `free_handle`, `unlink`, `link`, `store_body` and `stored`; `Profile::select` calls
`register` for an unlinked entry (one 1/10 transaction), then ChangeMyStatus. `Lobby::registers` tells the
waiting screen, whose step 3 then runs 14 -> 16 -> 17 -> 18 -> 19 -> 20 -> 21 -> 22 with texts 8 0x10, 0x12,
0x13, 0x14, 0x15, 0x10, 0x11 (`NetWait::login`).

The list reader, re-read for this (FUN_1001d340 states 0, 6, 8): every load first clears each entry's used and
linked bits and each slot's taken bit; a record is [0] index (past 0x3f skipped), [1] order, [4] linked (bit 0
for the entry's flag, any non-zero value for the handle's slot byte), [5] handle, [6] slot, u16 @8 product,
dwords @0xc / @0x10 / @0x14. **The entry's slot bits are set from the handle byte** (`[5] & 7`, 0x1001d641), not
from [6]; the handle's slot byte is right. Kept as retail has it (it only shows in the store's byte 2 of an
entry unlinked without a new link). polcore does not bound [6]; ours skips a slot past 7. `Profile` used to keep
the raw records and take the first match in record order; FFXiMain's lookup is by entry index.

**After a create, delete or rename: step 0x13 is the PlayOnline list reload.** The run's step 0x13 is
FUN_100ee1e0 (not FUN_100ef220, which is step 6): sub 0 (text 8 9) starts polcore's LoadCharacterList (slot
0xaf, FUN_1001e520 -> FUN_1001d2f0), sub 1 polls it (slot 0xb0, FUN_1001e540 -> FUN_1001d340), a negative
answer is the step's code, subs 2 and 3 pass. So a character made in this session gets its PlayOnline entry
before the lobby's list comes again (step 2), unlinked, and its first log-in registers it as above. Ours ran
the four frames and sent nothing, so on a PlayOnline sign-in a new character had no entry and its log-in failed
with -1. Now `Lobby::refresh` (the three change tasks) reloads the list first on a PlayOnline session
(`Profile::reload_characters`, the same 1/3); a failure counts as the refresh's (FFXI-3115 follows). Under
xiloader the loader rewrites polcore's list from the data link's 0x03, as before.

Steps 0x11 (FUN_100eefd0: the handle list's store with its own poll, then the character list's) and 0x12
(FUN_100ef0c0: text 8 0x1b, the handle list's store) have a place in the step switch (FUN_100da750) and in
FUN_100dbac0's counts (4 and 2), but nothing starts them in this build.

**A PlayOnline code attached to a failure was not found.** `Profile::select` attaches polcore's code to the
refusal it came from as a context; `lobby::failure_code` and `link_kept` looked for `Failed` in the error chain,
where a context does not appear as itself, so a refused ChangeMyStatus showed FFXI-3101 instead of its POL code
(the test built the error the other way). Both read the code with `downcast_ref` now.

**The handshake and the address bytes, in this polcore.**
- The connect handshake (FUN_10017c40): byte 0 = 0, byte 1 = 1 when the transaction is not enciphered (never on
  this path) else 0, u16 @4 = 1, the port @6 and address @8 from the 20-byte address global (0x100ffab8), 0x18..
  0x27 zeroed. Bytes 0x0c..0x17 are not written, as the 2026-11-01 entry has it. The request header
  (FUN_10017e90) zeroes its 8..0x17 before the cipher runs, so what the next handshake carries there is the
  keystream's bytes 12..23 from the IV: the same 12 bytes in every handshake after the first on a transaction slot,
  which carries what the buffer held before (zeros in ours). A server cannot require them of the first one.
- The address global is written once, from the chat greeting (FUN_10010570 -> FUN_10014480): {u16 1, u16 port,
  u32 address} at the frame's -0x244 and the next 12 bytes of the frame (-0x23c..-0x231), which the function
  never writes. They are the stack's leftovers, so a server cannot know them; the authCode enciphers all 20
  (FUN_10014be0). Ours sends zeros there.
- Whether a real server checks the handshake token's use or either group of bytes still needs a PlayOnline
  server *(not verified)*.

**Checks.** polcore itself, run under Wine (its table lock, transaction gate, notify and send patched out; the
reader, link, unlink, order pass and the store's body builder called at their states), against `Tables` on
20,000 random lists with leftover order and slot bytes: the entries after the load, 69,877 link / unlink answers
(every code above among them), the slot bytes and the first 0x240 bytes of the body all
equal. One difference found and kept: unlink with a handle index past 0x3f reads the byte after the handle
table before its range test (-0x1c04 where the range's -0x1c16 was meant); FFXiMain never passes one. Unit
tests: the tables, `select` against a profile server in the test (1/10 then 4/5 with the slot; a linked entry
4/5 alone; -1 with no free slot or no entry; a refused store's code, the link kept), the reload then
registration of a new character (1/3, 1/10, 4/5), the waiting screen's calls. 1,014 tests pass. Live on LSB: a
log-in still goes through (lobby 0x07 / 0x0B, zone-in).

**Not done, not checked.**
- None of this was run against PlayOnline: there is no server to run it on, and LSB under the loader never has an
  unlinked entry. A create, delete or rename was not re-run live on LSB (their refresh is unchanged there).
- The server's side of the store: whether it wants the stale bytes any particular way, and what it answers for a
  bad link.
- polcore 1.18.12's ChangeMyStatus sends nothing when no argument changes a value and one has gone through
  before (FUN_10019bc0's flag at the transaction's +0xde, FUN_10019f70 state 1); ours always sends (the logout's
  with no active character, for one). And status 0x72 comes with a 0x20-byte body it keeps (FUN_10019f70 state
  4). New gaps row.
- The handle list's store (0/8, FUN_10019300) is not built: nothing in the game changes a handle.
