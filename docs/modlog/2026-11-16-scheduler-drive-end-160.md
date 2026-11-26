## Scheduler end and path drive end (2026-11-16)

<!-- dll-build: 30261102_0 -->

Modlog-gaps item 160 ("Scheduler end and drive end", found by 137). The 137 reading stopped at the drive's last
write and so saw a ship thrown back to its path's far end as it docks. The step it lacked is in the actor's own
update; no retail footage is needed.

- A drive's end. FUN_1005e9c0, time below 0 and +0xa0 set: the point at u = 1.0 goes to the actor's +0xd4
  (0x1005ea0b, FUN_100a57c0) whatever the direction, the heading toward it to +0xe4, then the drive deletes itself
  and its destructor lets the actor go (FUN_1005f2c0 -> vt +0x17c = FUN_10081fd0 clears +0x88 bit 0).
- The actor's update. The model actor's FUN_100c47f0 starts with the control actor's FUN_100a57f0, and only then
  copies +0xd4 to the drawn position +0x734, and +0x734 back to +0x34 and +0xd4. FUN_100a57f0 reads +0x88 bit 0
  (0x100a5825; 137 found no reader): set, it works from +0xd4 as the drive left it; clear, it first sets the
  heading target +0xe4 from +0x44, and works from +0xc4, which FUN_10086e90 has just set from +0x34 (it always
  answers 0). It ends by writing +0xd4 (FUN_100a57c0) and +0x44 from +0xe4. A ship has none of the moves in between
  (vt +0x304 = FUN_100a4640 is "the player's own actor"; +0x101, the timed move, has one writer, a scheduler op's
  FUN_100aad40).
- So the end's write never shows, in either order of the two in a frame. Drive first: the actor's update of the
  same frame finds bit 0 clear and takes +0x34, the position its update of the frame before drew. Actor first: it
  draws the drive's last running point and stores it in +0x34; the drive then ends; the next update takes +0x34.
  The same holds for the heading target (+0x44 is the target of the last update that ran held). A ship stays where
  the drive's last running frame put it: the path's end for its direction when the time comes out at exactly 0,
  else the point one frame short of it. Only a first facing stays (+0xa3 clear: written to +0x744 / +0x44
  themselves). Ours applied u = 1.0 at the end: file 31010 `seq7` (Port Jeuno, leaving the Kazham berth), whose
  backward `ptv2` ends 60 ticks before the sequence, put the airship back where `ptv2` began for that second.
  `Drive::step` now sets nothing at its end but a first facing.
- A scheduler's end. FUN_10057e10: the end op (type 0) runs like any op and only leaves +0x88 clear (FUN_10062de0
  with no next op). The update after finds +0x88 clear and the countdown 0 and calls FUN_10057c20: an op 0x01 in
  the end stream (resource +0x78; the main stream's leading op 0x01 is not looked at) or +0x141 starts it over
  (FUN_100573e0), else +0x145 is set. The update after that tests +0x145 first and deletes the task. Its destructor
  (FUN_100574a0) is where a parent that waits on it is let go (+0x84, FUN_10074a50), its action's callback runs
  (+0xac) and its children are deleted (drives, holds: FUN_10074890). Ours did all of that in the step that reached
  the end. `Task.ended` / `Task.dying` now carry the two updates: what a scheduler owns lives two frames longer, a
  calling parent goes on two frames later, in the frame its child is deleted (a scheduler is linked before the task
  that started it, FUN_10075120, so the parent's update comes after it; ours steps a parent in an earlier slot
  there and then). A catch-up that runs out inside its skip still deletes at once (FUN_100575a0), as does a clone
  at its block's end.
- With both, a ship sequence whose drive lasts to its end (31011 `seq0`: 2700 ticks) has the drive's last running
  frame in the frame the end op runs, the drive's own end the frame after, the task gone the frame after that.

Traced, not built (new queue row):

- A task runs twice in a frame where it starts a scheduler whose first step makes any task, and this is wider than
  137 noted. The walk FUN_10074c30 keeps its next pointer at +0xd5c. A new scheduler is linked before the running
  task T (FUN_10057270 -> FUN_10074a00 -> FUN_10075120; the unlink FUN_100751b0 puts +0xd5c back) and updated at
  once with itself as the running task (FUN_100748c0, which saves +0xd4c but not +0xd5c). Any task its first step
  makes is linked after it, so before T, and FUN_100750b0 (0x100750ff) sets +0xd5c to it; one that is re-linked
  before the scheduler (a sub-scheduler, FUN_100531d0 / FUN_10053370's tasks) leaves +0xd5c on the scheduler's
  next, which is T or a task before T. When T returns the walk goes on from there and reaches T again: T's update
  runs a second time with the frame's ticks. T is the entity loop (FUN_100106c0 -> FUN_10096640: every actor's
  update twice) for a start from an actor's update, or a scheduler for an op that starts one (its countdown loses
  a second frame). Ours keeps tasks, drives and generators in separate lists with no such order; building it needs
  a model of retail's one list.
- How a server position reaches a model actor after its creation (ships.rs's "seen on the retail client" rule) is
  still not traced: FUN_100a57f0 itself moves an undriven ship nowhere.

Tests: `drive::tests::end_sets_no_position`, `jeuno_leaving_drive_end`, `sequence_dies_two_frames_after_its_end`;
`skill_files_dropped_at_main_end` now sees the skill file go two frames later (frames 72 and 101). Not checked live.
