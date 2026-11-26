<!-- dll-build: 30261102_0 -->
## Actors are drawn at the actor update's eased place, and turn along it (2026-11-18)

- Report: with B held (Compact 2) the body turned toward the stick roughly, with single frames where it swung sideways
  and back; retail turns a little more each frame.
- The actor update is FUN_100c63d0 (the earlier fragments' FUN_100c5d60 is the actor's reset in this build). For an
  actor that is not on a lift (vt+0x19c, +0x5e2 from FUN_100a4ed0), riding only with a mount actor (below) and without
  the forced-move flags +0x101..+0x104, it eases the drawn position +0x5fc (vt+0x1bc) 0.125 a tick (_DAT_1032b3bc, its
  loop once per whole tick of FUN_10014cf0, at least one) toward the collision position +0x5c4 that FUN_100a4ed0 walks
  (0x100c6591); on a lift it takes the position as it is. The step +0x5fc moved is the turn's aim (2026-11-17), and the
  update adds it to +0x5fc after the attach block (+0x7a4). The skeleton is posed at +0x678 / +0x688, copies of +0x5fc /
  +0x61c made at the end of the update (FUN_100d4560 -> FUN_1002c3e0), and the camera follows vt+0x1bc. So retail draws
  us trailing a steady run by 0.875^2 / (1 - 0.875^2) frames of the move (about half a yalm running) and glides onto the
  spot after a stop.
- The turn is the same code with or without the strafe lock: free (vt+0x330, +0xf9), not riding under it, the drawn
  rotation +0x61c eases 0.125 a tick toward the aim (the drawn step, or this frame's displacement when the drawn step
  points against it), else toward the heading +0x39; when it aimed, +0x44 takes it (not in first person, DAT_10489130),
  which FUN_100a57f0 makes the heading next frame. Free, FUN_100a6240 then turns the heading to the move, so the body
  follows the drawn path round a corner rather than snapping to the stick; standing, the heading is what the body last
  aimed at.
- The strafe lock's quarter (FUN_100a6240 0x100a6e57 -> FUN_100a80d0): the point one unit along the heading +0xe8 from
  +0x5fc, less the collision position +0xd4 (FUN_100a57c0, the last frame's walk), normalised and split at +-45 degrees
  (0x3f490e56) against the move. That is the heading less how far the model trails, taken each frame before its move.
- Ours: World::turn_draw is +0x5fc for all our drawing now (update_movement's step loop, strafe_lock_turn), snapped on a
  lift, a place set from outside (zone-in, keep_pose, a scheduler's pin) and before the first frame; draw_pos runs from
  the last retail frame's +0x5fc to this one's over the frame. The free third-person turn (World::turn_rot, with or
  without B) is the actor update's per retail frame, drawn between the last two frames the same way; strafe_lock_quarter
  is the quarter. Locked on, first person, under the right drag's facing, the forced follow, events and a pin keep the
  ease toward the heading as before.
- Remote actors: all three skeleton actor vtables (0x1032e710, 0x10331f40, 0x103323e8) have FUN_100c63d0 at slot 0x20
  and vt+0x1bc = FUN_100a4740 (+0x5fc), so NPCs and other players ease the same way. Their collision position comes from
  the entity slide (+4 -> +0x34, FUN_1008f740; +0x34 -> +0xc4, FUN_10086e90; +0xc4 -> +0xd4, FUN_100a57c0; ground snap
  -> +0x5c4, FUN_100a4ed0). The drawn place is set to it (FUN_10092c20 / FUN_100929d0 / FUN_10092f90 write +0x34,
  +0x5fc, +0x5c4, +0xd4, +0xc4) by FUN_100929a0, which FUN_1008cd90 calls for a slide jump over 12 (_DAT_1032e6b8, 144 =
  12 squared) and the place setters (FUN_100ab830 / 100ab880 / 100c3ff0 / 100c4050) and zone-in (FUN_100ae3f0) call;
  every frame for a status 0x1c or 0x1f rider; and by the push (+0x102) and self-move (+0x101). Not ours, the turn aims
  only at the drawn step (no displacement test). Ours: Entity::drawn (ease_drawn), snapped for the cases above, a lift,
  a fresh spawn and a place set from outside; base_place poses at it; the facing aims through drawn_aim at 0.01 a retail
  frame. Doors, lifts and ship models are not skeleton actors and are not eased.
- Remote actors, review round: the drawn step (fStack_26c) also feeds the walk / run motion (FUN_100c83c0 ->
  FUN_100c8930 takes its length for an actor not ours, vt+0x304 == 0), so one gliding to a stop keeps its feet moving.
  A jump over 12 and a 0x1c / 0x1f rider have +0x5fc set before the update (FUN_100929a0 / FUN_10092c20 in
  FUN_1008cd90): their drawn step is 0 (no turn toward the jump or the carrier's move, no motion); a lift keeps the
  whole step. Name plates and target arrows of actors not ours sit at the drawn place too (+0x678 follows +0x5fc), as
  ours already did.
- Riding (status 5 / 0x55, FUN_10084350 / 70 on the entity's +0x170): FUN_1008f740 builds the mount as a second actor
  (entity +0xa4, FUN_100c59b0 / FUN_100d7240), and for a chocobo (kind DAT_1035c4d0[colour], 0..0x3e) or a mount (id + 5
  under 0x25) puts it at the rider's +0x768 (slot 0). With +0x768 set, 0x100c655c goes on to the same ease (0x100c6591);
  only without it (no mount actor yet) does the drawn place stay (step 0, DAT_1035e710). The turn aims at the drawn step
  riding too; only our own actor riding under the strafe lock (vt+0x340, +0xfb) eases toward the heading instead.
  Statuses 0x1c and 0x1f are both snapped every frame (FUN_1008cd90 calls FUN_10092c20 in both branches). At the end of
  our own update while riding, FUN_100c8280 tests the segment from (1.1, -1, 0) to (0.8, -1, 0) in the drawn frame
  (+0x61c / +0x620 / +0x624 rotation, +0x5fc place) against the zone (FUN_10182b60 -> FUN_1016a980) and on a hit moves
  +0x5fc by the hit less the start in x and z, so the mount's head stops at a wall. Ours: the rider's drawn place is
  turn_draw as walking (drawn_between_steps removed), the free turn runs riding unless B is held, rider_nose is
  FUN_100c8280 (yaw only: our drawn rotation has no x / z part), remote riders ease like walkers.
- Flagged for lenonk: (1) Retail's FUN_1008cd90 skips the over-12 jump for an actor on a lift (vt+0x19c); ours still
  jumps there. (2) The rider's step-0 case (no mount actor at +0x768 yet) is not ported: ours always has the mount. (3)
  Drawing between retail frames (position and rotation) is ours: retail draws once per frame of its own; remote actors
  ease continuously per tick (0.875^ticks) rather than once per whole tick.
- Checked against retail after testing (twitch on turning round with B held, the body turning sideways at a wall):
  - A wall: retail's per-face push (FUN_101708f0, called from FUN_1016ff00 via FUN_101706b0's 0.15 march) moves the
    sphere out by sqrt(0.25 - d^2) along the face normal, not to the surface; running head-on into a wall lands 0.17
    back off it every other frame, ours too. The turn's displacement test then aims at the move (into the wall), so
    head-on the body keeps facing the wall. Off square, the drawn step slides along the wall and the body turns toward
    it (3 degrees off turns it about 10, 30 off faces along the wall), the same rule as above. No difference from the
    DLL was found in the collision, the drawn place or the turn.
  - Turning round with B held: per retail frame the first frame of a reversal aims at the move (dot < 0), so the body
    turns 42 degrees, then about 32, 25, ... one way only; the quarter (FUN_100a80d0: heading plus +0x5fc less +0xd4,
    DAT_1035cbdc = (1, 0, 0)) goes 3, 4 (or 2) for about five frames, then 1, so the motion goes mvb, mvl / mvr, run.
  - Ours, for testing in game: FFXI_DRAW_30HZ draws our model at the last retail frame (no drawing between frames);
    FFXI_TRACE_MOVE logs each retail frame's view and stick angles, quarter, positions, drawn step, aim and rotation.
- Movement Rate (Settings, not retail; config `move_rate`, 30 by default): 60 runs our own actor update once per tick
  instead of once per two, as retail does when played at 60 frames a second with an fps add-on (FUN_10014cf0 runs the
  update once per whole tick it is given). A trace of retail at 60 showed the B-held reversal turning 16 to 21 degrees
  a frame and sideways steps of 0.0625 a frame; at 30 the same logic turns up to 42 degrees a frame. The step's speeds,
  the walls and falls, and the drawn place and rotation's 0.125-a-tick ease all take the frame's ticks; remote actors
  already ran per tick.
