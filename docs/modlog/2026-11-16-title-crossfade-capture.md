## Title movie crossfade: the outgoing frame captured once (2026-11-16)

- Op 0x10 in a title movie fades out the frame before the cut over the new shot, as the world's crossfade does
  (event.rs `Cross`, `cross_capture`). `Flyover::render` drew the outgoing shot again on every frame of the crossfade,
  in the same command encoder as the new shot. The zone's uniforms go up with `queue.write_buffer`, so both passes
  read the camera written last (the new one), while CPU run culling (`Cull::runs_shown`) for the outgoing pass had used
  the old camera: runs the old camera could not see were skipped and dropped out of the faded image (Pashhow `mov4`,
  the marsh bed around the cut at about 30 s; one terrain draw, `or_la_coi1_m`, a mirrored instance).
- Now the outgoing frame is drawn once, offscreen, from the camera it had, in its own submit, then faded out as a still.
  The zone is drawn once per frame during a crossfade instead of twice.
