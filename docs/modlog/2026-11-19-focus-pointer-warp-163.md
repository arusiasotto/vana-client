## The pointer put on the cursor at every focus change (2026-11-19)

<!-- dll-build: 30261102_0 -->

Modlog-gaps item 163 ("Window manager: the pointer put on the new cursor child at every focus change, FUN_1015e850 ->
FUN_10124b70, pointer +0x48 = 18.0"). Those are 30261006_0 addresses; in 30261102_0 they are FUN_1015fe20 and
FUN_10126000 (funcmap, both "same"). Decompiled with Ghidra; FUN_10126000, FUN_1015fe20, FUN_1011c080, FUN_10125b90
and the glide in FUN_101267f0 (0x101268ae..0x10126921) checked in Rizin.

Retail:
- FUN_1015fe20(window) is the window manager's focus setter (+0x54 the focused window, +0x58 the one before). On a
  change, the old window gets FUN_1011a690(0) and +0x98 = 0, the new one FUN_1011a690(1), then FUN_10126000 runs on
  the mouse object (DAT_104e2f04). A change to no window calls nothing. It is called by the manager's frame pass
  FUN_10160fd0 with the topmost window that can take the focus (FUN_1015fdb0: not flag 1 without +0x98, not +0x6e,
  not closing +0x70, not hidden state 0xe), so every open, close or raise that moves the focus goes through it.
- FUN_10126000: mouse +0x48 = 18.0; then, when the focused window exists, is not hidden (state 0xe) and not closing
  (+0x70) (FUN_10160380), FUN_1011c080 finds its type-1 part whose id (+0x3a) is the window's cursor (+0x4c) and
  returns that part's centre, x + w / 2 and y + h / 2 on its shorts (+0x2a / +0x2c / +0x2e / +0x30, absolute UI
  pixels, set by FUN_1011af60), and FUN_10125b90(centre, 0.0) puts the pointer there.
- FUN_10125b90: nothing while the mouse is in modes 3..6 (+0x4d: scroll thumb drag, move drag, camera drag,
  autoscroll). Else +4 / +8 (the game's pointer) = the point (+0x48 is left alone for 0.0). The Windows cursor itself
  is moved (SetCursorPos, UI pixels mapped to the window's client area) only with the Windows cursor shown
  (DAT_10457da8 = config 0021), DAT_10457c2c (config 0034) 0 or 3, the input device up (DAT_1045781c) and the window
  active (DAT_103d4d64 +0x1c == 1).
- +0x48 is a glide: each frame of FUN_101267f0 (0x101268ae) with +0x48 > 0 takes FUN_10014cf0's ticks off it; at 0
  or below it is set to 0, else the drawn position +0xc / +0x10 goes half way to +4 / +8 (C division on ints). With
  no glide left, +0xc / +0x10 = +4 / +8. The sprite cursor (FUN_10126340) draws at +0xc / +0x10.
- While +0x48 > 0 the children's hit test FUN_1011a140 returns -1 (no child takes the pointer, no hover state), and
  FUN_1011a240's hover SE 9 is skipped.
- The next WM_MOUSEMOVE (FUN_100016c0) more than 2 pixels from +4 / +8 sets them from the mouse (FUN_10125ad0, which
  also sets +0x48 = 0). With the sprite cursor the Windows cursor never moved, so the game's pointer goes back to
  where the mouse is.
- The focus itself (FUN_10160fd0 -> FUN_1015fdb0 -> FUN_1015fe20): each frame the window list is walked from the top
  and the first window that is not suspended (+0x70), not closing (+0x6e), not in state 0xe and without registry flag
  bit 0 (+0x34 & 1, unless +0x98) takes the focus. Bit 0 is set on 74 of the 373 registry windows: the log windows,
  the gauges, the party and alliance lists, the help line, the title and info windows, the lobby backdrops.

Ours had no pointer warp. Now:
- GameUi takes the focus from its window walk (`walk_focus`: the windows wanted this frame, top first by raise
  stamp, not suspended, registry flags & 1 clear), as FUN_1015fdb0 does. A change of focus owes the pointer warp to
  the new window's cursor child centre (game_ui.rs `Focus`), paid as soon as that window's hand is drawn (an opening
  window draws it once open). The hand drawn is recorded in one place (`UiBatch::set_hand`: the generic window draw,
  the disabled-children draw, invwin's hand, the main menu, the title buttons, the character list, the push_menu
  windows); only the focused window's hand is what Enter presses. With no window that can take the focus up, the
  screens outside the walk (the title, the lobby lists) have it by their hand; with no window up at all (Scroll Lock,
  the download screen) the focus stays.
- The windows that draw their own hand give its cursor part with it (`GameUi::cursor_on` / `cursor_child`): the
  config windows (their layout children, and our rows and buttons on them), the colour list, the party menu, the
  linkshell naming window, the quest and Unity choosers, the key items list, the shop and auction lists and history,
  the celestite, blue magic, automaton, Monstrosity and maze lists, the mannequin grid, the event choice, the
  Monstrosity mode menu and the Mog House door menu. A row list's part is its row (its layout child where the rows
  are children). Left as they were: the auto-translate list and the full log (feppalle, logwindo: registry bit 0, they
  never take the focus) and our own windows outside the window list (Settings pages, the updater, the notes, mod
  windows).
- A window opened again in place under the same name is a new focus (`GameUi::renew`): the event choice renews
  "menu    query" for each op 0x24 / 0xd4 menu.
- The app (client/ptrwarp.rs, mod.rs) applies it unless a drag is on (mouse kinds 3..6 by name, and the scroll
  thumb's drag, which ours keeps on the bar's hold rather than as kind 3): the game's pointer goes
  there, the sprite glides (stepped at 30 a second, 2 ticks each), the windows see no pointer during the glide, and
  a mouse motion more than 2 UI pixels away ends it. The Windows cursor is moved only with config 0021 on, window
  mode 0 or 3 and the window focused; elsewhere only the game's pointer moves, as in retail. Where the system refuses
  the move (Wayland, not a retail case) the game's pointer stays with the arrow too. With the mouse outside the
  window the windows see no pointer, warped or not, and leaving the window ends the warp.

Not done (deviations to flag):
- +0x98 (a flag-1 window asked to take the focus) and state 0xe are not modelled; the pointer warp of an opening
  window waits until its hand is drawn, where retail's comes at the focus change.
- Retail sets +0x48 = 18 even while a drag is on or when the window has no cursor part (hover held off for 18 ticks
  without a move); ours does nothing then.
- FUN_10160fd0's deferred raise also puts the pointer on the cursor (FUN_10125b90(centre, 0), no glide) when the
  raised window already had the focus; ours only on a change.
- The cursor moves with a pointer warp from window code (FUN_1011a240(child, 1), and FUN_10241c00 / FUN_10246840
  calling FUN_10126000 after setting a cursor), and FUN_1015fb00's own FUN_10126000 when a window opens: queue row 177.
- The field's pick and the press / drag positions keep using the mouse's window position, not the warped pointer
  (retail picks at +4 / +8); only the windows and the sprite use the warp. A later stacked-window shift
  (World::ptr_dy, FUN_101626e0) moves the warped pointer with it.
- Not checked live.
