## Mog House layout: the held piece's turn keys (2026-11-15)

<!-- dll-build: 30261102_0 -->

Queue row 154, opened by the re-baseline to 30261102_0. It corrects three things in "Mog House layout mode"'s
"Held keys" note, two of which were already so in 30261006_0. All addresses are build 30261102_0 (the old ones in
brackets).

**The function.** FUN_101cf930 (FUN_101ce360) is the held piece's key handler in context 0x42, read from Ghidra's
C and checked in the disassembly (0x101cfae9..0x101cfc67).

- Gate FUN_10160380, Enter 0x8f, Escape 0x90: as before.
- Arrows 0x34, 0x33, 0x31, 0x32 (mode 0): each one that is down runs FUN_101ce670 once. Only the last call's
  result counts: when it moved, FUN_101d6c70(0) (SE 8058) and return. When it did not move, the function goes on to
  the turn keys in the same frame. Ours returned on any arrow.
- Turn keys 0x8d (rot - 1, 3 after 0) and 0x8e (rot + 1, 0 after 3), mode 1, both read every frame, one after the
  other. **New in 30261102_0:** each step is skipped while FUN_101d01b0 (flag bit 0 of the 'furn' entry: a wall
  piece). In 30261006_0 a wall piece's +0x20 changed and nothing else happened; now nothing changes at all.
- When +0x20 changed (0x101cfb4e compares with the value saved before the keys):
  1. w0 = FUN_101d00c0() / 2 and d0 = FUN_101d0110() / 2 (0x101cfb5b, 0x101cfb69). Both read +0x20, which is
     already the new turn.
  2. FUN_101cf520(rot), then FUN_101cf360 puts the model at its place.
  3. w1 and d1 the same way, then FUN_101ce720(w0 - w1, d0 - d1). Because step 1 runs after the turn, the
     arguments are always (0, 0): there is no re-centring, in either build. FUN_101ce720 still clamps the turned
     footprint to the floor's bounds (FUN_101ce490), and when that moves the piece it sets the level (0, or the
     cells' for a stackable piece) and carries the pieces on it by the same cells (FUN_101ce860).
  4. FUN_101d01d0 (flag bit 2, stackable): level = 0, then the height / 10 (FUN_101d73c0 -> FUN_101d01f0) of the
     last cell of the footprint (x < 0x14, z < 0x1a) that has one. A piece that is not stackable keeps its level.
  5. FUN_101d6c70(1) (SE 8059).
  In 30261006_0 steps 1 to 5 were inside `if (!wall)`; in 30261102_0 the wall test moved to the keys, which is the
  row's "re-centring before the FUN_101d01d0 test". The order of the steps did not change.

**The pieces on it.** FUN_101cf520 (FUN_101cdf50), for a surface (FUN_101d01c0, flag bit 1) with pieces on it
(+0x6c, +0x70..), first calls FUN_101ce8a0(piece on it, the surface, rot) (FUN_101cd2d0) for each:

- rx = its +0x14 - the surface's, rz = its +0x1c - the surface's.
- A four-way switch on rot (table 0x101ce968) whose two targets, 0x101ce8d2 and 0x101ce8f2, are the same code:
  new rx = FUN_101d00c0(surface) - rz - FUN_101d0110(piece), new rz = the old rx. The surface's width is the turned
  one, the piece's depth is the one before its own turn.
- Its +0x20 goes down by one (3 after 0), whichever way the surface turned.
- +0x14 = the surface's + rx, +0x1c = the surface's + rz; FUN_101cf520 and FUN_101cf360 for it. Its level stays.

So they turn with the surface about its first cell, always in the -1 direction: right for 0x8d, and for 0x8e
the surface turns one way and the pieces on it the other. The old note said they move without turning; that was a
misreading, FUN_101cd2d0 did the same in 30261006_0.

Escape's FUN_101ce520(6) also runs FUN_101cf520 on the surface before it empties +0x6c, but each piece on it is
then put back from its own record, so nothing shows.

**Ours.** `layout::rotate` (layout.rs): false for a wall piece; else the turn, the pieces on it by FUN_101ce8a0,
`shift(0, 0)` for the clamp with its delta given to the pieces on it, and a stackable piece's level over its new
cells. `held_keys`: each arrow's delta goes to the pieces on it as it happens, only the last arrow decides the
sound and the return, and the two turn keys together cancel. Tests `turns`, `rotate_and_walls`, `live_room`.

Not checked against a retail client on screen: the trace is the DLL only.
