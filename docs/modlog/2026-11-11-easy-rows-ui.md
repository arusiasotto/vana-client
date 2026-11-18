## Primer, Help Desk hand, automaton refusal, log refill, auction slots at zone-in (2026-11-11)

<!-- dll-build: 30261102_0 -->

Modlog-gaps queue rows 34, 37, 51, 52 and 56: the points the batch 8 / 10 notes traced that ours still lacked.
Addresses are 30261102_0 (the notes carry 30261006_0).

- **Adventuring Primer (row 51).**
  - guide00's frame hook win_guide00_v28 (0x10235300) only counts while +0x8c < 10; on frame 0 it empties the paged
    list. The row build FUN_10235500 then sets rows 1..count to state 0 and **rows count + 1..8 to state 0x10**
    (FUN_10119ff0), inert but drawn. So the eight row bars always draw, empty during the wait and past the count.
    Ours hid every bar without a row; `primer::draw_cats` now hides none.
  - /primer with the Primer up (menu_guide00_open 0x10235190 -> the window open on an open window): the open hook
    win_guide00_v04 (0x10235260) runs again. It finds the main menu and the social page closed, so +0x64 / +0x65
    become 0 and neither is reopened at the close, and +0x8c = 0 restarts the ten-frame wait. guide00 is raised
    with the focus; guide01 stays open under it *(inferred: both are layer 2)*. Ours: `primer::open` on an open
    Primer (`Primer::over`).
  - guide01's arrows: a click is Enter on child 9 / 10. The generic key layer plays SE 0002 (guide01's open clears
    only the move sound, window +0x85), then win_guide01_onkey (0x10235980) re-sends it as Left / Right with SE
    0001: both sounds in one frame, 0002 alone with Ctrl / Alt held. Ours played 0001 only.
  - A drag's release: the generic left release sends Enter only with no bar drag in progress and on the cursor
    child, which is the generic handler ours already runs. Nothing changed.
- **Help Desk hand (row 52).** The entry marker draw FUN_10217de0 (faqsub and faqmain's pages) keeps its own
  counter at entry +0x2c: the frame drawn is (counter >> 2) % 6 and the counter steps once a drawn frame, wrapping
  at 24. Each of the six anc_s frames holds four retail frames (8 ticks); the generic hand holds 3 ticks. Ours:
  `GameUi::faq_cursor`. The header against row 0 and the keyword box's place were already as traced; the field's
  frame is still unsettled (footage).
- **Automaton customization (row 56).** automato's frame hook win_automato_v28 (0x10209050) sends itself message 8
  on every frame the pointer drives the menus (FUN_10127770) and rests inside bluinven (FUN_1011a0a0).
  win_automato_onkey (0x10209490) case 8: nothing picked -> the focus to bluinven with SE 0013; a pick -> SE 0004
  and the focus stays, so the 0004 sounds again every frame. Ours repeated it only when the pointer moved; it now
  sounds every retail frame (33 ms) while the pointer rests there with a pick. Flow B's two SE 0002 start in one
  frame, as ours' do. pupsibor has no registry flag 0x10000, so it opens on its remembered row, as ours.
  Still open: the cursor box of an unfocused automato. The generic draw FUN_10118c60 highlights the cursor part
  while window +0x63 is set, and nothing in automato clears +0x63, but the animated box's own gate was not found.
- **Log windows (row 37).** The history refill FUN_1012a520 calls FUN_10163b30(logwindo, 1) for each row it
  writes, whichever ring it fills: window 2's open (FUN_1012aa60(8, ..)) refills up to 50 rows and each keeps
  **window 1** open one more period, capped at its max lines. Ours: `LogWin::refill_rows` / `refilled`, run when
  window 2 opens. Game state 0x40 (the front end) closing both logs and registry flag A 0x10 having no reader
  needed nothing.
- **Auction house (row 34).** The map session setup FUN_100fa000 runs for every zone and zero-fills the whole
  character data block (0x103ba dwords), the parcel store with it, so the eight slots start empty in each zone.
  Ours kept them across zones; the ZoneIn handler now clears `ah_slots` (Sales Status asks again with its
  LotChecks). The category menus' focus hook (FUN_101dbce0, vtable +0x24) zeroes the list's remembered row on
  every focus gain; ours opens each list at row 0 and keeps the list only under the price history, which is the
  same thing.
- Row 31 (Linkshell Concierge) needed no change: the hand-off between link5 and lscswin is the window manager's
  deferred raise and focus, whose only effects are the hand, the help line and the pointer put on the new cursor
  child. That last step is the manager's for every focus change (FUN_1015e850 -> FUN_10124b70) and ours does it for
  no window: queue row 163.
