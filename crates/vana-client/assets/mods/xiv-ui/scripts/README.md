# XIV-UI maintenance scripts

All commands run from `crates/vana-client/assets/mods/xiv-ui/` unless noted.

The suite **`mod.toml` at the xiv-ui root** is the only settings manifest panels use (via `settings_proxy`). Per-panel `modules/*/mod.toml` files are **not** loaded — delete any left over after integration.

**Loader shape:** only root `init.lua` runs at mod load. Panels use `modules/<panel>/entry.lua` + `manifest.lua`. There is no `modules/*/init.lua` in the suite tree.

Shared Lua for all panels: `src/xiv_renderer.lua` (`src.xiv`), `src/hud_drag.lua`, `src/hud_config_factory.lua` (injected at bootstrap).

---

## Which script when?

| Goal | Script | When to run |
|------|--------|-------------|
| Import a panel tree from `assets/mods/<folder>` into `modules/<alias>` | `integrate_module.py` | Rare dev port only; those folders are not shipped in this repo |
| **Append** panel `[settings.*]` / `[commands.*]` into suite `mod.toml` | `merge_mod_toml.py` | After a ported `mod.toml` gained new keys you need in the suite manifest |
| **Reorder** settings by panel (`mod_*`, prefixed keys, panel labels) | `regroup_mod_toml.py` | After `merge_mod_toml.py`, or when cleaning duplicate section comment lines in bodies |
| *(legacy)* **Verify** no stale `_m18_*.lua` chunks remain | `regen_all_m18.py --check` | Optional; suite uses `source_files` only |
| **Consolidate** panel PNGs into suite `img/` | `dedup_img.py` | One file per image + `img/_aliases.lua`; run `--check` in CI |

Typical flow after importing a panel from an external folder (you supply the folder name on your machine):

1. `integrate_module.py <folder> <alias>` (or manual merge of `entry.lua` / `src/`)
2. `merge_mod_toml.py folder:prefix` only if the ported tree had new manifest keys/commands
3. `regroup_mod_toml.py` — restores panel grouping and manifest header

Day-to-day panel **logic** fixes: edit `modules/<panel>/src/` and/or `entry.lua` → reload the mod.

---

## Warnings (manifest / permissions)

- **`merge_mod_toml.py` is destructive on re-run:** it truncates `mod.toml` at the first `# --- Cast` marker before appending. Always run **`regroup_mod_toml.py`** afterward. Do not run merge in CI blindly.
- **`regroup_mod_toml.py`** rebuilds the grouped settings region from parsed sections. It **requires** the file to keep the top manifest block (`name`, `version`, **`permissions`**, `[settings.on]`). If `permissions` is missing, the script exits with an error — restore header from git before regrouping.
- **`integrate_module.py`** overwrites `modules/<alias>/` (except it does not copy the source tree's `init.lua` / `mod.toml`). Set `source_files = true` in `manifest.lua` and drop any `_m18_*.lua` chunks.

---

## Authoritative runtime sources

| Panel | Loaded from |
|-------|-------------|
| All panels | `modules/<panel>/src/*.lua` per `manifest.lua` `imports` |
| Suite bootstrap | Root `init.lua`, `src/*.lua` |
| Panel lifecycle | `modules/<panel>/entry.lua` (always read from disk) |

---

## `integrate_module.py`

Imports a panel folder under `assets/mods/<name>` into `modules/<alias>/` (folder names are dev labels only; nothing is shipped separately):

- Extracts M18 chunk list and imports from the source `init.lua` (or uses `source_files` for buff-style panels).
- Writes `entry.lua` from that init body.
- Writes `manifest.lua`.
- Rewrites legacy shared storage keys in Lua to `xiv_ui_<alias>_v1` when porting old sources.

Does **not** update suite `mod.toml`. Use merge + regroup if settings changed.

```bash
python3 scripts/integrate_module.py my-panel-folder cast
python3 scripts/integrate_module.py my-buff-folder buff --source-files --import src.bar
python3 scripts/merge_mod_toml.py my-panel-folder:cast
```

---

## `merge_mod_toml.py`

Appends prefixed settings/commands from selected ported `mod.toml` files into suite `mod.toml`. Skips suite-only keys (`mod_*`, target/focus prefixes already owned by suite).

**Always follow with:** `python3 scripts/regroup_mod_toml.py`

---

## `regroup_mod_toml.py`

Rebuilds the Settings tab order: one `# --- <panel> ---` comment per panel, `mod_*` toggle, then `alias_*` settings with labels prefixed by the panel name. Drops `hdr_*` and dead keys. Commands tab block at the end.

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