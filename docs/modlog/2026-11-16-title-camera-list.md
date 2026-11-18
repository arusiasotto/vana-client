## Title movie: the camera list under the movie camera (2026-11-16)

Addresses are 30261102's.

- The lobby state `FUN_10013ad0` draws through camera lists as the world state does. Case 0 creates the camera object
  (`FUN_1001e470` sets game `+0x50`). Each frame, case 1 probes the collision under that camera (`FUN_101829c0`: from
  0.51 above the eye, 100 down, else 15 up; constants at `0x103378d0`) and copies the list the hit names into the scene
  (`FUN_1017a960` -> `+0x3912c`, the list `FUN_1017cae0` draws from).
- Ours: the flyover set no list, so it drew every placement. Ru'Aun Gardens (`ex1c`) places a detailed mesh and a
  simpler stand-in at one spot in 113 places (`bri_gate_a_h` / `m_bri_gate_a`, `osid_cen_pb_m` / `m_osid_cen_pa`), and
  both of each pair z-fought. `FlyoverData` now builds the zone's `Ground` on the loader thread, and each frame the
  list under the movie camera goes to `set_camera_list`; the crossfade's capture gets the list under the outgoing
  camera. As in the world, past the Retail Draw Distance the list holds within retail's reach (`far`, from the zone's
  draw distance under the Clipping factor) and the rest draws beyond it, of a variant group only the simplest mesh.
