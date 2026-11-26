# The neural rendering engine

`upscale-engine.so`: Settings > Upscaling > Neural Rendering (config `neural`). It runs NVIDIA's DLSS 5 neural
rendering network on the render-size colour before the upscale, through the `vana_nr_dispatch` export of the engine
ABI (`docs/upscaler-engine.md`). Linux, Vulkan backend. Built for RDNA3 (Radeon RX 7000) and tested on a 7900 XTX.

The network is [DLSSNR-RDNA3](https://github.com/mauri870/DLSSNR-RDNA3)'s runtime (mauri870, MIT), built on
DLSSNR-AMD (mochizuki0323, MIT), vendored in `vendor/dlssnr-rdna3/`. The colour handover in `src/compose.comp`
follows RenoDX's DLSS 5 resolve.

## Build

```sh
engine/build.sh                 # target/engine/upscale-engine.so
release/build-engine.sh         # the release asset, built in the Steam Runtime SDK
```

Needs g++ (C++20), zlib, the Vulkan loader and headers 1.4.357 or later (`VULKAN_INCLUDE`), glslang and python3 (at
build time only).

## Install

The client downloads `vana-client-nr-engine-linux-x86_64.so` from its release when Neural Rendering is turned on and
keeps it as `upscale-engine.so` in the data folder (`~/.local/share/vana-client`). By hand: copy
`target/engine/upscale-engine.so` there, or point `VANA_UPSCALE_ENGINE` at it.

It is one file. On first use it writes its packed files into `nr/` beside it (`VANA_NR_ROOT` overrides the folder):

| Path | |
|---|---|
| `nr/dlssnr-amd/shaders/` | The network's shaders. |
| `nr/prep.spv`, `nr/compose.spv` | The passes either side of the network. |
| `nr/engine.ini.default` | The default settings; the first run copies it to `nr/engine.ini`, which is never overwritten. |
| `nr/.files` | Which build wrote them: a new build writes them again. |
| `nr/dlssnr-amd/dlssnr-small.bin`, `dlssnr.bin` | The model. Not shipped: made from the player's NVIDIA DLL, below. |
| `nr/engine.log` | Settings and GPU time. |

## The model

The weights are NVIDIA's and are not in this repository or in a release. They come from the player's own copy of
`nvngx_dlssnr.dll`: 310.9.16 makes both models, 310.8.0 the original only. The engine makes them itself
(`src/model.cpp`, a port of DLSSNR-RDNA3's model tools): it takes the DLL or a zip holding it, reads only the weight
data (the DLL is never loaded or run) and keeps a file only when it matches the tested model byte for byte.

The client calls these exports (also in `docs/upscaler-engine.md`); each writes one plain sentence into `msg`:

```c
const char* vana_nr_version(void);                                   /* "vana-client/<version>" */
int vana_nr_model_status(char* msg, uint32_t size);                  /* 0 ready, 1 no model, 2 nr/ unwritable */
int vana_nr_check_dll(const char* path, char* msg, uint32_t size);   /* 0 usable (msg: what it makes), 1 not (why) */
int vana_nr_make_model(const char* path, void (*progress)(float fraction, void* user), void* user,
                       char* msg, uint32_t size);                    /* 0 made, 1 not (why); blocks, off the render thread */
```

A model made while the game runs is picked up within a few seconds. With only the original model, `model = small`
falls back to it.

By hand: `target/engine/model_check <nvngx_dlssnr.dll or zip> ~/.local/share/vana-client/nr/dlssnr-amd`.

## Settings

`engine.ini` (`engine.ini` here is the default):

- `model`: `small` (faster) or `original` (stronger, about twice the cost).
- `scale`: the network's size as a fraction of the render size, 0.25..1.
- `reuse_every`: run the network every Nth frame and carry its edit along the motion between.
- `style`, `intensity`, `local_tone`, `local_structure`, `skin_structure`, `exposure_ev`, `strength`, `color`,
  `chroma_clamp`, `vivid_guard`, `history`, `log_every`: see the comments in `engine.ini`.

`model`, `scale` and `reuse_every` rebuild the network when changed (a short hitch); the rest apply at once.

GPU time per frame on a 7900 XTX, 1280 x 720: the original model 15.0 ms, small 8.1, small at scale 0.5 4.1,
small with reuse 2 (the default) 4.3.

## Tools

- `tools/harness.cpp` (built as `target/engine/harness`): `harness <engine.so> <capture> <frames> <out>` calls
  `vana_nr_dispatch` the way the client does on an `/upcapture` capture and writes each frame's output as linear f32.
- `tools/model_check.cpp` (built as `target/engine/model_check`): makes the model from a DLL, with progress.
- `tools/experiment.py <capture> <out> name:key=value,...`: runs the harness under several `engine.ini` settings and
  prints the GPU time of each.
