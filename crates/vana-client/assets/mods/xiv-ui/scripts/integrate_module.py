#!/usr/bin/env python3
"""Dev-only: import a panel tree from assets/mods/<folder> into modules/<alias>."""
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[2]
UI = ASSETS / "xiv-ui"
STORAGE_KEY = "storage.account.xiv_ui_v1"
STORAGE_TMPL = "storage.account.xiv_ui_{alias}_v1"


def extract_m18_meta(text: str) -> tuple[list[str], list[str], str | None]:
    chunks_m = re.search(r'local chunks=\{([^}]+)\}', text)
    imports_m = re.search(r'local imports=\{([^}]+)\}', text)
    stagger_m = re.search(r'for i=1,#"([^"]+)" do', text)
    chunks = []
    imports = []
    if chunks_m:
        chunks = re.findall(r'"([^"]+)"', chunks_m.group(1))
    if imports_m:
        imports = re.findall(r'"([^"]+)"', imports_m.group(1))
    stagger = stagger_m.group(1) if stagger_m else None
    return chunks, imports, stagger


def extract_entry(text: str) -> str:
    lines = text.splitlines()
    start = 0
    for i, line in enumerate(lines):
        if "init.lua body" in line or (
            i > 0 and "startup.phase='entry'" in lines[i - 1]
        ):
            start = i + 1
            if "init.lua body" in line:
                start = i + 1
            break
    end = len(lines)
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].strip().startswith("startup.ready"):
            end = i
            break
    body = "\n".join(lines[start:end]).strip()
    if not body:
        return text.strip()
    return body + "\n"


def patch_storage(tree: Path, alias: str) -> None:
    repl = STORAGE_TMPL.format(alias=alias)
    for path in tree.rglob("*.lua"):
        data = path.read_text(encoding="utf-8")
        if STORAGE_KEY in data:
            path.write_text(data.replace(STORAGE_KEY, repl), encoding="utf-8")


def write_manifest(
    dst: Path, alias: str, chunks: list[str], imports: list[str], stagger: str | None, source_files: bool
) -> None:
    lines = ["return {"]
    if source_files:
        lines.append("  source_files = true,")
    else:
        lines.append("  chunks = {")
        for c in chunks:
            lines.append(f'    "{c}",')
        lines.append("  },")
    lines.append("  imports = {")
    for imp in imports:
        lines.append(f'    "{imp}",')
    lines.append("  },")
    if stagger:
        lines.append(f'  stagger = "{stagger}",')
    lines.append("}")
    (dst / "manifest.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")


def integrate(source_folder: str, alias: str, *, source_files: bool = False, imports: list[str] | None = None) -> None:
    src = ASSETS / source_folder
    if not src.is_dir():
        raise SystemExit(f"missing {src} (optional dev tree; not shipped)")
    dst = UI / "modules" / alias
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(
        src,
        dst,
        ignore=shutil.ignore_patterns("init.lua", "mod.toml"),
    )
    init_path = src / "init.lua"
    init_text = init_path.read_text(encoding="utf-8")
    if source_files:
        entry = init_text.strip() + "\n"
        imp = imports or ["src.bar"]
        stagger = source_folder
        chunks: list[str] = []
    else:
        chunks, imp, stagger = extract_m18_meta(init_text)
        entry = extract_entry(init_text)
        if not imp:
            raise SystemExit(f"no imports for {source_folder}")
    (dst / "entry.lua").write_text(entry, encoding="utf-8")
    write_manifest(dst, alias, chunks, imp, stagger, source_files)
    patch_storage(dst, alias)
    print(f"integrated {source_folder} -> modules/{alias} ({len(chunks)} chunks, {len(imp)} imports)")


def main(argv: list[str] | None = None) -> None:
    import argparse

    p = argparse.ArgumentParser(description="Import assets/mods/<folder> into xiv-ui/modules/<alias> (dev porting only).")
    p.add_argument("folder", help="Directory name under assets/mods/")
    p.add_argument("alias", help="Suite module folder name (e.g. cast, party)")
    p.add_argument("--source-files", action="store_true", help="Use source_files manifest (buff-style panel)")
    p.add_argument(
        "--import",
        dest="imports",
        action="append",
        metavar="MOD",
        help="manifest imports entry (repeat); default src.bar when --source-files",
    )
    args = p.parse_args(argv)
    integrate(args.folder, args.alias, source_files=args.source_files, imports=args.imports)


if __name__ == "__main__":
    main()