# XIV-UI (suite mod)

One mod loads the FFXIV-style HUD panels that used to ship as separate **`xiv-*`** assets (`xiv-target-bar`, `xiv-focus-target`, `xiv-cast-bar`, `xiv-player-bars`, `xiv-buff-bar`, `xiv-exp-bar`, `xiv-party-list`, `xiv-notify`).

## Using the suite

1. Open **XIV-UI** in the Mods window (not the old per-panel mods).
2. Turn on **`mod_<panel>`** for each panel you want, then **`/lua reload xiv-ui`** if that panel was off at the last reload.
3. **Disable or unload the matching standalone `xiv-*` mod** for any panel you enable here. Running both can duplicate HUD elements and compete for natives.

## Saves and layout

- Panel positions and non-manifest options live in **`storage.account.xiv_ui_<panel>_v1`** buckets (see `src/migrate.lua`).
- On first load, **`migrate.lua`** may copy values from legacy **`storage.account.xiv_ui_v1`** into per-panel buckets when a bucket is still empty.
- Layout keys (`offset_x`, `place_x`, …) are **not** in suite `mod.toml`; use drag in-game or the hud_config editor APIs.

## Developer layout

| Path | Role |
|------|------|
| `init.lua` | Suite loader, frame pump, settings toggle hints |
| `mod.toml` | **Only** manifest (permissions, settings, commands) |
| `modules/<panel>/entry.lua` | Panel runtime (always read from disk) |
| `modules/<panel>/manifest.lua` | Chunks or `source_files`, import list |
| `modules/<panel>/src/` | Panel sources (embedded in `_m18_*.lua` except buff) |
| `src/` | Shared bridge, bootstrap, `hud_config_factory`, `hud_drag`, migrate |
| `scripts/` | Integration and M18 maintenance — see `scripts/README.md` |

There is **no** `modules/*/init.lua`; standalone `init.lua` files are not loaded by the suite (integration copies body into `entry.lua` only).