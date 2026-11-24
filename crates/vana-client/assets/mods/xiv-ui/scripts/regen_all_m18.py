#!/usr/bin/env python3
"""Regenerate M18 chunk files under modules/*/ from modules/*/src (authoritative sources).

Runtime: bootstrap loads manifest.chunks (embedded string literals), not disk src/, unless
manifest sets source_files = true (buff). After editing modules/<panel>/src/*.lua for a
chunk-based panel, run:

    python3 scripts/regen_all_m18.py

Dry-run / CI-style drift check (exits 1 if any embedded body differs from src):

    python3 scripts/regen_all_m18.py --check
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

UI = Path(__file__).resolve().parents[1]
HEADER = "-- M18 bundled sources; generated from stage sources. Do not edit.\n"
KEY_RE = re.compile(r'\["([^"]+)"\]\s*=\s*\[(?:=*)\[', re.MULTILINE)
MANIFEST_CHUNKS_RE = re.compile(r"chunks\s*=\s*\{([^}]+)\}", re.DOTALL)
CHUNK_NAME_RE = re.compile(r'"([^"]+)"')


def parse_manifest(mod_dir: Path) -> tuple[list[str], bool]:
    text = (mod_dir / "manifest.lua").read_text(encoding="utf-8")
    if "source_files" in text and re.search(r"source_files\s*=\s*true", text):
        return [], True
    m = MANIFEST_CHUNKS_RE.search(text)
    if not m:
        return [], False
    chunks = CHUNK_NAME_RE.findall(m.group(1))
    return chunks, False


def long_string_delim(body: str) -> tuple[str, str]:
    for n in range(0, 8):
        eq = "=" * n
        close = f"]{eq}]"
        if close not in body:
            return f"[{eq}[", close
    raise ValueError("cannot pick long-string delimiter")


def chunk_keys(chunk_path: Path) -> list[str]:
    if not chunk_path.is_file():
        return []
    text = chunk_path.read_text(encoding="utf-8")
    return KEY_RE.findall(text)


def extract_bodies(chunk_path: Path) -> dict[str, str]:
    text = chunk_path.read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for m in re.finditer(
        r'\["([^"]+)"\]\s*=\s*\[(=*)\[(.*?)\]\2\]',
        text,
        re.DOTALL,
    ):
        key, _, body = m.group(1), m.group(2), m.group(3)
        if body.startswith("\n"):
            body = body[1:]
        if body.endswith("\n"):
            body = body[:-1]
        out[key] = body
    return out


def src_path(mod_dir: Path, import_key: str) -> Path:
    return mod_dir / (import_key.replace(".", "/") + ".lua")


def emit_chunk(mod_dir: Path, chunk_label: str, keys: list[str]) -> str:
    lines = [HEADER.rstrip(), "return {"]
    for key in keys:
        path = src_path(mod_dir, key)
        if not path.is_file():
            raise FileNotFoundError(f"{mod_dir.name}: missing {path.relative_to(UI)} for {chunk_label}")
        body = path.read_text(encoding="utf-8")
        if body.endswith("\n"):
            body = body[:-1]
        open_d, close_d = long_string_delim(body)
        lines.append(f'["{key}"]={open_d}')
        lines.append(body)
        lines.append(f"{close_d},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def regen_module(mod_dir: Path, *, check: bool) -> list[str]:
    chunks, source_files = parse_manifest(mod_dir)
    if source_files:
        return []
    if not chunks:
        return []
    issues: list[str] = []
    for label in chunks:
        chunk_path = mod_dir / f"{label}.lua"
        keys = chunk_keys(chunk_path)
        if not keys:
            issues.append(f"{mod_dir.name}/{label}.lua: no embedded keys (skip)")
            continue
        if check:
            old_bodies = extract_bodies(chunk_path)
            for key in keys:
                src = src_path(mod_dir, key).read_text(encoding="utf-8")
                if src.endswith("\n"):
                    src = src[:-1]
                old = old_bodies.get(key, "")
                if hashlib.sha256(src.encode()).hexdigest() != hashlib.sha256(old.encode()).hexdigest():
                    issues.append(f"drift: {mod_dir.name}/{label}.lua [{key}] != src")
        else:
            new_text = emit_chunk(mod_dir, label, keys)
            chunk_path.write_text(new_text, encoding="utf-8")
            print(f"wrote {chunk_path.relative_to(UI)} ({len(keys)} sources)")
    return issues


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if src/ and chunks diverge")
    args = parser.parse_args()
    modules = sorted((UI / "modules").iterdir())
    all_issues: list[str] = []
    for mod_dir in modules:
        if not mod_dir.is_dir():
            continue
        all_issues.extend(regen_module(mod_dir, check=args.check))
    if all_issues:
        for line in all_issues:
            print(line, file=sys.stderr)
        if args.check:
            raise SystemExit(1)
    if args.check:
        print("M18 chunks match modules/*/src")


if __name__ == "__main__":
    main()