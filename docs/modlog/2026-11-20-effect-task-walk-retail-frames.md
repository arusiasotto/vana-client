## Effect schedulers: the task walk once a retail frame at any frame rate (2026-11-20)

<!-- dll-build: 30261102_0 -->

- Retail walks the effect tasks once a frame, and each task's countdown takes the frame's ticks: FUN_10057e10 takes
  `DAT_1047d158 +0xeb0` (or the Vana'diel change DAT_1065dcc4 for a clock task) before its ops, carrying the overshoot
  into the next op's wait. FUN_10069f90 sets +0xeb0 each frame to FUN_10014cf0: whole ticks, at least 2 (30 fps),
  at most 20 (FUN_10011a00; MODLOG "Camera shake"). A new task's first step is the same whole update (FUN_100748c0 ->
  vtable +0x20), so it takes the frame's ticks too; so does a task caught up by FUN_10056b20, right after the skip.
- Ours stepped the tasks every frame of ours with that frame's ticks, and a new task's first step took none. At
  300 fps a wait could end up to a retail frame later than at 30 fps (a damage number's digits,
  `damv_life_by_frame_rate`), and at any rate every wait after a task's start was one retail frame longer than
  retail's.
- Now (`Effects::tick`): a retail frame starts at our tick nearest its start (half a tick of ours either way, so
  frame-time jitter at 30 fps never skips a walk); the walk runs then with the frame's whole ticks (at least 2, the
  fraction carried, what is past 20 dropped, as FUN_10014cf0 drops it). Starts asked for (`run_pending`) run once a
  frame too, before the walk, so one asked part way through a retail frame starts with the next, as at 30 fps. Each
  task keeps the serial of the walk it last took a frame's ticks in (`Task::walked`), its first step's included: the
  walk passes a task already stamped (once a frame, whatever its slot), and a paused task is not stamped. What the
  tasks own (holds, roots, pins, light ramps, colour drives) still counts down every tick of ours. A step back of the
  Vana'diel clock counts as no change for op 0x52.
- Tests: the ones that stepped 1-tick frames now step retail frames (2 ticks) and count frames. Without DATs:
  `record_loop_same_frames_at_any_rate` (the same retail frames at 30, 60, 120, 144 and 300 fps),
  `start_part_way_through_a_frame_waits_for_the_next`, `child_in_earlier_slot_before_the_walk_is_passed`,
  `walk_cadence_under_jitter_and_stalls`, `clock_step_back_counts_as_none`. With DATs, the first step's ticks move
  `fist_hit_sparks` (three nested starts, each a frame shorter), `klbt_ends_bntg`, `clone_inherits_wait` (78) and
  Selbina's `pat2` (2 ticks ahead of the clock).
