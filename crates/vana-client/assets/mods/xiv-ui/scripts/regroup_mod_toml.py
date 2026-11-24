#!/usr/bin/env python3
"""Reorder xiv-ui/mod.toml settings by panel (hdr_* section labels + mod_* + prefixed keys)."""
from __future__ import annotations

import re
from pathlib import Path

UI_TOML = Path(__file__).resolve().parents[1] / "mod.toml"

MODULES = [
    ("target", "Target bar", "HP, weaknesses, cast strip. Toggle + reload to load; //xtb for temp hide."),
    ("focus", "Focus and last target", "Requires panel on and /lua reload. Last target needs switching away from current target."),
    ("cast", "Cast bar", "Player cast / swing / ranged gauges."),
    ("player", "Player bars", "HP / MP / TP near hotbars."),
    ("buff", "Buff bar", "Replaces native status icons when on."),
    ("exp", "XP / limit strip", "Top-of-screen points strip."),
    ("party", "Party list", "Loads last in queue; keep target on for casts/status."),
    ("notify", "Notify", "Toasts and invite reminders."),
]

CMD_ORDER = ["xtb", "xft", "xcb", "xpb", "xbb", "xxp", "xpl", "xn"]

GROUP_START = re.compile(
    r"^(?:# Panel toggles and settings are grouped|# --- [^#]|\[settings\.hdr_)",
    re.MULTILINE,
)


def extract_manifest_header(text: str) -> str:
    """Keep name, version, permissions, [settings.on], and comments before grouped settings."""
    m = GROUP_START.search(text)
    if m:
        return text[: m.start()].rstrip() + "\n\n"
    m = re.search(r"^\[settings\.(?!on\])", text, re.MULTILINE)
    if m:
        return text[: m.start()].rstrip() + "\n\n"
    return ""


SECTION_COMMENT = re.compile(r"^# --- .+ ---\s*$")


def clean_section_body(body: str) -> str:
    lines = [ln for ln in body.splitlines() if not SECTION_COMMENT.match(ln)]
    if not lines:
        return ""
    return "\n".join(lines).rstrip() + "\n"


def parse_sections(text: str):
    parts = re.split(r"(?=^\[)", text, flags=re.MULTILINE)
    sections: dict[str, str] = {}
    commands: list[str] = []
    for part in parts:
        part = part.strip()
        if not part:
            continue
        lines = part.split("\n", 1)
        header = lines[0].strip()
        body = clean_section_body(lines[1] if len(lines) > 1 else "")
        if header.startswith("[commands."):
            commands.append(part + "\n")
        elif header.startswith("[settings."):
            key = header[len("[settings.") : -1]
            sections[key] = body
    return sections, commands


def hdr(alias: str, title: str, help: str) -> str:
    return f"""[settings.hdr_{alias}]
type = "enum"
default = "—"
options = ["—"]
label = "{title}"
help = "{help}"

"""


def main() -> None:
    text = UI_TOML.read_text(encoding="utf-8")
    manifest = extract_manifest_header(text)
    if not manifest.strip() or "permissions" not in manifest:
        raise SystemExit(
            f"{UI_TOML}: missing mod header (name/version/permissions). Restore before regrouping."
        )
    sections, commands = parse_sections(text)

    out: list[str] = [manifest]

    out.append(
        "# Panel toggles and settings are grouped by panel. hdr_* rows are section labels only (not read by Lua).\n\n"
    )

    for alias, title, help in MODULES:
        out.append(f"# --- {title} ---\n")
        out.append(hdr(alias, title, help))
        mod_key = f"mod_{alias}"
        if mod_key in sections:
            out.append(f"[settings.{mod_key}]\n" + sections[mod_key])
        prefix = alias + "_"
        for k in sorted(k for k in sections if k.startswith(prefix)):
            out.append(f"[settings.{k}]\n" + sections[k])

    out.append("\n# --- Commands (separate tab in Mods window) ---\n\n")
    cmd_blocks = {
        re.match(r"\[commands\.(\w+)\]", c).group(1): c
        for c in commands
        if re.match(r"\[commands\.", c)
    }
    for name in CMD_ORDER:
        if name in cmd_blocks:
            out.append(cmd_blocks[name] + "\n")
    for name, block in sorted(cmd_blocks.items()):
        if name not in CMD_ORDER:
            out.append(block + "\n")

    # Preserve hdr_* bodies if user customized labels; we regenerate headers each run.
    UI_TOML.write_text("".join(out), encoding="utf-8")
    print("regrouped", UI_TOML)


if __name__ == "__main__":
    main()