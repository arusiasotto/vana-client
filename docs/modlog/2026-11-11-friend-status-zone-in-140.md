## Friend List: our status at a zone-in, the status job (2026-11-11)

<!-- dll-build: 30261102_0 -->

Modlog-gaps item 140 ("Friend List: Away back to Online at login *(inf)*; deleting / unblocking / reordering; polcore's
message format and status mapping"). Addresses are 30261102_0 (MODLOG "The Friend List": LAB_100facf0 -> FUN_100fae40,
FUN_100f7960 -> FUN_100f7aa0, FUN_100e46a0 -> FUN_100e4710, FUN_100f7a90 -> FUN_100f7bd0, FUN_100ee160 ->
FUN_100ee2a0). Decompiled with Ghidra; the 0x00A branch, its jump table and the job's answer checked in Rizin.

- The reset is not a login step: it runs at every zone-in. The s2c 0x00A handler FUN_100fae40 takes the packet only
  in connection state 2 (S+0xc; `cmp byte [ebp + 0xc], 2` at 0x100faeb4, then 3), and the connect of every zone
  (FUN_100fa000) zeroes the whole session object and sets state 1, the login datagram's build (FUN_100fb980) 2. The
  older note "only the first 0x00A" was wrong.
- By LoginState (u32 @0x80, jump table 0x100fb790 on state - 1): 1 MYROOM (0x100faf3c) and everything else but 3..5
  (0x100faf9b: 2 GAME, 0, 6 and up) read our open status (FUN_100f7bc0, status object DAT_104e0abc +0xc) and, when
  it is 1 (Away), call FUN_100f7bd0(0) (Online) and FUN_100e4710(1, 0) (c2s 0x0DC, away flag off). Online and
  Invisible (4) are left alone and nothing is sent. So /away, olstat's Away and an Away set in the PlayOnline viewer
  all end at the next area change.
- 3 POLEXIT, 5 POLEXIT_MYROOM (zone flag 0x200) and 4 JOBEXIT (0x2000) do not reset. They start FUN_100daf30 (called
  each frame through FUN_10016580): state 0 waits for a mode outside 0xb / 0xc / 0xe / 0x15 and the flag without
  its done bit (0x400 / 0x4000), then asks for the fade (DAT_104840ce = 1); 1 waits for it; 2 waits for the PlayOnline
  jobs (FUN_100f1230 == 0) and closes the mail engine (FUN_100f7810(0)); 3 saves the item caches and gives the
  process to the viewer (FUN_10017670: FUN_10010520, DAT_10457b78 = 1, main loop flag off); 4, once DAT_10457b78 is
  0 again, sets flags 0x400, 0x4000 and 1, calls FUN_100f7aa0 and FUN_100e4710(1, status == Away). FUN_100f7aa0
  reads polcore's slots +0x330 and +0x338 (the status) into both blocks of the object, puts -1 in the fifth field
  and sends once: the status the player left the viewer with, and the away flag set or cleared to match. LSB sends
  only LoginState 1 and 2.
- The status object (0x48 bytes, built by FUN_100f78d0): six dwords in force at +0 (handle, character, slot +0x330's
  value, open status, -1, FUN_100f1a90's word), the same six pending at +0x18, the job at +0x30, a dirty byte at
  +0x34; a second job at +0x40 for the handle record's low two bits (+0x38 / +0x3c). FUN_100f7bd0(open) does nothing
  when the status in force is already `open` or the job is busy (job +1); else it writes the pending status, sets
  the dirty byte and queues the job (FUN_100f7b40 -> FUN_100f1480, answer FUN_100f7b00).
- The job sends twice. Its request FUN_100f1a10 passes the six dwords in force to polcore's ChangeMyStatus
  (FUN_103116a7), not the pending ones, so the first request repeats the old status. The answer FUN_100f7b00 with
  the dirty byte set copies pending over in force (`rep movsd` from +0x18, 6 dwords) and clears the dirty byte, but
  not the job's busy byte (job +1), so the runner FUN_100f1230 runs the job again from step 0 and it now sends the
  new status; that answer finds the dirty byte clear and clears the busy byte, which ends the job. FUN_100f7b00
  returns 1 on every path, so the runner never frees the job itself (`FUN_100f1200` is skipped): the busy byte
  decides. A failed request (result < 0) copies nothing and clears nothing, so the job runs again. Inside one run
  FUN_100f12a0 tries a failed request again each frame up to 0x32 times (counter +0x28) for results above -0x800
  other than -0x14cc; after that, or for other results, it reports the error (FUN_100182e0) and hands it to the
  answer, which leaves the job busy: retail never gives up. FUN_100f7aa0's send has the dirty byte clear: one
  request.
- Dead in this build:
  - "menu    oplev" (menu table row 0x103740ec, handler DAT_1066484c with vtable 0x1033ade8): its key handler
    FUN_101ed350 sets the handle record's low two bits to child - 1 (FUN_100f7c70 -> FUN_100f1730, polcore slots
    FUN_103115b5 / FUN_103115c0) and its open puts the cursor on them (FUN_101ed1e0). Nothing opens it (the name
    has no code reference) and no DAT in ROM..ROM9 holds a menu of that name.
  - Config 0x19 (registered with no callbacks, kind 5, 0..1): FUN_101ac550 (set: FUN_100f7b90(v != 0)) and
    FUN_101aa0f0 (load: FUN_100f7b60) would put it in the object's fifth field, but neither has a caller, a
    pointer or a table entry anywhere in the DLL, and no config window shows the id. The field stays -1.
- olstat's table (0x1038308f + child: 0, 1, 4, ended by 5) and its handler FUN_101ed2e0 are as built: FUN_100f7bd0,
  then the away flag set for Away and cleared for the rest.
- Ours (client/friends.rs): `zone_in` at every 0x00A with `net::pol_return` (LoginState 3..5), settled once
  LoadMyStatus is in and the session is signed on (retail has polcore's status before the game starts). A plain
  zone-in: Away -> `set_status(0)` and c2s 0x0DC away off (`zone_reset`). A return: LoadMyStatus again,
  ChangeMyStatus with it once, then the away flag by it; ours has no viewer to hand over to, so the return is at
  once and the fade and the wait are not made.
  `set_status` (`change`) drops a change while the status job runs and sends the old status then the new
  (`change_sends`). Without xi_profile it only keeps the status, so a zone-in still clears an /away there. With
  xi_profile but before the session can send (not signed on, the loads not in, our slot unknown, or within 30 s
  of an IRC drop) it holds the change and `poll` sends it once it can, so the next LoadMyStatus does not undo it.
  The return's read-and-send runs on the status job too (FUN_100f7aa0) and is skipped without a ready session, as
  is any send with no slot (a ChangeMyStatus without one would tell xi_profile the character is not in game).
  A failed ChangeMyStatus is tried again a frame later, as retail tries results above -0x800 0x32 times a frame
  apart and then runs the whole job again, without end (`change_retried`): ours after a connection or I/O failure,
  not after xi_profile refused it (`transient`; a close at the open and a failed TLS handshake count as refusals),
  a game frame (1/30 s) apart. A logout (Friends dropped) stops the tries, so an old change cannot
  land after the next login. Before, the status was not kept
  without a session and nothing ran at a zone-in.
- Tests: zone_in_resets_only_away, a_change_repeats_the_old_status_first, change_decision, settle_gate,
  retries_only_io, dropped_friends_stop_their_jobs, pol_return_states. Not checked live.
- Still open:
  - polcore's own side is in "Friend List: polcore's notice status and message format" (2026-11-11).
  - Deleting, unblocking and reordering: retail has none in game (commenu's help sends the player to the viewer);
    still the user's call.
