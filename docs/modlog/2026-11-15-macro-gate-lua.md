## The macro gate for mods: game.info().macros (2026-11-15)

<!-- dll-build: 30261102_0 -->

Symptom: a mod that runs macros from the pad (Hotbars' crossbars) can't tell when retail would refuse a macro. With RT
held at a `<stpc>` target prompt, A runs the slot again instead of confirming the target.

- FUN_101a33e0 (30261102_0 FUN_101a49b0, asm 0x101a49b0..0x101a4ac5) closes the macro keys and the palettes when any
  of these holds: not in the field (scene state != 0x60); FUN_1015dce0 (cinema mode, rem4line +0x48, or the UI
  hidden); the target prompt (+0x59); the party cursor (+0xc4); the myroom object's mode (DAT_106631d4 +0x1c) != 0;
  FUN_10087070(0) (an event, frozen, charmed, fishing / digging); own +0x170 2 / 3. Then a focused window
  (FUN_1015edb0, or DAT_1057876c +0x68) closes it unless it is playermo, a palette or mp_pmode.
- Ours tested `event::active` in place of FUN_10087070(0), and not the myroom mode. It now uses `textcmd::busy` and
  `layout` / `garden` (myroom modes 1 and 4 / 2 and 3). +0x68 is still unidentified.
- `game.info().macros` returns the gate without ours' "macro book loaded" test, which retail doesn't have.
