## Lobby netwait: the backdrops, the rename as its own run, the time-out and FFXI-3115 (2026-11-12)

<!-- dll-build: 30261102_0 -->

Queue row 144, the four things "Lobby: netwait and netbar" (2026-10-26) left undone. None was built. All addresses
are build 30261102_0 (the older entry's are 30261006_0; FUN_1023b550 is now FUN_1023cb60).

client/netwait.rs, net/lobby.rs, client/mod.rs, client/game_ui.rs (`backdrop_window`).

**The run (FUN_1023cb60(connect, 1, 0, op, slot)) and how it ends.** Every step goes through FUN_1023d170, which
pumps a frame, starts the step (FUN_100db170), then calls the step function once a frame until it is done. Three
ends:
- Step 1 or the op's own step fails (LAB_1023d116): both windows close, the popup of `thunk_FUN_100efa60()`
  (FUN_1023fab0), return -1.
- The refresh after a change fails, steps 0x13 / 2 of ops 2, 3, 5 and 6 (LAB_1023d0a6): both windows close, that
  popup, then the popup of code 0x73, FFXI-3115 "Connection to the FINAL FANTASY XI server lost. / Returning to the
  PlayOnline FINAL FANTASY XI top page.", return -2.
- Done: p = 1 for 10 frames, both close, 0.

The code (FUN_100efa60): no link object 0x65; the link's error (FUN_100efa30); else the object's +0x136ac; else
**0x71**, FFXI-3113 "Protocol time out error.".

**The time-out (FUN_100edfe0 / FUN_100edff0).** One counter, DAT_104cb7f8. FUN_100edfe0 zeroes it; FUN_100edff0
adds 1 and answers `0xe0f < counter`, so the 3600th counted call fails. Each step function zeroes it on its first
call (sub-step 0) and tests it on later ones:
- Step 1 (FUN_100ed920): only in its waits (cases 2, 6, 8, 10, 0xe, 0x10, 0x12, 0x14), after the poll, and only
  with the sub-step at 0xe or more: the waits for 0x05, 0x20 and 0x23.
- Step 3 (FUN_100ee2a0): while 0 < sub < 10 (not in the PlayOnline handle steps).
- Steps 2, 4, 0x14, 0x16, 5, 0x17 (FUN_100ee0f0, 100ee7d0, 100eea40, 100eecb0, 100ef160, 100eef20) and 0x13
  (FUN_100ef220): every call after the first.
A step that times out returns -1 with no link error set and +0x136ac zeroed at its start, so the code is 0x71. The
link is not touched: FUN_101164f0 still calls it alive (state not 0 and not 6), so the next op's step 1 jumps from
sub 5 to 21 and the next request goes out on the same link, the old one still unanswered.

Ours: each table frame knows whether it is its step's first call and whether it counts (`netwait::counted`); a
reply wait repeats its frame, so the count runs while it waits. Past 3599 the run ends with `End::TimedOut`. The
worker is told through `lobby::Watch::give_up`: the lobby link's reads now wake every 100 ms (they had no time-out
at all), stop with `Abandoned`, and keep the bytes read so far; the worker hands the link back
(`Task::LobbyBack`), request still open, so the lobby goes on as retail's does. At 30 calls a second that is two
minutes per step.

The link keeps what each request written still has to come (`lobby::Owed`): a view reply, or on LSB for 0x1F and
0x07 a data message first (0x01 / 0x02), then after the loader's 0xA1 / 0xA2 the view reply (0xA1 also the data
0x03). A view reply goes to the oldest request owing one, a data message to the oldest waiting for its type; one
that goes to an earlier request than the current one (its wait given up) is read whole and dropped, its key
counter step kept (LSB stepped its counter when it sent it), and the netbar does not count it.

LSB's paths that skip or replace a step's messages (src/login, read 2026-11-13):
- A refused 0xA1 (maintenance and no character to list): view 0x04, no data 0x03.
- 0x1F with no data session: view 0x04 in place of the data 0x01.
- A refused 0xA2 (zone full, character already logged in, maintenance or login limit, no zone row, no map
  address, the session insert failed): view 0x04 in place of the 0x0B, one for one.
- Refusals of view-only requests (0x26 version, 0x14 deletion off, 0x22 name or pass, 0x28 name): one 0x04 for one
  reply.
- Closed sockets (0xA1 or 0xA2 with no account, 0x07 / 0x14 / 0x21 / 0x28 account or name checks, database
  failures): the link is broken, nothing to account.
- No answer at all: 0xA1 whose account id is not the session's, 0x07 with no data session.
A refusal settles what it replaces: a 0x04 ends the data message its request still waited for. While a data
message is awaited, the view link is watched too (a 1 ms look each round, the view link first, since LSB sent a
late refusal there before it took the later requests): a 0x04 for the current request is its result at once, as
for a refused 0xA1 (before this, ours waited for a 0x03 that never came until the time-out). Not covered: the two
no-answer paths leave their request owed for good, so the next replies of the same kind go to it (nothing can tell
an answer that never comes from a late one).

The
time-out and the worker's result race for one state (`Watch::give_up` / `Watch::finish`): a result in before the
3600th call goes on as usual, and a worker that finds the run given up hands the link back instead of its result.
The time-out frees the UI at once (the popup's OK, the login form), since a worker can be held up outside a read
(a PlayOnline transaction, a connect); the late `LobbyBack` then leaves `busy` alone.

**After a failed run, by caller.** Read from each caller; ours now follows them for a time-out, a refusal, and a
failed refresh:
- Entry, op 0 (FUN_1023fc20): any failure returns -2, the lobby is left. Ours: the login screen with the error.
- Log-in, op 1 (FUN_10241200, from FUN_10246c80): -2 or code 0x14b leaves; -1 goes back to the title menu (from
  the creator with the title music started again, FUN_10246b80).
- Delete, op 2 (FUN_1023c840): -2 or 0x14b leaves; -1 stays on the delete screen. Ours also keeps the screen for a
  refused delete now (it left the lobby before).
- Rename, op 5 (FUN_10244c00): the old name goes back; -2 or 0x14b leaves; 0x139 / 0x142 remember the name and the
  code, and typing that name again shows the code without a request (local_100 / local_228); else the select screen.
- Name check, op 4, and create, op 3 (FUN_1023ad30): -2 or 0x14b leaves the lobby (ours went to the title menu for
  0x14b); else the world step again (op 4) or the race step with the names cleared (op 3).

**Op 5 is its own run.** FUN_10244c00 stores the new name in the slot, runs op 5 (steps 1, 0x16, 0x13, 2: the
rename, then the list again) over the select screen with no fade, and returns 1. FUN_10246c80 then calls
FUN_10241200: the select screen fades out and op 1 runs. Ours did the rename and the log-in in one Task behind one
bar, after the fade, never asked for the list, and left the lobby on a refused name. Now `Task::Renamed` (0x28,
then 0x1F) ends the first run over the select screen, and the log-in is the second.

**The backdrops.** "menu    ptcbgwin" and "menu    hnbackwi" are the same window: no handler of their own, one
element 640 x 240 at (0, 0), sprite lobbywin 85, registry flags 0x11002f (8 no open animation, 0x20 no frame,
0x100000 scaled by W / 640 and H / 480). Sprite 85 is three cells: two 640 x 240 halves of "menu    newtex" drawn
additively (source alpha 145 and 97 of 128, the lower one at half colour), and the small logo from titlwin at (32,
32)..(236, 144). So it is a wash over whatever is behind, not an opaque panel.
- Entry (FUN_1023fc20): ptcbgwin and lobyhelp (no text) open, 'sfin' and 8 + 8 + 8 frames (FUN_1023fbe0,
  FUN_1023fb60 twice), the run, then 'sfot' and 34 frames (FUN_1023fc00) and both close. Nothing is behind it: the
  title's scene loads after the entry returns.
- Log-in (FUN_10241200): before it FUN_10246c80 sets the clock to 12:30 (FUN_10247130(0xc, 0x1e)) and starts the
  title's scene again (FUN_10246a90: resource 0x17, 'main'), so the wash lies over the title flyover. hnbackwi opens,
  lobyhelp closes, 'sfin' + 'ffin' and 8 frames (FUN_1023fb20), the run, 10 frames; then the hn* windows close,
  'sfot' + 'ffot' and 34 frames (FUN_1023fb80), hnbackwi closes, 2 frames.
- The delete and the rename keep their screen under the run.

Ours: `GameUi::backdrop_window` draws the sprite scaled. The entry draws it over black, which hides our login form
and title for the run (retail has neither there); the run starts 24 frames in (at once in the modern UI, which
has no backdrop or fade there), and a good entry fades out before the title menu comes up. The log-in is a screen
of its own, `LobbyScreen::Run`: the title's scene, the backdrop, the run after 8 frames (every log-in, scripted
ones too), and the error popup if it fails. A character the held list lacks fails before anything is sent
(`lobby::Unsent`): FFXI-3101 over the backdrop and the title menu, the link kept.

**Test hook.** `FFXI_LOBBY_MUTE=CMD[:N]` (hex, e.g. `07` or `1f:2`) holds back that view request, every time or
only the Nth on the link, so its reply never comes.

**Checked.** 1004 tests pass (new: the 3600-call count, the refresh's own count, the counted sub-steps, the lead
frames, a given-up read that keeps the link and drops the late reply ahead of the next one, the same on LSB's data
link, the race between the time-out and the result, a log-in of an unlisted character that keeps the link, LSB's
refusals of 0xA1, of 0x1F with no data session and of 0xA2, each at once and after a time-out). Live
on the test server, before the late-reply and race changes, classic UI: the
entry backdrop; a log-in through the select screen into the world; `FFXI_LOBBY_MUTE=07`: FFXI-3113 after 120 s
over the backdrop, OK, the title menu, and the select screen works again on the same link; `FFXI_LOBBY_MUTE=1f:2`
on a delete: FFXI-3113, then FFXI-3115, then out of the lobby.

**Not done, not checked.**
- A broken link (a closed socket, a bad reply: retail's 0x65 / 0x67 / 0x68) still sends ours to the login screen
  with its own text. Retail shows the code and stays in the lobby, and step 1 of the next op connects again. New
  gaps row.
- The modern layer keeps its login form at the entry (no backdrop there); the log-in's backdrop is drawn under it.
- What 'ffin' shows at the log-in depends on the title's scene having loaded; ours has it loaded already.
- The rename was not run live (no character with the rename flag on the test server). The create and name-check
  paths were not run live after the change.
- The 30 calls a second is still the earlier entry's reading of the lobby's frame rate.
