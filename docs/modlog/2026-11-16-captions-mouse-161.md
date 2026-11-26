## Menu captions do not take the mouse; the shared hit test (2026-11-16)

<!-- dll-build: 30261102_0 -->

Modlog-gaps item 161 ("Menu captions take the mouse cursor", found by item 139; also FUN_10191710 on the comment
editor's drawn lines). The item's claim is wrong.
Addresses are 30261102_0. Decompiled with Ghidra; the hit test, the window open, the frame part and FUN_10191710's
language gate checked in Rizin.

- A caption is a part like the rows (FUN_1011ad60, type 1), and the hit test FUN_1011a140 takes any type-1 part
  whose state (+0x10) is not 0x10 (`cmp dword [eax + 0x10], 0x10` at 0x1011a1e4). That much of item 139 holds. But
  the open of a window (FUN_1015f920) tests the registry flags after the parts are built (`test eax, 0x200000` at
  0x1015fa80) and with the flag calls FUN_1011a580, which sets the state of the child whose number is the child
  count (+0x58), the last one, to 0x10 (FUN_10119ff0(0x10, n) -> FUN_1011ae00: +0x10 and the base state +0x18).
  Nothing clears it. FUN_1011a580 has no other caller and windows are built nowhere else.
- In the menu files the flag and the caption go together: 74 registry rows have the flag, 70 of them layouts in the
  files we load; in each the last child has no cursor link (links 0xff), so no flagged window ends in a row (test
  `flagged_windows_end_in_a_caption`). The linkshell submenus are flagged (link1 .. link4, link7 .. link10, link13:
  0x210000), as are the party, search, auction, status, magic / ability, config, macro and friend list menus.
- Windows with a caption and no flag set the state themselves when they open: menuwind and socialme child 15
  (0x1014161f, 0x1014fcfa), bazaar 3 (0x101de55b), mp_cstm 13 (0x10144cf3), post1 9 (0x1014de2f), passinpu 1
  (0x10207bda), ptc9dele 3 (0x10165ca5), keypadus 1..5 and 0x54 (0x101b05b5..). No caption in the game is left in
  another state: the scan of every FUN_10119ff0 call and of the registry against every layout finds none.
- So no caption takes the cursor, by mouse or by a link (FUN_101196f0 refuses a move onto a part in state 0x10 too),
  and case 4 of link2 / link3's handlers (menu_link2_fn / menu_link3_fn -> menu_comment_fn, the comment editor in
  mode 3 on the linkshell message) never runs: MODLOG "Linkshell menu" was right to call it dead code. menu_comment_fn
  has no other caller.
- The hover is not FUN_1015f360. That one runs while the left button is held (FUN_10124f00(0x3e, 0x8b, 4)): inside
  the window frame (FUN_1011a0a0, window +0x3a .. +0x40 = the frame part's place and place + size, both ends in) it
  moves the cursor to the child under the mouse, and on the same child counts +0xb0 up to message 0x1d past 0x1e
  (the held repeat). The hover is the tail of the mouse routine FUN_101267f0 (0x10127220: mode +0x4d = 2, pointer
  shown +0x4e, an active window): every frame FUN_1011a140 on the active window with no frame test, the hit child
  kept at mouse +0x52, and the cursor moved (FUN_1011a240, then message 9) only when the hit is a child and not the
  one of the frame before (`jle` / `cmp ax, di; je` at 0x1012722c). The release FUN_1015f420 (0x8b, 5) is message 5
  when the hit child is the cursor's, with no frame test either.
- The hit box of a child is its place moved by its own header offset (+0xe, +0x10 of the child's 32 bytes, part
  +0xc), both ends in (`jg` / `jl` around each bound); the first child in file order wins. The header offset is
  where the sprite is drawn from the place: (19, -3) for a caption, (-2, 2) and (0, 2) for the page arrows of
  quest01 / miss00 / guide01.
- Children no cursor link leads to that are live (no flag, no state call), all buttons for the mouse: itemctrl /
  moneyctr 2..5, the page arrows quest01 / miss00 / guide01 9, 10, jbpcat 11, 12, conf11s 15, 16, mcrselec / mcres20
  21, 22 (linked up and down to row 1, flagged windows whose last child 23 is the caption), menuwind 13, 14, the
  creator's chmk* arrows, and chatctrl 8, the arrow beside the tell name: menu_chatctrl_fn (0x1012e6b0) sends message
  5 on child 8 to the code of Right on the Tell row (FUN_1012e610(1, 1), the next name), and the window stays open.
- FUN_10191710(text, length, room) is for the German client only (`cmp eax, 2` on the language at 0x1019172e, and
  not when byte +0x18 of the same block is negative): each ASCII `"` becomes 0x85 0x44 or 0x85 0x53 in turn (the
  opening and closing German quotes), when twice the length fits the room. English, French and Japanese text is
  returned as it is, so there is nothing to draw differently here.

Ours:
- `Menu::hit` (dat/ui.rs) is the hit test: boxes at place + header offset, both ends in, file order, the children in
  state 0x10 passed over. `GameUi::caption` gives the flagged caption and `GameUi::hit` leaves it out. The generic
  mouse of winhits.rs (65 call sites) uses the same boxes and skips the same caption (`winhits::parts`), whatever range
  of children the window asks for: linklist's member windows asked for 1..=4, which took link7 / link8's caption at
  its place (0, 0) and sent the sack / pearl change from it (link9 / link10's too).
- The linkshell pointer took only children with a cursor link up (link 0xff passed over) at their place without the
  header offset; it, and the party, search, status, quest and mission pointers, use `GameUi::hit` now. `select` has
  no case for the submenus' caption, and nothing opens the editor's mode 3 (its store and close stay as the window
  class has them).
- chatctrl: child 8 takes the cursor, Enter there is the next tell name, and the arrows leave the cursor on it (its
  links are 0xff).
- mcrselec: the page arrows 21 / 22 take the cursor like mcres20's; Enter there turns the page (message 5's cases
  0x15 / 0x16, FUN_101a7fc0 / FUN_101a7fa0, where Left / Right go).
- Not built: the hover's rule that the cursor moves only when the hit child changes (ours moves it on any mouse
  move over another child than the cursor's); the frame test and the held repeat of FUN_1015f360 outside itemctrl /
  moneyctr; the mouse on the page arrows of jbpcat (win_jbpcat_onkey 0x1014bf50: message 9 on 11 / 12 turns the
  list off, +0x61 / +0x62) and conf11s (0x1019ba40: message 5 on 0xf / 0x10 is Left / Right); the mouse on windows
  ours gives none: iuse, sortyn, bluesibo and the map menus.
- Tests: `dat::ui::tests::hit_boxes`, `client::winhits::tests::hit_test_skips_the_caption`,
  `client::game_ui::tests::flagged_windows_end_in_a_caption` (needs the game files). Not checked live.
