## Disengaging: `bntg`, `klbt`, `hwat`, and dying with the weapon out (2026-11-10)

<!-- dll-build: 30261102_0 -->

Modlog-gaps item 134 ("Motion schedulers bntg / klbt / hwat / res0; the move direction for atr / atb / atl", MODLOG
"PC battle motions", Open). Addresses are FFXiMain.dll 30261102_0, read in the decompile and the disassembly; every
function named here is unchanged from 30261006_0.

- Already built since the row was written: `res0` / `res2` ("/heal: sitting down and standing up", 2026-11-05), the
  moving swing's direction ("Swings while strafing: by the move's quarter", 2026-11-07), and the lock-on release when
  the status leaves 1 (FUN_10158c30(0) on the target object DAT_10579924, called from state 3; ours target::update).
- The entity's machine FUN_1008b460 (state byte +0x1bc) runs twice a frame from FUN_1008e9a0: before the applied
  status +0x170 takes the server's +0x16c, and again after (0x1008eb40 / 0x1008ec68). The engaged part:
  - State 3 (engaged, files in, weapon drawn) stays while the applied status is 1 or 3 (0x1008b7c4 / 0x1008b7cd). So a character
    who dies engaged keeps the battle files and the weapon in the hand, and sheathes when the status leaves 3 (a
    raise). On leaving: our lock-on is released, `bntg` starts through vtable +0x298(name, 0, 0) (FUN_100cee40:
    the actor's files, then DAT 0; FUN_10056c70 with no second actor), FUN_100d14c0 loads the normal skirt file
    (FUN_100d2d70, tag 5, when it is not on the list) and the normal upper-body file (FUN_100d2e30: skeleton + 1 +
    info[5], tag 0) on top of the list, plus the riding files when the new status rides (FUN_100d2800). Then state
    0x11, or 6 when the new status is healing (0x21 / 7).
  - States 0x11 and 6, from the next frame once the model is ready (FUN_100d12d0), without testing the status again:
    `klbt` (no second actor), "out N" (FUN_100d2ef0), `hwat` with the actor as second actor, +0x7d8 = four spaces,
    vtable +0x31c(0, 0) (sheathed), FUN_100cf160 (every glow off). 0x11 goes to state 5, 6 to state 7.
  - State 5 (the second call of that same frame at the earliest): once the model is ready and no `waot` runs on the
    actor (vtable +0x2a0), state 0 and FUN_100d44b0(1), which takes every tag-1 file (the battle files) off the list
    +0x7e4. State 7 does the same and starts `res0`.
- The schedulers are all in DAT 0 (`syst/acti`), and nothing else in the game files holds them except an unrelated
  `klbt` in effect file 70783 (a byte search of every DAT
  for the four names):
  - `bntg`, 300 ticks: op 0x07 for 300, no reactions (+0x80) on actor1. With +0x80 up FUN_100c83c0 picks no new
    status motion either, so the battle stance holds until the sheathe starts.
  - `klbt`, 10 ticks: waits 10, then op 0x5f `bntg` (0x10059b95): FUN_10056eb0 deletes every scheduler task of that
    resource, whoever it runs on, so one character's `klbt` also ends everyone else's `bntg`.
  - `hwat`: three op 0x75 with no length and no engaged gate: wep0 shown, wep1 shown, wep2 hidden. It is also the
    op 0x03 child of 2,049 swing schedulers (`atk0`, `cnt0`, ...). At the sheathe it undoes what a cast's `hwmg` or a
    shot left hidden, since the sheathe's op 0x07 keeps FUN_100c83c0 (which would show them) from running for
    its 72 ticks.
  - `waot`, 50 ticks of nothing. Only the dual wield sheathes start it (op 0x03 at tick 0 of the 34 "out N" in the
    24 dual wield battle files, ROM/108, 110..112, 114..116): their second hand's scheduler is looked up at tick 36
    (op 0x84), so the files have to stay on the list that long. A single weapon's "out N" plays its one
    motion at tick 0 and its files go off the list in the same frame.
- A hold is a child task of the scheduler that made it: ops 0x07 / 0x08 build FUN_100607e0 and ops 0x1f / 0x20 / 0x59
  FUN_100601f0 / FUN_10062650 with the scheduler task as parent (FUN_10074790 -> FUN_100747d0), the constructor
  takes the actor (vtable +0x160) and the destructor FUN_100608b0 lets it go (+0x164). Deleting a task deletes its
  children first (FUN_10074ad0 -> FUN_10074890). So a scheduler killed by op 0x5f or a stop gives its holds back
  at once; one that runs out has holds no longer than itself (its length is the longest op end, FUN_10056ae0).
- Ours now:
  - `actmotion::update` follows the states: the frame the status leaves 1 / 3 starts `bntg`
    (`Effects::on_scheduler_alone`); the next frame runs `klbt`, "out N", `hwat` and the sheathe; a status of 3
    keeps an engaged actor's files and drawn weapon (`Battle::held`), so the sheathe plays after a raise instead of
    at the moment of death.
  - A killed scheduler's holds already end with it (`task_holds` carry their task's uid), so `klbt` ends `bntg`'s
    hold.
  - Battle files retail has taken off the list become `Kind::Sheathed` (two frames after the sheathe starts, for our
    effect queue, and not while a `waot` runs on the actor): the sheathe's motions still resolve from them, standing
    in for the motion player's reference, but scheduler lookups (`actmotion::scheduler`, `scheduler_names`,
    the effect system's file list) no longer see them, so a swing that arrives late finds no `ati?`. They are dropped
    when the sheathe's play ends.
  - `rest::update` starts `res0` only after the sheathe (state 6 before state 7) and its `waot`.
- Not done: FUN_100d14c0's reload order (ours never takes the normal files off, and no name both lists hold is
  looked up while the sheathe's holds run); an actor whose status leaves 1 while its battle files are still loading
  (retail plays "in N" and then sheathes; ours draws nothing).
- Tests: fx::tasks::skillchain_tests::klbt_ends_bntg (DAT 0: the 300-tick hold, the kill at tick 10 from another
  actor's `klbt`, `hwat`'s three weapon ops),
  client::actmotion::tests::sheathed_files_keep_motions_only and battle_held.
- Not checked live: disengaging in the middle of a cast (the weapons should show through the sheathe), dying while
  engaged (weapon stays in the hand) and the sheathe after a raise.
