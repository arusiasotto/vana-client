# XIV-UI — PR checklist (`xiv-ui` → `master`)

## Summary for reviewers

- **One mod** (`crates/vana-client/assets/mods/xiv-ui/`) bundles eight HUD panels (target, focus, cast, player, buff, exp, party, notify).
- **Staggered M18 bootstrap** + shared `src/` (`bridge`, `hud_config_factory`, `hud_drag`, `settings_proxy`, `migrate`).
- **Settings:** single `mod.toml`; per-panel `mod_*` + prefixed keys; layout in `storage.account.xiv_ui_<panel>_v1`.
- **Standalone `xiv-*` assets** remain in repo but should be **disabled** when using the suite (not deleted in this branch).

## Pre-merge verification

- [ ] `python3 crates/vana-client/assets/mods/xiv-ui/scripts/regen_all_m18.py --check`
- [ ] In-game: `/lua reload xiv-ui` with several `mod_*` on — no `no setting … in mod.toml`
- [ ] Disable duplicate standalone `xiv-*` mods for enabled panels
- [ ] Docs: `xiv-ui-audit.md`, `xiv-ui-client-pass.md`, `crates/.../xiv-ui/README.md`

## Suggested PR title

`feat(assets): XIV-UI suite mod (8-panel HUD bundle)`

## Suggested test notes

Enable `mod_target`, `mod_party`, `mod_buff`, `mod_player`; reload; drag layout; party cast strips with target on; buff cancel; XP attach to player bars.

## Out of scope (follow-ups)

- Catalogue/metadata entry if assets are enumerated elsewhere
- Removing or deprecating standalone `xiv-*` folders in assets
- Replacing client **Timers** recast window
- Full `source_files` migration for all panels (buff already live-src)