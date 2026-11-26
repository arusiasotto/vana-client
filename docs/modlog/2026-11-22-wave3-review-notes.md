## Effects: a relative drive's first frame, killed tasks, the end op's wait (2026-11-22)

lenonk's review notes on rows 137 and 160, checked in FFXiMain 30261102_0.

- A relative path drive (op 0x26 / 0x27, flags bit 0 clear) moves nothing on its first update and starts its later
  moves from the point that update reached, so the first retail frame's stretch of the path never shows. That frame
  is the walk's ticks (the retail frame the creating op ran in), not ours: at 300 fps the drive used to skip only a
  tenth of it and end further along. `Drive::new` takes the walk's ticks; until the time passes them the actor stays.
  Ships use absolute drives and are not affected.
- Killed tasks go through their destructor (FUN_100574a0): a parent waiting on one runs on (FUN_10074a50) and its
  action ends, as for a task that ran to its end. That covers op 0x85 / 0x5f's kills, a sequence's, a stopped actor
  scheduler, a released file, a departed actor and a look change (`kill_tasks_where`). Before, those only emptied
  the slot, and with ended tasks now living two more updates, a waited child killed then left its parent waiting.
- The end op's wait (op 0, i16 @4, `dat::sched::end_wait`) goes on the countdown before the end, as FUN_10057e10
  adds every op's: the task waits it out with no op left before FUN_10057c20. Only ROM2/14/97 `s009` has one (29
  ticks). The catch-up (fast-forward) and a looping end do not add it.
