## Camera shake: a new element's first kick comes in the frame it is made (2026-11-16)

<!-- dll-build: 30261102_0 -->

The point "Effect draw order" (2026-11-15) and "Camera shake" (2026-11-10) left open: ours ran op 0x5f before the
frame's emissions, so a new element's first camera kick came a frame after retail's. All addresses are build
30261102_0.

**Retail's frame.**
- The walk FUN_10074c30 runs the task list head to tail and takes each task's next (+0xc) before running it, so a
  task linked in ahead of the running one runs in the same walk. A task's step is FUN_10075000: vtable +0x20, then
  +0x24 when that returns 0.
- A generator's task (vtable 0x1032c654, +0x24 FUN_10054220 -> FUN_100496f0(0)) sits in bucket 8 or 9, or just before
  the task that started it (FUN_10075120). It makes its elements there; the factory FUN_1004e8d0 puts each one at the
  front of bucket 0xb (FUN_100749b0 -> FUN_10074f80), ahead of the walk. So the element's first update is in the frame
  it is made.
- An element's update (+0x20 FUN_10045a40, all element vtables from 0x1032bc90): FUN_10044ae0 counts the life down by
  the frame's ticks (DAT_1047d158 +0xeb0) when +0x114 is not 0 and, under 1, runs the end stream (FUN_1004e720) and
  deletes it; then the update stream FUN_1004a980, op 0x5f included (it starts by setting the visibility +0x138 to 1).
  Unless an op left +0x138 at 0, it goes on to FUN_10044d40 and the ordering table (FUN_10045920 -> FUN_100458f0),
  whose draw task (bucket 0xc) runs later in the same walk: the first update is a whole one, drawn.
- An element made inside an element's update goes to the same front of bucket 0xb, which the walk has passed, so its
  first update is the next frame: the end stream's burst (FUN_1004e720) and an element's clone (update ops 0x25 at
  0x1004b5d0, 0x33 / 0x46 at 0x1004b604 -> FUN_100496f0 with the element).

**Ours.**
- `Effects::tick` ran the lives and op 0x5f before the generators, and a new element's life started counting the next
  frame on both sides (ctl::LIFE_SET). Now an element a generator's task makes after the lives gets its first update
  after the generators (`first_run`, `step_life`): its life counted down once, on the GPU too (neither ctl::LIFE_SET
  nor ctl::BORN, so it is drawn in that frame at that life), and op 0x5f runs after that, so its kick comes in its
  first frame, ahead of the older elements' (`run_order`). `ElemCpu::late` marks one made inside an element's update
  (the lives' end streams, an element's clone): no life step and no kick in the frame it is made, where ours had run
  the kick at t = 0.
- Op 0x5f now also runs after the generators for the old elements, as retail's walk does: their parent frames are
  this frame's.
- Test: `first_kick_in_the_frame_made` (3445 gob_/vib1, from the game files).

**Not changed.**
- Elements made before the lives (scheduler ops, the footstep dust, `on_action`) keep ctl::LIFE_SET while the CPU's
  lives count them down in that frame: the GPU runs a frame behind the CPU for them. *(Not traced: the buckets of
  the scheduler and actor tasks that make them.)*
- Retail does not update a late element in the frame it is made; the GPU still runs its update stream at t = 0 there
  (not drawn).
- The ctl::BORN rule (a new element with a life not drawn in its first frame, *inferred*) stays for the elements
  made before the lives and the late ones.
