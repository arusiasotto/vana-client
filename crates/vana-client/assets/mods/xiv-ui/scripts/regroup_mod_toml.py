#!/usr/bin/env python3
"""Reorder xiv-ui/mod.toml settings by panel (mod_* + prefixed keys, labels grouped by panel)."""
from __future__ import annotations

import re
from pathlib import Path

UI_TOML = Path(__file__).resolve().parents[1] / "mod.toml"

MODULES = [
    ("target", "Target", "HP, weaknesses, cast strip. Toggle + reload to load; //xtb for temp hide."),
    ("focus", "Focus", "Requires panel on and /lua reload. Last target needs switching away from current target."),
    ("cast", "Cast Bar", "Player cast / swing / ranged gauges."),
    ("player", "Player Bar", "HP / MP / TP near hotbars."),
    ("buff", "Buffs", "Replaces native status icons when on."),
    ("exp", "XP Bar", "Top-of-screen points strip."),
    ("party", "Party", "Loads last in queue; keep target on for casts/status."),
    ("notify", "Notify", "Toasts and invite reminders."),
]

SKIP_KEYS = {
    "notify_offset_x",
    "notify_offset_y",
}

CMD_ORDER = ["xtb", "xft", "xcb", "xpb", "xbb", "xxp", "xpl", "xn"]

GROUP_START = re.compile(
    r"^(?:# Panel toggles and settings|# --- [^#])",
    re.MULTILINE,
)

LABEL_LINE = re.compile(r'^label\s*=\s*"(.*)"\s*$', re.MULTILINE)


def extract_manifest_header(text: str) -> str:
    """Keep name, version, permissions, [settings.on], and comments before grouped settings."""
    m = GROUP_START.search(text)
    if m:
        return text[: m.start()].rstrip() + "\n\n"
    m = re.search(r"^\[settings\.(?!on\])", text, re.MULTILINE)
    if m:
        return text[: m.start()].rstrip() + "\n\n"
    return ""


SECTION_COMMENT = re.compile(r"^# (?:---|——) .+ (?:---|——)\s*$")


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
            if key.startswith("hdr_") or key in SKIP_KEYS:
                continue
            sections[key] = body
    return sections, commands


def label_without_panel_prefix(label: str) -> str:
    if ": " in label:
        return label.split(": ", 1)[1]
    return label


def dedupe_suffix(panel_title: str, suffix: str) -> str:
    """Drop words from the suffix that repeat the panel name (e.g. Party: Party Scale → Scale)."""
    s = suffix.strip()
    low_pt = panel_title.lower()
    low_s = s.lower()
    if low_s.startswith(low_pt + " "):
        s = s[len(panel_title) + 1 :]
    elif low_s.startswith(low_pt) and len(s) > len(panel_title):
        s = s[len(panel_title) :].lstrip(" :")
    # Trailing word of panel title repeated at start of suffix ("Player Bar" + "Bar Scale").
    parts = panel_title.split()
    if parts:
        tail = parts[-1].lower()
        if s.lower().startswith(tail + " "):
            s = s[len(parts[-1]) + 1 :]
    # Notify panel vs "Notification …"
    if panel_title == "Notify" and s.lower().startswith("notification "):
        s = s[13:]
    # XP Bar panel vs "XP …" in suffix
    if panel_title == "XP Bar" and s.upper().startswith("XP "):
        s = s[3:]
    # Mid-label panel name (only when the whole setting is under that panel)
    if panel_title == "Party":
        s = re.sub(r"\bparty\b", "", s, flags=re.I)
        s = re.sub(r"\s{2,}", " ", s).strip()
    s = s.strip()
    return s or suffix


def relabel_body(body: str, panel_title: str) -> str:
    m = LABEL_LINE.search(body)
    if not m:
        return body
    base = dedupe_suffix(panel_title, label_without_panel_prefix(m.group(1)))
    new = f"{panel_title}: {base}"
    return body[: m.start(1)] + new + body[m.end(1) :]


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
        "# Panel toggles and settings are grouped by panel; each label is prefixed with the panel name.\n\n"
    )

    for alias, title, _panel_help in MODULES:
        out.append(f"# --- {title} ---\n")
        mod_key = f"mod_{alias}"
        if mod_key in sections:
            body = relabel_body(sections[mod_key], title)
            out.append(f"[settings.{mod_key}]\n" + body)
        prefix = alias + "_"
        keys = sorted(k for k in sections if k.startswith(prefix))
        for k in keys:
            body = relabel_body(sections[k], title)
            out.append(f"[settings.{k}]\n" + body)

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

    UI_TOML.write_text("".join(out), encoding="utf-8")
    print("regrouped", UI_TOML)


if __name__ == "__main__":
    main()