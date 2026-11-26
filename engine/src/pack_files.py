#!/usr/bin/env python3
"""Packs a folder for files.S: "VNRPACK1", the stamp (u32 length + bytes), then per file a u32 name length, the
name (relative, '/'), a u64 size and the bytes. Little-endian. The stamp is the contents' SHA-256 (16 hex digits).

    pack_files.py <folder> <out>
"""
import hashlib
import struct
import sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
files = sorted(p for p in src.rglob("*") if p.is_file())
body, h = bytearray(), hashlib.sha256()
for p in files:
    name, data = p.relative_to(src).as_posix().encode(), p.read_bytes()
    h.update(name + b"\0" + data)
    body += struct.pack("<I", len(name)) + name + struct.pack("<Q", len(data)) + data
stamp = h.hexdigest()[:16].encode()
out.write_bytes(b"VNRPACK1" + struct.pack("<I", len(stamp)) + stamp + body)
print(f"{len(files)} files, stamp {stamp.decode()}")
