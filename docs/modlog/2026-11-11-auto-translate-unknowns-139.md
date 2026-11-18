## Auto-translate: the open questions; the linkshell message editor (2026-11-11)

<!-- dll-build: 30261102_0 -->

Modlog-gaps item 139 ("Auto-translate: what window FUN_101ddcb0 is and the s2c 0x0CC chain to FUN_101dd780;
FUN_101bceb0 (config 0xce); what FUN_1022aff0 tests and why ids 0x181..0x183 end the key item scan; the French /
Japanese second key"). Addresses are 30261102_0 (the row's + 0x15d0: FUN_101ddcb0 -> FUN_101df280, FUN_101dd780 ->
FUN_101ded50, FUN_101ba830 -> FUN_101bbe00). Decompiled with Ghidra, the second key loader and the menu hit test
checked in Rizin.

- FUN_101ddcb0 is the draw of "menu    comment" (ours seacom.rs), the holder of seven blocks of three 41-byte lines
  (MODLOG "Set Bazaar"). A line that is not being edited is expanded with the auto-translate brackets
  (FUN_101b8850(.., 1, 0)), then FUN_10191710, then fitted (FUN_101cb820). Ours wrote the phrases without brackets;
  now `fep::braced`.
- FUN_101dd780 is not on the s2c 0x0CC path: it prints a search comment (MODLOG "Search comments on Enter"; its mode
  word {0xcc, 3} is a chat mode, not the packet). The linkshell message of s2c 0x0CC is printed by LAB_10080390
  (MODLOG "Linkshell message").
- FUN_101bceb0 is the Misc. 4 chat filter (MODLOG "Misc. 4: Chat filter setting"), built in spamfilter.rs.
- FUN_1022aff0 (FUN_1022c600) is "key item owned" (item 138). Ids 0x181..0x183 are the maps of the San d'Oria,
  Bastok and Windurst areas, the first three entries of the table's Magical Maps section (file index 0xb0c, straight
  after the Mog Garden header). Every character owns one of them, so the scan (FUN_101bca00 / FUN_101bca80) ends
  there: the Key Items group holds the owned entries of the seven sections before the maps (Temporary, Permanent,
  Abyssea, Voidwatch, Geas Fete, Mounts, Mog Garden) and never a map, a claim slip or an active effect. Ours already
  did this (item 138); nothing changed.
- The second key (FUN_101bbe00, group loader FUN_101bc090 by the group's language byte): Japanese (1) and French (4)
  entries outside the item kinds 7..0x12 carry a second string after the text. When it holds more than its NUL it is
  the word's key (FUN_101bddc0: text, key), the string completion matches and sorts by: the kana reading in Japanese
  (初めまして。 -> ハジメマシテ。; 1,262 of 2,685 entries), the text without accents in French (Félicitations ! ->
  Felicitations !, Pardon. -> Pardon; 550 entries). French adds a second word per such entry keyed by the text itself
  (param 4), so the word count is FUN_101bbd10's; and a second title word keyed by the title inside its brackets
  (text + 2, length - 4) when FUN_101c9e70 (the accent-folding compare, tables DAT_1037e358 / DAT_1037e3a0) finds it
  differs from the completion. English and German (FUN_101bbfa0) have no second string: key = text. The group's
  sorted array is then ordered by the word's compare (vtable slot 0).
- Ours: `Dictionary::parse_lang(data, language byte)` reads any of the four files with these keys (test
  `second_keys`). The client itself is English only, so the French second words, the per-language compares and the
  Japanese / French candidate lists are not built.

The linkshell message editor (found on the way, then corrected: the submenus carry registry flag 0x200000, so their
open puts the caption in state 0x10, it never takes the cursor, case 4 never runs and nothing opens the editor's
mode 3. The caption bullets below are wrong and ours does not do them):
- The comment window's mode 3 edits the linkshell message (blocks 3 / 6). menu_comment_fn (FUN_101e7530) opens it
  (+0x16 = 3, +0x17 = 0x73) from case 4 of the holder's and the pearlsack's submenus (link2 / link3,
  menu_link2_fn / menu_link3_fn). MODLOG "Linkshell menu" called that case dead code because child 4 is the caption.
  It is not: every child of a layout is the same kind of part (FUN_1011ad60, type 1), and the mouse hit test
  FUN_1011a140 takes any type-1 part whose state is not 0x10, in its box moved by the layout's offset (head 0xe /
  0x10: the caption's (0x13, -3)). The hover handler FUN_1015f360 wants the mouse inside the window frame
  (FUN_1011a0a0), so the lower six rows of the caption take the cursor (FUN_1011a240, message 9) and a click there
  is Enter on child 4 (FUN_1015f420, message 5). In link1 / link4 / link13 that only closes the submenu.
- With the cursor on a caption an arrow key does nothing: FUN_1011c6b0 reads the link as a signed byte (movsx at
  0x1011c6f0), so 0xff is -1, and FUN_101196f0 skips the move (`test di, di; jl` at 0x101197a3). The cursor stays
  on the caption and Enter still opens the editor. (Corrected after the post-merge review; the first version moved
  ours to 0xff.)
- While the editor is open link5 stays up under it but takes no mouse (the editor has no children, only the right
  click); ours gates linkshell::pointer on the editor being closed, as the search window's pointer already was.
- Mode 3 (win_comment_v04 / v08): flag 0x1000, line 0 edited, help 0xe 0x32, no title, the lines at x0 + 4 as in
  mode 0. On close, when the lines differ from the last-sent block: all blank sends "" and clears the sent block's
  first line; else the lines that have a first byte are joined by a line feed (FUN_101dec20, DAT_10351e4c = 0A 00)
  and the sent block takes them. Then, with linkshell 1 worn (FUN_100e9870(.., 1)), c2s 0x0E2 with flag 0x40
  (FUN_100eae20), the packet /lsmes set sends. Nothing fills the lines from the server; only the holder's
  constructor clears them.
- Ours: `Store` for block 3 / 6 (`World.ls_edit_msg`), `linkshell::set_message`; a link of 0xff leaves the
  cursor where it is (`linkshell::link_to`); link5 has no wheel, scroll bar or cursor focus while the editor is
  open (`linkshell::has_focus`). Nothing opens mode 3 yet.
- Not built: FUN_10191710 on the drawn lines; the caption taking the mouse cursor in the other windows of the game
  (the hit test is generic; our other pointers skip parts whose links are 0xff); the modern UI has no way to the
  linkshell message editor.
- Tests: `client::seacom::tests::ls_message_text`, `dat::autotrans::tests::second_keys`,
  `client::linkshell::tests::caption_links_stay`, `client::linkshell::tests::editor_takes_focus`. Not checked live.
