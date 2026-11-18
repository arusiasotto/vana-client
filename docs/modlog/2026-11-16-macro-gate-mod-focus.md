## The macro gate inside mod calls sees mod windows (2026-11-16)

- `game.info().macros` (and `menu_open`) count a mod window with the keys as a focused window (FUN_101a33e0's
  focus test). But every mod call moves the host out of the World first (`std::mem::take(&mut w.lua)`), so the
  World read from inside a pad / key filter or the mod phase held an empty host, and a focused mod window never shut
  the gate there. A crossbar mod's filter then fired slots while another window (its manager) had the keys.
- `Host::park` now moves the host out and leaves a stand-in that shares the mods' states (`Rc<RefCell<ModState>>`),
  `/lua hide` and the frame info, so every World-side query during the call (focused, typing, modal, the help bar,
  the edge panels) reads the mods as they are at that moment: a window closed, a mod hidden or unloaded (its state's
  `gone`) in the same call shows at once. A state its mod's code holds right then is passed over (`try_borrow`).
- `ui.native.menu_open()` now also counts a mod window with the keys inside mod calls (docs updated): map-overlay's
  Escape leaves the overlay open while such a window has the keys, as it does for the game's windows.
