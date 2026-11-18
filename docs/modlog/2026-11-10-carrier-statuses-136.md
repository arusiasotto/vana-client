## Carrier statuses 0x1a..0x1f, GroundMode, and the feet points (2026-11-10)

<!-- dll-build: 30261102_0 -->

Modlog-gaps item 136 ("Ground tilt: writers of +0x128 bit 14 and +0x120 bit 20; statuses 0x1a / 0x1b / 0x1d / 0x1e;
whether vt+0x1c4's bones include +0x998; long bodies' no-roll and scale overshoot"). The functions named below have
the same addresses in 30261006_0.

- Already answered: the writers of +0x128 bit 14 (HackMove) and +0x120 bit 20 (GroundFlag), MODLOG "GroundFlag and
  HackMove stop the ground snap and tilt".
- Statuses 0x1a..0x1f are a carrier and its riders, two sets (FUN_1008cd90, the entity update, called for index 0 up
  by FUN_10096640 through FUN_1008e9a0):
  - state in force (+0x170) 0x1a / 0x1b (set A) or 0x1d / 0x1e (set B): when the entity has a model that is an
    XiDoorActor (FUN_1002c8f0 on 0x10330d4c; lifts and ships are not), p = its part 0 translation (drawobj +0x624,
    what scheduler op 0x0c moves, FUN_10043d00 -> FUN_100acea0); step = p - last p, last p = p, in globals
    (A DAT_10486bb8 / DAT_10486bc8, B DAT_10486b98 / DAT_10486ba8) that nothing else writes or clears; +0x120 bit 21
    is set. For any other actor p is an unset stack vector. These are also the door states that open (0x1a / 0x1d)
    and close (0x1b / 0x1e), MODLOG "Doors".
  - bound actors (+0x120 bit 7) return before the rider part. Any other actor in status 0x1c (set A) or 0x1f (set B),
    after its slide step: position += the set's step, bit 21 set, the model placed at once (FUN_10092c20), and the
    server place +0x24 and the move start +0x44 = the new position. This runs with and without a model.
  - bit 21 is cleared at the top of the update for unbound actors, so it holds exactly while the status does.
- FUN_100983f0 (c2s 0x015) returns at once while our status in force is 0x1c or 0x1f: no position goes out. Its
  byte @0x15: bit 0 = +0x124 bit 18 (TargetMode), bit 1 = +0x124 bit 19 (RunMode), bit 2 GroundMode = +0x128 bit 14
  | +0x120 bit 21 | +0x120 bit 20, the three bits FUN_10084640 tests. @0x18 = FUN_100dc120() (TimeNow).
- FUN_10084640 itself is called only by FUN_100cbde0 (both tilt sites).
- Who sets the statuses: only the server's status byte (0x00D / 0x00E @0x1f, 0x037). Census
  `dat::event::status_census::event_status_census` over every zone's event code: op 0x4f (+0x174 = val + 0x12) is
  used 22 times with 0x12, 0x13, 0x15, 0x17, 0x19 only; op 0xac sub 1 with 0, 1, 2, 6, 0x22, 0x26, 0x27, 0x29, 0x2b,
  0x2f, 0x42, 0x44; op 0xac sub 0 (+0x16c) never; no operand is a variable. LSB names none of 0x1a..0x1f in a
  script or table.
- Event status ops: 0x4c / 0x4d / 0x4f / 0x8e / 0x8f write +0x174 on whatever actor runs them and skip while its
  +0x120 bit 2 is set; op 0xac sub 1 has no such test (asm 0x100bb1ee..0x100bb215).
- vt+0x1c4 on the skeleton classes (FUN_100d4560 -> FUN_1002c400 -> FUN_1002a780) reads the model's bone matrices
  (model +0x14 + bone x 0x40) and needs model +0x30 bit 4. FUN_100cbde0 poses them with FUN_1002c2d0(root = actor
  +0x998), the matrix the tilt wrote. So the feet points of FUN_100a4d10 are the last drawn pose on the last drawn
  world matrix, tilt included; before the first pose the call fails.
- Ours:
  - client/carrier.rs: `Carriers` (the two sets, the frame's publishes by index so an actor before its carrier
    still takes last frame's step), `carrier::update` after `doors::update`, the step added to riders in the entity
    loop after the slide (also after a push or an op 0x6e step) with the slide goal moved along, and to our own
    position. A carrier that is not a door publishes nothing (retail: undefined).
  - *(Open, for lenonk: retail's floor ray also meets door models (FUN_1017a660), so a rider stands on its carrier;
    ours has no door-model floors, so a rider's floor snap and our gravity follow the static floor and take back a
    rising carrier's lift. An earlier workaround (skip the floor and gravity while carried) was not retail and is
    gone; door floors are not built.)*
  - bit 21 from these statuses stops the ground tilt and the event ground snaps (`carrier::no_ground`).
  - c2s 0x015: GroundMode is sent (HackMove, GroundFlag, op 0x33's bit, the carrier statuses); no 0x015 while our
    status in force is 0x1c / 0x1f. LSB reads neither.
  - the door status ops (lock honoured) and op 0xac sub 1 (no lock test) already shared the one +0x174 field here;
    the event ground snap of a bound actor reads whichever of the two wrote last.
  - the feet normal uses the posed points of the last drawn frame through that frame's matrix (`Actor.feet`); such
    models (info[0] == info[2] == 2) pose on the CPU when they probe (the probe gate, FUN_100a4ed0, is in MODLOG
    "Ground tilt"). Before: the rest pose through this frame's untilted matrix.
- Not built: TargetMode / RunMode (+0x124 bits 18 / 19, writers not traced) and TimeNow in c2s 0x015; FUN_100ae3f0's
  copy of +0x174 into +0x16c / +0x170 at the event's end for entities with +0x138 bit 31 (op 0xac sub 2).
- Still open (footage only): the across-slope no-roll of long bodies and the scale overshoot.
- Not checked live: no server sends these statuses (LSB never does), and no server ran in this session.
