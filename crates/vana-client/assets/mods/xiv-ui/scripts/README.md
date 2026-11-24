# XIV-UI maintenance scripts

All commands run from `crates/vana-client/assets/mods/xiv-ui/` unless noted.

The suite **`mod.toml` at the xiv-ui root** is the only settings manifest panels use (via `settings_proxy`). Per-panel `modules/*/mod.toml` files are **not** loaded — delete any left over after integration.

**Loader shape:** only root `init.lua` runs at mod load. Panels use `modules/<panel>/entry.lua` + `manifest.lua`. There is no `modules/*/init.lua` in the suite tree.

Shared Lua for all panels: `src/hud_drag.lua`, `src/hud_config_factory.lua` (injected at bootstrap; `src.hud_drag` is also embedded in M18 chunks where listed).

---

## Which script when?

| Goal | Script | When to run |
|------|--------|-------------|
| Pull in a **new or updated standalone** `xiv-*` mod as a suite panel | `integrate_module.py` | Rare: upstream panel changed outside git; or first-time port of a panel |
| **Append** standalone `[settings.*]` / `[commands.*]` into suite `mod.toml` | `merge_mod_toml.py` | After standalone `mod.toml` gained new keys you need in the suite manifest |
| **Reorder** settings by panel (`hdr_*`, `mod_*`, grouped keys) | `regroup_mod_toml.py` | After `merge_mod_toml.py`, or when cleaning duplicate section comment lines in bodies |
| **Sync** M18 `_m18_*.lua` with `modules/*/src/` (and shared suite `src/`) | `regen_all_m18.py` | After **any** edit to panel `src/*.lua` that chunk-based panels load (not buff `source_files`) |

Typical maintenance flow after editing a standalone mod upstream:

1. `integrate_module.py` (or manual merge of `entry.lua` / `src/`)
2. `merge_mod_toml.py` only if new manifest keys/commands appeared in standalone `mod.toml`
3. `regroup_mod_toml.py` — restores panel grouping and manifest header
4. `regen_all_m18.py` then `regen_all_m18.py --check`

Day-to-day panel **logic** fixes in an existing suite panel: edit `modules/<panel>/src/` and/or `entry.lua` → **`regen_all_m18.py`** (skip merge/integrate unless you changed standalone assets).

---

## Warnings (manifest / permissions)

- **`merge_mod_toml.py` is destructive on re-run:** it truncates `mod.toml` at the first `# --- Cast` marker before appending. Always run **`regroup_mod_toml.py`** afterward. Do not run merge in CI blindly.
- **`regroup_mod_toml.py`** rebuilds the grouped settings region from parsed sections. It **requires** the file to keep the top manifest block (`name`, `version`, **`permissions`**, `[settings.on]`). If `permissions` is missing, the script exits with an error — restore header from git before regrouping.
- **`integrate_module.py`** overwrites `modules/<alias>/` (except it does not copy standalone `init.lua` / `mod.toml`). Review diff and run regen + regroup as needed.

---

## Authoritative runtime sources

| Panel | Loaded from |
|-------|-------------|
| Most panels (`target`, `focus`, `cast`, …) | `modules/<panel>/_m18_*.lua` chunks referenced in `manifest.lua` |
| `buff` | Live `modules/buff/src/*.lua` (`manifest.lua` sets `source_files = true`) |
| Suite bootstrap | Root `init.lua`, `src/*.lua` |
| Panel lifecycle | `modules/<panel>/entry.lua` (always read from disk) |

**Rule:** Edits to `modules/<panel>/src/*.lua` do not affect in-game until chunks are regenerated (except `buff`).

---

## `integrate_module.py`

Copies a standalone asset folder (e.g. `assets/mods/xiv-cast-bar`) into `modules/<alias>/`:

- Extracts M18 chunk list and imports from standalone `init.lua` (or uses `source_files` for buff-style panels).
- Writes `entry.lua` from the standalone init body.
- Writes `manifest.lua`.
- Rewrites storage keys from `xiv_ui_v1` to `xiv_ui_<alias>_v1`.

Does **not** update suite `mod.toml`. Use merge + regroup if settings changed.

```bash
# Default bundle set (see script main); or import and call integrate() from Python
python3 scripts/integrate_module.py
```

---

## `merge_mod_toml.py`

Appends prefixed settings/commands from selected standalone `mod.toml` files into suite `mod.toml`. Skips suite-only keys (`mod_*`, target/focus prefixes already owned by suite).

**Always follow with:** `python3 scripts/regroup_mod_toml.py`

---

## `regroup_mod_toml.py`

Rebuilds the Settings tab order: one `# --- <panel> ---` header per panel, `hdr_*` section row, `mod_*` toggle, then `alias_*` settings. Commands tab block at the end.

Strips stray `# --- … ---` lines that were accidentally merged into setting bodies.

---

## `regen_all_m18.py`

Regenerates chunk files from disk sources. Preserves which `src.*` keys live in which `_m18_*` file. Suite-only modules resolve from root `src/`:

- `src.hud_drag` → `src/hud_drag.lua`
- `src.hud_config_factory` → `src/hud_config_factory.lua`

```bash
python3 scripts/regen_all_m18.py
python3 scripts/regen_all_m18.py --check   # CI: exit 1 on drift
```

`entry.lua` is **not** embedded in chunks; no regen needed for entry-only edits.