## Find Member: Refine over the party menu (2026-11-22)

<!-- dll-build: 30261102_0 -->

- The party menu's row handler (FUN_102074e0 / FUN_10207720) runs Find Member (FUN_10206270) and leaves `prty*`
  open: the condition is built by FUN_1020bc10 (status 0x8020 through FUN_10107fc0), searched with mode 1
  (FUN_1020bfe0), and the results take title 0xd 0x13. Nothing closes.
- Enter on the results header (scresult's handler FUN_1020d860) opens `menu    scsibori` for modes 1 and 2
  (FUN_1015f920) over what is open, so the party menu, the results and Refine are all up at once.
- The classic UI drew them that way already. The modern window panel drew the party menu and returned, so Refine had
  the keys but was never shown; now the party menu yields the panel while Search is refining.
- Not traced: a results row of type 2 opens sccomite / sccompar / sccomls (refine by comment genre, mode 2).
- Not checked in game.
