#!/usr/bin/env python3
"""Append prefixed settings/commands from standalone xiv mod.toml files into xiv-ui/mod.toml."""
from __future__ import annotations

import re
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[2]
UI_TOML = ASSETS / "xiv-ui" / "mod.toml"

PREFIXES = [
    ("xiv-cast-bar", "cast"),
    ("xiv-player-bars", "player"),
    ("xiv-buff-bar", "buff"),
    ("xiv-exp-bar", "exp"),
    ("xiv-party-list", "party"),
    ("xiv-notify", "notify"),
]

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


def main() -> None:
    base = UI_TOML.read_text(encoding="utf-8")
    # Trim at first phase-2 placeholder section comment if re-run
    if "# --- Cast" in base:
        base = base.split("# --- Cast")[0].rstrip() + "\n\n"
    else:
        base = base.rstrip() + "\n\n"
    out = [base]
    for mod_dir, prefix in PREFIXES:
        path = ASSETS / mod_dir / "mod.toml"
        text = path.read_text(encoding="utf-8")
        out.append(f"# --- {mod_dir} (suite prefix {prefix}_) ---\n")
        for header, body in parse_sections(text):
            if not (header.startswith("[settings.") or header.startswith("[commands.")):
                continue
            block = transform_block(header, body, prefix)
            if block.strip():
                out.append(block + "\n")
    UI_TOML.write_text("".join(out), encoding="utf-8")
    print("updated", UI_TOML)


if __name__ == "__main__":
    main()