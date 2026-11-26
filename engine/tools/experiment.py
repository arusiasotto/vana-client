#!/usr/bin/env python3
"""Runs the engine on a capture under several engine.ini settings; GPU time and output per setting.

    experiment.py <capture dir> <out dir> name:key=value,key=value ...
"""
import json, os, re, subprocess, sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
DIST = HERE.parents[1] / "target" / "engine"  # engine/build.sh
cap, out = Path(sys.argv[1]), Path(sys.argv[2])
frames = len([p for p in cap.iterdir() if p.name.startswith("frame_")])
width = json.loads((cap / "frame_000" / "inputs.json").read_text())["files"][0]["width"]
loops = 12
for spec in sys.argv[3:]:
    name, _, kv = spec.partition(":")
    ini = "\n".join(kv.split(",")) + f"\nlog_every = {frames * (loops - 2)}\n"
    (DIST / "nr" / "engine.ini").write_text(ini)
    d = out / name
    d.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, HARNESS_LOOPS=str(loops), TMPDIR=str(out))
    r = subprocess.run([str(DIST / "harness"), str(DIST / "upscale-engine.so"), str(cap), str(frames), str(d)],
                       capture_output=True, text=True, env=env)
    log = (DIST / "nr" / "engine.log").read_text()
    gpu = re.findall(r"gpu ([\d.]+) ms", log)
    net = re.findall(r"network (\d+x\d+)", log)
    for i in range(frames):
        o = np.fromfile(d / f"{i:02d}.out.f32", "<f4").reshape(-1, width, 4)[..., :3]
        Image.fromarray((np.clip(o, 0, 1) ** (1 / 2.2) * 255).round().astype(np.uint8)).save(d / f"{i:02d}.png")
    print(f"{name:14s} gpu {gpu[-1] if gpu else '?':>6} ms  network {net[-1] if net else '?'}  exit {r.returncode}"
          + ("" if r.returncode == 0 else "  " + r.stderr.strip().splitlines()[-1]))
