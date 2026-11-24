# XIV-UI suite audit (`xiv-ui` branch)

**Scope:** `crates/vana-client/assets/mods/xiv-ui/` (suite root, `src/`, `modules/*`, `scripts/`).  
**Date:** 2026-11-23 (America/New_York).  
**Method:** Static review vs client mod patterns (e.g. `hotbar/`: single `init.lua`, manifest settings only, no M18 bootstrap).

---

## Executive summary

Phase 2 integration is **functionally coherent**: one VM, staggered bootstrap, internal `bridge`, layout in `storage.account.xiv_ui_*_v1`, buff uses live disk sources. **HIGH pass (8e92e886):** `xiv_config` registry/dispatcher, M18 tooling, `settings_proxy` docs. **MEDIUM pass (49433096):** shared `src/hud_drag.lua` + `src/hud_config_factory.lua`, thin per-panel `hud_config.lua`, orphan module manifests removed, `mod.toml` reload UX, full M18 regen + `--check` green. Remaining duplicate **logic** is mostly per-panel `xiv.lua` / `config_schema` / large data maps.

**Recommended Phase 3 priorities:** (1) catalogue + deprecate standalone `xiv-*` assets, (2) dedupe suite `mod.toml` section comments, (3) optional shared `xiv.lua` helpers.

---

## 1. Duplicate code

| Severity | Item | Paths / notes | Next action |
|----------|------|----------------|-------------|
| **High** | **`hud_config.lua` clones** (same transaction editor; differs only by `storage.account.xiv_ui_<panel>_v1` bucket name) | `modules/{cast,player,party,exp,notify,target,focus}/src/hud_config.lua`; was duplicated in `_m18_*` chunks | **Fixed (49433096):** `src/hud_config_factory.lua` + thin panel shims; bootstrap injects factory |
| **High** | **`hud_drag.lua` identical** (same MD5 across five modules) | was `modules/{cast,player,party,exp,focus}/src/hud_drag.lua` | **Fixed (49433096):** `src/hud_drag.lua`; bootstrap inject + M18 embed |
| **Medium** | **`xiv.lua` renderer/natives** — near-duplicates with panel-specific tail | `modules/*/src/xiv.lua` (215–408 lines); embedded in `_m18_01.lua` for chunk loaders | **Accept** for now; merge shared `X.renderer`, `X.native`, `X.call` only if churn stays high |
| **Medium** | **`config_schema.lua`** — same shape per panel | Seven `modules/*/src/config_schema.lua`; labels still mention offsets removed from suite `mod.toml` | **Fix** low priority: trim schema help/labels; keep schema as layout authority |
| **Medium** | **Status art maps** | `status_png.lua` in `buff`, `target`, `party` (large generated tables) | **Accept** (data, not logic); share only if asset layout unifies |
| **Medium** | **`tooltip.lua` / `target_palette.lua`** copied between target/focus/player | `modules/target`, `focus`, `player` | **Accept** unless palette becomes suite-wide |
| **Low** | **Bridge + per-module `X.call`** — bridge aliases `xiv-*` ids; each `xiv.lua` still embeds `mods.call` fallback | `src/bridge.lua`, all `src/xiv.lua` | **Accept** (needed for standalones + suite) |
| **Low** | **Entry bootstrap pattern** repeated | Each `entry.lua`: `hud_config.new(settings, schema, hooks)`, `mods.provide('busy')`, frame/timer draw | **Accept**; document as panel template |

---

## 2. Unused / stale code

| Severity | Item | Paths / notes | Next action |
|----------|------|----------------|-------------|
| **High** | **M18 chunks vs on-disk `src/`** — runtime loads **embedded chunk sources**, not `src/*.lua`, for all panels except buff (`source_files = true`). `entry.lua` is always read from disk. | All `modules/*/manifest.lua` with `chunks = { "_m18_*" }` | **Mitigated (49433096):** full regen + `--check` green; `regen_all_m18.py` resolves suite shared `src.hud_drag` from root `src/` |
| **Medium** | **Orphan standalone `mod.toml`** in suite tree (not used by suite manifest) | `modules/focus/mod.toml`, `modules/target/mod.toml` | **Fixed (49433096):** deleted; `scripts/README.md` notes root `mod.toml` is sole manifest |
| **Medium** | **`hdr_*` settings** (8× single-option enums) — UI section hacks; Lua never reads them | `mod.toml` `[settings.hdr_*]` | **Fix** or **accept:** remove when client supports sections or keep as UX affordance |
| **Medium** | **Duplicate section comments** in `mod.toml` (regroup artifacts) | e.g. duplicate `# --- Focus ---`, `# --- Notify ---`, mixed `——` vs `---` | **Fix:** run `scripts/regroup_mod_toml.py` after cleaning regroup script to emit one header each |
| **Low** | **`scripts/merge_mod_toml.py`** — can truncate suite `mod.toml` on re-run (`# --- Cast` split) | `scripts/merge_mod_toml.py` | **Accept** with warning in script; do not run in CI without regroup |
| **Low** | **Layout keys still in `config_schema`** but removed from suite `mod.toml` | All schemas still define `offset_x`/`offset_y`/`place_*`/`last_*` | **Accept** — intentional; values live in storage buckets |
| **Low** | **`//xui` mentioned, not registered** | `modules/exp/entry.lua` (attach drag guard); `modules/cast/entry.lua` grip tip | **Fix:** point help text at real commands or add suite `//xui status` later |

No **dead Lua entry files** found; every queued panel has `entry.lua` + `manifest.lua`. `init.lua` at suite root is the only loader (no parallel `modules/*/init.lua`).

---

## 3. Lengthy / noisy comments

| Severity | Item | Paths / notes | Next action |
|----------|------|----------------|-------------|
| **Medium** | **Party load probe / runtime commentary** — long inline docs mixed with probe counters | `modules/party/entry.lua` (~1014 lines; large header comment block ~lines 1–80) | **Accept** for debugging; trim when party stabilizes |
| **Medium** | **Buff `bar.lua` file header + incident comments** | `modules/buff/src/bar.lua` (~46 comment lines; `hud.clear` warning, drag/offset narrative) | **Accept** — operational warnings worth keeping |
| **Low** | **`hud_config.lua` boilerplate** one-liners repeated 7× | Was each panel `src/hud_config.lua` | **Fixed (49433096):** 8-line shims per panel |
| **Low** | **Target status/icon geometry** in `target/entry.lua` | Lines ~19–28 | **Accept** — documents non-obvious layout |
| **Low** | **M18 chunk files** — huge string literals (not human-maintained prose) | `modules/target/_m18_*.lua` (13 chunks) | **Accept** as build artifact; prefer regen over hand-edit |

No large **commented-out code blocks** flagged in suite `entry.lua` files; standalone `_m18_*` may contain stale embedded copies (see §2).

---

## 4. Client conflicts & API assumptions

| Severity | Item | Paths / notes | Next action |
|----------|------|----------------|-------------|
| **High** | **`mods.provide('xiv_config')` overwrites** — each panel’s `hud_config.new()` registers the **same global name** in one VM. Load order ends at **notify** (last in queue); earlier panels’ config API is lost for external `mods.call`. | All `*/src/hud_config.lua` + `_m18_00` chunks | **Fixed in `xiv-ui` (2026-11):** `bridge.wrap_provide` registers `xiv_config` per panel in `bridge.config`; suite `mods.provide('xiv_config', op, panel, …)` dispatches; each loaded panel also exposes `xiv_ui_<panel>_config` after bootstrap entry. |
| **High** | **`settings.get` manifest enforcement** — undeclared keys error (`no setting in mod.toml`). Mitigated by `LAYOUT_KEYS` nil-return in proxy | `src/settings_proxy.lua`; layout keys in hud_config `native_value` | **Fixed in `xiv-ui` (2026-11):** expanded comment block in `settings_proxy.lua` documenting client rule + `LAYOUT_KEYS` bypass; notify offset keys remain declared in suite `mod.toml`. |
| **Medium** | **`settings.get('on')` in panels** via hud_config — panel visibility uses **`mod_*`** toggles through proxy, not per-bucket `on` | `settings_proxy.lua`, `hud_config` strips `on` on commit, `migrate.lua` | **Accept** — by design; **UX (49433096):** `mod.toml` `mod_*` + master `on` help states `/lua reload xiv-ui` when enabling a panel that was off at load |
| **Medium** | **Cross-panel `X.call` / `mods.call`** with legacy mod ids | `player/entry.lua` → `X.call('xiv-cast-bar','layout')`; `party/entry.lua` → `xiv-target-bar` then `xiv-ui` | **Accept** — `bridge.call` resolves when target/cast loaded; **fix** party helper to use `bridge.registry` only |
| **Medium** | **Staggered load + frame pump** — up to 8 panels × (chunks + imports + entry); target alone 13 chunks + 35 status_map imports | `init.lua`, `bootstrap.lua`, `modules/target/manifest.lua` | **Accept** with profiling; watch suspend budget on slow disks |
| **Medium** | **`timer.every` stacking** — each hud_config adds 0.25s session sweeper; cast `0.05s` tick; party `0.5s` pets; buff `0.5s` | Multiple `entry.lua` + hud_config | **Accept**; revisit if timer budget tight |
| **Low** | **`hud.clear()`** — buff explicitly avoids; no other suite usage | `modules/buff/src/bar.lua` | **Verified 2026-11:** grep across `xiv-ui` shows no active `hud.clear()` calls (comment only). |
| **Low** | **`require` / `settings` global restore** on bootstrap errors | `bootstrap.lua`, `init.lua` frame hook | **Accept** — matches client expectations |
| **Low** | **Permissions** — suite `mod.toml`: `ui.native`, `actions` only | Root `mod.toml` | **Accept** — matches `ui.native.hide` + `actions.cancel` (buff) |
| **Low** | **Commands** — all panel commands in suite `mod.toml`; buff `resetpos` in code | `mod.toml` `[commands.*]` | **Accept**; keep command list synced when adding subcommands |

### Settings inventory (suite `mod.toml`)

- **Declared:** `on`, 8× `mod_*`, 8× `hdr_*`, prefixed panel settings, notify offsets (4).  
- **Not in manifest (by design):** layout keys via hud_config + `LAYOUT_KEYS` proxy bypass.  
- **Risk:** any **new** `settings.get("suite_prefix_key")` from **global** `settings` (not hud_config/proxy) must add `[settings.*]` row.

---

## 5. Scripts / repo hygiene

| Script | Purpose | Risk |
|--------|---------|------|
| `scripts/integrate_module.py` | Copy standalone → `modules/<alias>` | **Low** — dev tool; strips `init.lua`/`mod.toml` |
| `scripts/merge_mod_toml.py` | Append standalone settings | **Medium** — destructive trim if re-run |
| `scripts/regroup_mod_toml.py` | Panel-group manifest | **Low** — requires full manifest header |

**Fixed in `xiv-ui` (2026-11):** `scripts/regen_all_m18.py` + `scripts/README.md` (authoritative runtime table, regen + `--check` drift).

---

## 6. Comparison to other bundled mods

| Pattern | `hotbar/` (reference) | `xiv-ui/` |
|---------|------------------------|-----------|
| Entry | Single `init.lua` | Suite `init.lua` + per-panel `entry.lua` |
| Settings | All in `mod.toml` | Suite `mod.toml` + hud_config schema + storage buckets |
| Load budget | One require tree | M18 chunks + stepped `frame` pump |
| Mod interop | `mods.provide` namespaced | Bridge + legacy `xiv-*` ids; suite **`xiv_config` dispatcher + `xiv_ui_*_config`** |

---

## 7. Trivial fixes (not applied in this pass)

| Item | Action |
|------|--------|
| Delete `modules/focus/mod.toml`, `modules/target/mod.toml` | Safe if no tool reads them (**low**; confirm with user) |
| Dedupe duplicate `# --- … ---` lines in `mod.toml` | Safe cosmetic (**low**) |
| Cast/exp help: replace `//xui` with `//xcb` / attach wording | Copy-only (**low**) |

---

## 8. Recommended next actions (priority)

1. ~~**High — M18 sync:**~~ **Done:** `scripts/regen_all_m18.py` + `scripts/README.md`; run after `src/` edits (or migrate panels to `source_files`).  
2. ~~**High — Document** load order~~ **Done:** `scripts/README.md`.  
3. ~~**Medium — `xiv_config`:**~~ **Done:** bridge registry + per-panel host provides (see §4).  
4. **Medium — Phase 3 ship:** Catalogue entry, deprecate standalone `xiv-*` folders in assets, PR from `xiv-ui` branch.  
5. **Low — Dedupe** `mod.toml` comments; remove orphan module `mod.toml`; trim `hdr_*` when UX allows.  
6. **Low — Refactor** (user-driven): shared `hud_config` / `hud_drag` / base `xiv.lua`.

---

*Audit only — no code deleted, no PR opened.*