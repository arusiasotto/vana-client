# XIV-UI maintenance scripts

## Authoritative runtime sources

| Panel | Loaded from |
|-------|-------------|
| Most panels (`target`, `focus`, `cast`, …) | `modules/<panel>/_m18_*.lua` chunks referenced in `manifest.lua` |
| `buff` | Live `modules/buff/src/*.lua` (`manifest.lua` sets `source_files = true`) |
| Suite bootstrap | Root `init.lua`, `src/*.lua` |
| Panel lifecycle | `modules/<panel>/entry.lua` (always read from disk) |

**Rule:** Edits to `modules/<panel>/src/*.lua` do not affect in-game behavior until chunks are regenerated (except `buff`).

## Regenerate M18 chunks

From `crates/vana-client/assets/mods/xiv-ui/`:

```bash
python3 scripts/regen_all_m18.py
```

Drift check (embedded chunk bodies vs `src/`, non-zero exit on mismatch):

```bash
python3 scripts/regen_all_m18.py --check
```

Chunk grouping (which `src.*` keys live in which `_m18_*` file) is preserved from the existing chunk files; the script only re-embeds current `src/` text.

## Other scripts

| Script | Use |
|--------|-----|
| `integrate_module.py` | Copy a standalone `xiv-*` mod into `modules/<alias>` (dev integration). |
| `merge_mod_toml.py` | Append standalone settings into suite `mod.toml`. |
| `regroup_mod_toml.py` | Re-group suite `mod.toml` by panel after a merge. |

After `integrate_module.py`, run `regen_all_m18.py` for non–`source_files` panels and regroup `mod.toml` if settings changed.