# XIV-UI client runtime pass

**Branch:** `xiv-ui`  
**Date:** 2026-11-24 (America/New_York)  
**Reference:** [`xiv-ui-audit.md`](xiv-ui-audit.md) §4; client `settings.get` in `crates/vana-client/src/client/lua/api.rs` (undeclared key → runtime error `"no setting … in mod.toml"`).

**Verdict:** **PASS** — no HIGH issues; suite matches manifest/settings, permissions, HUD, and stepped-load constraints. MEDIUM/LOW items documented below (no code changes required this pass).

---

## Checklist summary

| # | Check | Result |
|---|--------|--------|
| 1 | `settings.get` vs manifest / `LAYOUT_KEYS` | **OK** |
| 2 | `permissions` in root `mod.toml` | **OK** |
| 3 | No `hud.clear()` | **OK** |
| 4 | `require('src.*')` after bootstrap | **OK** (by design) |
| 5 | `mods.provide` / `mods.call` | **OK** (see MEDIUM notes) |
| 6 | Stepped bootstrap | **OK** |
| 7 | M18 `--check` | **OK** (run 2026-11-24) |

---

## Findings

| Severity | File / area | Issue | Status |
|----------|-------------|--------|--------|
| — | `src/settings_proxy.lua` | Panel `settings` is proxy: `on` → `mod_*`; manifest keys → `prefix_key`; `LAYOUT_KEYS` (`offset_*`, `place_*`, `last_*`) return **nil** so undeclared layout keys never call global `settings.get` (per `api.rs`). | **OK** |
| — | `modules/*/entry.lua` | Panels rebind `local settings = cfg.settings` after `hud_config.new` (layout via bucket + schema defaults). | **OK** |
| — | `modules/notify/src/requests.lua` | `settings.get('request_offset_*')` via `hud_config.read` + proxy → `notify_request_offset_*` in `mod.toml`. | **OK** |
| — | `modules/buff/entry.lua` | Uses bootstrap-injected proxy as `panel_settings`; `bar.lua` reads `buff_*` manifest keys. | **OK** |
| — | `init.lua` | Global `settings.get` only for `on`, `mod_*` (all declared). | **OK** |
| — | `mod.toml` | `permissions = ["ui.native", "actions"]` — covers `ui.native.hide`, `actions.cancel` (buff), `actions.target`, `actions.open_menu` (notify), all wrapped in `pcall`. | **OK** |
| — | `modules/buff/src/bar.lua` | Only comment references `hud.clear()`; hide uses per-id `hud.set` / `visible = false`. | **OK** |
| — | `bootstrap.lua` + `entry.lua` | `require('src.*')` uses prefixed M18 `require` during import/entry; restored native `require` after panel load — no post-bootstrap bare `src.*` in suite `src/` or `init.lua`. | **OK** |
| — | `init.lua` + `bridge.lua` | `xiv_config` dispatcher; per-panel `xiv_ui_<panel>_config`; `wrap_provide` namespaces host provides; `bridge.registry` for in-suite calls. | **OK** |
| — | `init.lua` `frame` pump | One panel `bootstrap.step` per frame until queue drained; unchanged. | **OK** |
| **Medium** | `init.lua` `HOST_COMPAT` | Publishes bare `layout` from **target** and **player** on host — last loaded wins for external `mods.call('xiv-ui', 'layout')`. In-suite `bridge.call('xiv-player-bars','layout')` is correct path. | **OK / accept** (audit §4) |
| **Medium** | `modules/party/entry.lua` `cast_call` | Legacy `mods.call('xiv-target-bar', …)` then `mods.call('xiv-ui', …)`; `bridge.call` preferred when panels loaded. | **OK / accept** |
| **Medium** | `hdr_*` in `mod.toml` | UI section labels only; Lua never reads. | **OK / accept** (skipped per product) |
| **Low** | Notify toast `offset_x/y` | Proxy `LAYOUT_KEYS` nil → `or 0` in draw; drag values live in `xiv_ui_notify_v1` via hud_config when edited. | **OK** |
| **Low** | `mods.provide` timers | Each panel hud_config adds `timer.every(0.25, …)` session sweeper. | **OK / accept** |

---

## Provide / call map (suite host)

| Name | Owner | Notes |
|------|--------|------|
| `loaded`, `suite`, `xiv_config` | `init.lua` | `xiv_config(op, panel, …)` dispatches |
| `xiv_ui_<panel>_config` | `bootstrap` after entry | Per-panel config API |
| `xiv_<panel>_*` | `wrap_provide` during import | Namespaced legacy host names |
| `layout`, `cast`, `casts_for`, `effects` | target (compat) | Host compat for standalones |
| `layout` | player (compat) | Host collision with target `layout` — use panel-specific bridge |
| `busy`, `points`, `status`, … | panel `entry.lua` | Registered in `bridge.registry` |

---

## M18

```bash
python3 scripts/regen_all_m18.py --check
# → M18 chunks match modules/*/src
```

No `src/` Lua changes in this pass.

---

## User validation

After pulling `xiv-ui`:

1. `/lua reload xiv-ui`
2. Enable several panels (`mod_target`, `mod_player`, `mod_exp`, `mod_buff`, …).
3. Confirm no chat errors like `no setting "…" in mod.toml`.
4. Drag player/XP; toggle attach; exercise buff click-cancel and notify toasts if enabled.