## Riding: op 0x6e on any actor, and what was left of the riding row (2026-11-10)

<!-- dll-build: 30261102_0 -->

Modlog-gaps item 135 ("Riding: ground tilt of info[0] 1 / 2 models (FUN_100d54c0); op 0x6e for other actors; the
riding `cdam`; the local player's wait for the stand motion before `coff`"). Three of the four parts were built or
closed after the row was written; the fourth is built here. The functions named below have the same addresses in
30261006_0.

- Already built: the ground tilt (MODLOG "Ground tilt", client/tilt.rs; the no-ground bits in "GroundFlag and
  HackMove stop the ground snap and tilt"); the local player's wait for the stand (MODLOG "Actor flow ... the dismount
  stand", ride Phase::Stopping; "Riding: a dismount while autorunning").
- `cdam`, closed by census: the 4cc is in 64 files, all riding files (38603.., 39246) and animals (39275 / 39276,
  55296, 55432, 102705..102768); `coff` in the same plus texture bytes. No event file and no code names either, so
  s2c 0x038 is the only way in, and it addresses actor1's own model (entity +0xa0), never the animal (+0xa4). LSB
  sends neither name and has no NPC or monster on a mount model (ids 4466..4529). The rider's `cdam` through 0x038
  already plays (holds 45, `chd?`, `bb1?`); the animals' `cdam` cannot start.
- Op 0x6e (FUN_10057fb0 -> FUN_100aad40) is not tied to animals: it sets actor1's +0x101, +0x118 = ticks, +0x11c =
  speed and +0x120 = RotY(the facing now) (1, 0, 0) x speed for any actor. FUN_100a57f0 (the movement update of
  every collision actor) then calls FUN_100aadf0 each frame:
  - another actor: only without +0x103 / +0x104 and without a running push (+0x102 goes first, except on the
    attached kinds, which take no push); the step is added to the drawn position (+0xc4 = +0x34 each frame through
    FUN_10086e90) and written to +0xd4;
  - our own player, free: the step first, then the input's move (FUN_100a5ec0) on top; in the locked branch
    (DAT_10457aac + 8) the step replaces the input for statuses 0 / 1 / 4 / 0x1c / 0x1f.
- FUN_100aadf0: t = the frame's ticks (at least 1); +0x118 -= t; while it stays above 0 the position gains +0x120
  once per started tick of t; the frame that brings it to 0 or below gains it once per started tick of the
  overshoot only and clears +0x101. So at 2 ticks a frame a run of n ticks moves n - 2 for an even n and n for an
  odd one (71: 35 x 2 + 1): the animals' `coff` (72 ticks, 12.0 / 10.0) covers 70 ticks, 14.0 / 11.67 units, not
  14.4 / 12.0. Ours (`ride::self_step`) runs that count on retail's 2-tick frame whatever our frame rate, so the
  distances are retail's, and draws each retail frame's way spread over our frames during the next 2 ticks; the
  leaving animal uses the same step.
- Ours: `ride::self_move` keeps the leaving animal's run and puts any other actor in `World::self_moves`
  (`ride::SelfMove`). The entity loop moves such an actor after the push branch: no slide, no turn, snapped to the
  floor when grounded, its motion ratio from the way moved; our own player moves through the walking collision before
  the input. Test `client::ride::tests::self_step_counts_retail_frames`. *(inf: what retail does with the goal
  (+0x24 / +0x44) when +0x101 clears is not traced. `ride::self_settle` keeps another actor where it was moved unless
  a slide was under way when the op started or a new server position came in meanwhile; without it the slide would
  jump back to the old goal at once, where retail at most walks back through FUN_100c63d0's chase. Test
  `client::ride::tests::self_move_settles_goal`. Nor traced: whether the floor snap and the motion ratio from the way
  moved match FUN_100c63d0's path while +0x101 holds.)*
- Not built: our own ratio freeze (FUN_100c8930) and the locked branch's rule; +0x103 / +0x104 are not traced. No
  retail data reaches any of it: op 0x6e is only in the animals' `coff` / `cdam` (102 schedulers).
- Not checked live: no server ran in this session. The animal's run after a dismount is 0.4 units shorter than
  before.
