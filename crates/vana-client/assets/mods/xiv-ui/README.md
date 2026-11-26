# XIV-UI (suite mod)

One mod bundles eight FFXIV-style HUD panels (target, focus, cast, player, buff, experience, party, notify) behind per-panel **`mod_<panel>`** toggles in a single `mod.toml`.

The catalogue lists **`xiv-ui` only** — not separate per-panel mod ids. All panel code ships under `modules/<panel>/` inside this tree. `scripts/` helpers take arbitrary folder names on a maintainer machine when porting; they are not loaded at runtime.

## Using the suite

1. Open **XIV-UI** in the Mods window.
2. Turn on **`mod_<panel>`** for each panel you want, then **`/lua reload xiv-ui`** if that panel was off at the last reload.
3. Turning a panel off hides it without reload; turning one on after it was off at load still needs reload.

## Saves and layout

- Panel positions and non-manifest options live in **`storage.account.xiv_ui_<panel>_v1`** buckets for this mod only.
- Layout keys (`offset_x`, `place_x`, …) are **not** in suite `mod.toml`; they live in each panel’s `config_schema.lua` bucket (`xiv_ui_<panel>_v1`) and `xiv_config` when exposed there.
- **Notify:** toast position uses that layout bucket; invite reminder offsets (`notify_request_offset_*`), scale, seconds, and toggles are **`notify_*` keys in `mod.toml`** only.

## Developer layout

| Path | Role |
|------|------|
| `init.lua` | Suite loader, frame pump, settings toggle hints |
| `mod.toml` | **Only** manifest (permissions, settings, commands) |
| `modules/<panel>/entry.lua` | Panel runtime (always read from disk) |
| `modules/<panel>/manifest.lua` | `source_files` import list per panel |
| `modules/<panel>/src/` | Panel Lua loaded at runtime |
| `img/` | Retained PNGs only: `jobs/` (22); vitals, notify, and mog indicator use `hud` primitives |
| `src/` | Shared bridge, bootstrap, `xiv_renderer` (`src.xiv` per panel), `hud_config_factory`, `hud_drag` |
| `scripts/` | Manifest / integration tools — see `scripts/README.md` |

Panel **`entry.lua`** files are the runtime entry points; there is no separate `modules/*/init.lua` in the suite.

## Native HUD coverage

With the matching `mod_*` toggles on, panels hide or redraw the usual combat HUD pieces: **target** (incl. status/debuff strip), **focus/last**, **cast**, **party/alliance**, **your buff row**, and the **experience** strip. **Player bars** draw custom vitals over the hotbar area. **Notify** adds toasts; it does not replace a large native window.

The client **Timers** edge window (especially **recast** lists) is **not** replaced — keep Timers or another mod if you want recasts.

## Third-party attributions

- **Party trust job hints** (`modules/party/src/trusts.lua`): NPC name → job table derived from [Tylas11/XivParty](https://github.com/Tylas11/XivParty) `jobs.lua` (also shipped in [maybeLynd/XivUI](https://github.com/maybeLynd/XivUI)). The file includes the upstream BSD-3 notice block from `jobs.lua`. XIV-UI is not affiliated with, sponsored by, or endorsed by XivParty or XivUI.
- **Tooltip helper** (`modules/*/src/tooltip.lua` where present): adapted from XivUI with maintainer permission; vana `hud` API.
- **Job badge art** (`img/jobs/*.png`): rasterized from vana-client modern pack SVGs (same pictograms as the native party list), not FFXIV/Windower job portrait assets.
- **Player vitals strip**: native `hud.bar` HP/MP/TP (same API as the bundled `player-bars` mod); no `m5_*` fill PNGs.
- **Party list vitals / cast strips**: native `hud.bar` (no row/track PNG chrome); job badges still use `img/jobs/`.
- **Target, focus/last, cast, XP bars**: native `hud.bar` (palette `colour` or built-in kinds); no bar track/fill PNGs.
- **XP mog-house marker**: rounded `hud.rect` (Vana’diel moon % tints fill); not an FFXIV rested-XP asset.

## Before you open a PR / ship

- Edit `modules/<panel>/src/` or `entry.lua`; changes apply on `/lua reload xiv-ui` (no chunk regen).
- `/lua reload xiv-ui` with several `mod_*` panels enabled — no `no setting … in mod.toml` errors.
- Drag player / target; party cast strips with target on; buff click-cancel; XP attach to player bars when enabled.