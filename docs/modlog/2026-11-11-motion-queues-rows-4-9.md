## Motions: the model's region queues (2026-11-11)

<!-- dll-build: 30261102_0 -->

Queue rows 4 and 9 of the modlog-gaps queue (the mouth's 8-tick fade; the phase carry per region). Checked in game
on an LSB server: run start / stop, swings and hit reactions, strafing while engaged, emotes, death and raise,
engage / disengage. Not yet checked: an NPC's line closing (row 4), guard / parry, blend smoothness.

- Retail keeps seven queues per model, one per body region, each a list of weighted entries (FUN_1001ad00 queues,
  FUN_1001a3e0 ticks, FUN_1001a420 poses). Ours had one status-motion clock, a whole-pose cross-fade (`prev`, `keep`,
  `under`) and a single overlay slot. Now `Actor::q` (crate::motionq) is those queues and the pose block
  (client/mod.rs pose_actors) only feeds it; the posers (render/anim.rs on the GPU, dat::character::pose_layers on
  the CPU) take the queues' entries as layers.
- Row 9: a motion queued with the carry (the status motion, FUN_100c83c0) starts in each region at the phase of
  that region's last entry, plus half the blend at the new rate. A motion that keys only some regions no longer
  takes one phase into all of them. The formula is the binary's: old frame x old speed / old frames, so only a true
  fraction of the cycle at speed 1.
- Row 4: op 0x23's close, unbind and op 0x7c call `Actor::mouth_off` (FUN_100ce160): every motion in region 4 runs
  8 more ticks, then goes. A playing entry keeps its weight for those ticks; one still blending in keeps rising.
- The blend between entries of a region is retail's: the newer entry's weight runs 0 -> 1 over its blend-in and it
  is laid over the older ones bone by bone (rotation by a straight lerp toward the nearer of q / -q, FUN_10033220);
  the older entry is dropped when its out timer ends. A fourth entry in a region cuts the oldest within a tick.
  Higher regions win a bone (4 down to 0); regions 5 and 6 are posed apart and blended over by the region's weight.
- What changed with it, each as the binary has it:
  - Scheduler op 0x05 motions (swings, deaths, event and emote motions) start at their op's start frame, not at
    a carried phase; the op's out length (u16 @0x1c) and half (top nibble of byte @0x1f: first or second half of
    the frames) are read. Op 0x28 queues the status motion with its blend-in (f32 @8), a planned play's too, and
    past the +0x80 hold (its handler calls FUN_100cd920 directly, 0x1005b0c8..0x1005b12e).
  - A counted motion's end raises the model's flag (+0x79c) from the queue itself; FUN_100c83c0 then queues the
    status motion again in all its regions, from frame 0, blended in over the counted motion's out length. So
    after a moving swing (which keys the upper body only) the leg cycle starts over through that blend; before,
    ours left the legs in step.
  - A status motion whose name changes while a counted motion plays, with no +0x80 hold, is queued over it.
  - Reactions (ops 0x25 / 0x21) go to overlay region 5; a moving guard or parry too; a standing guard or parry is
    a counted motion in its chunks' regions. Several can overlap (the queue holds them).
  - A spoken line's mouth is the entity's face motion (one chunk by its whole name) in region 4, in over 8 ticks;
    without it `mou6` plays as an overlay in region 6, in over 16 and out over 8. A blink is `eye3` in region 3.
  - Event op 0xd3 fades regions 3 and 6 only (FUN_100ce070: queues +0x60 / +0x9c of the queues at model +0x24,
    0x14 a region); ours ended the actor's scheduler motions. This supersedes "Event op 0xd3: end the actor's
    motions" (2026-11-02) in MODLOG.md, which read +0x60 / +0x9c as both motion lists.
  - A PC look whose body has no skirt set (info[9] == 0) queues no region 2 chunk (FUN_100cd540).
  - A bone a region 1..4 chunk names without keying (rot index bit 31) goes back toward the rest pose by the
    entry's weight over an older entry of that region that keyed it (FUN_10019ee0).
  - A blend of 0 counts as 1 tick (0x1001ad77) in the new entry, the phase carry and the old entry's fade.
  - The motion link (event op 0xae 5, FUN_100cb400) holds each region's newest entry to the leader's.
- Ours, marked in the code: a dead actor's corpse motion waits for the death motion's end only while a motion of
  ours is running; a held actor with nothing queued still takes its status motion (not the fishing rod); with
  nothing playing at all the model's idle stands in for a status motion it lacks. The queues go on over a look
  change only on the same skeleton with shared model tracks. FUN_100cd540's `jmp*` pass (region 1 from `run1`)
  is not modelled.
- Performance: one pose per actor on the GPU instead of two during a cross-fade (scratch halved); animations are
  found by index instead of a pointer search per layer per frame.
- Tests: motionq (queue rows, fades, counted ends, overlay weights), render::anim (GPU against the CPU poser with
  a mid-blend and an overlay), `queue_frames` (ignored; writes PNGs of a walk-to-run blend and a mouth cut-off).
