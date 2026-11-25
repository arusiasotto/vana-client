#!/usr/bin/env python3
"""Append prefixed settings/commands from ported panel mod.toml files into xiv-ui/mod.toml.

After merging, run regroup_mod_toml.py so the Settings tab stays grouped by panel.
"""
from __future__ import annotations

import re
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[2]
UI_TOML = ASSETS / "xiv-ui" / "mod.toml"

SKIP_KEYS = {
    "mod_target",
    "mod_focus",
    "mod_party",
    "mod_player",
    "mod_cast",
    "mod_buff",
    "mod_exp",
    "mod_notify",
}
SKIP_PREFIXES = ("target_", "focus_")


def transform_block(header: str, body: str, prefix: str) -> str:
    if header.startswith("[commands.") or header.startswith("[commands.["):
        return header + "\n" + body
    m = re.match(r"\[settings\.([^\]]+)\]", header)
    if not m:
        return header + "\n" + body
    key = m.group(1)
    if key == "on" or key in SKIP_KEYS or any(key.startswith(p) for p in SKIP_PREFIXES):
        return ""
    new_header = f"[settings.{prefix}_{key}]"
    return new_header + "\n" + body


def parse_sections(text: str) -> list[tuple[str, str]]:
    parts = re.split(r"(?=^\[)", text, flags=re.MULTILINE)
    sections = []
    for part in parts:
        part = part.strip()
        if not part:
            continue
        lines = part.split("\n", 1)
        header = lines[0].strip()
        body = lines[1] if len(lines) > 1 else ""
        if body and not body.endswith("\n"):
            body += "\n"
        sections.append((header, body))
    return sections


def merge_one(out: list[str], mod_dir: str, prefix: str) -> None:
    path = ASSETS / mod_dir / "mod.toml"
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    text = path.read_text(encoding="utf-8")
    out.append(f"# --- {mod_dir} (suite prefix {prefix}_) ---\n")
    for header, body in parse_sections(text):
        if not (header.startswith("[settings.") or header.startswith("[commands.")):
            continue
        block = transform_block(header, body, prefix)
        if block.strip():
            out.append(block + "\n")


def main(argv: list[str] | None = None) -> None:
    import argparse

    p = argparse.ArgumentParser(
        description="Append settings/commands from assets/mods/<folder>/mod.toml into suite mod.toml."
    )
    p.add_argument(
        "pair",
        nargs="+",
        metavar="FOLDER:PREFIX",
        help="e.g. my-cast-panel:cast (folder under assets/mods, suite settings prefix)",
    )
    args = p.parse_args(argv)
    base = UI_TOML.read_text(encoding="utf-8")
    if "# --- Cast" in base:
        base = base.split("# --- Cast")[0].rstrip() + "\n\n"
    else:
        base = base.rstrip() + "\n\n"
    out = [base]
    for item in args.pair:
        if ":" not in item:
            raise SystemExit(f"expected FOLDER:PREFIX, got {item!r}")
        mod_dir, prefix = item.split(":", 1)
        if not mod_dir or not prefix:
            raise SystemExit(f"expected FOLDER:PREFIX, got {item!r}")
        merge_one(out, mod_dir, prefix)
    UI_TOML.write_text("".join(out), encoding="utf-8")
    print("updated", UI_TOML, "(run scripts/regroup_mod_toml.py to restore panel grouping)")


if __name__ == "__main__":
    main()