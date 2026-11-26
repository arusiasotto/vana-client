# DLSSNR-RDNA3 (vendored)

The parts of [mauri870/DLSSNR-RDNA3](https://github.com/mauri870/DLSSNR-RDNA3) that the neural rendering engine
builds on, at commit `a2b4edebcd236c8c6d189b340542ce0bf0c3d673` (upstream 0.0.8 merged into rdna3). MIT, see
`LICENSE`. DLSSNR-RDNA3 is mauri870's RDNA3 port of DLSSNR-AMD by mochizuki0323, now maintained as
[TheAutomatic/DLSSNR-AMD](https://github.com/TheAutomatic/DLSSNR-AMD). Thanks to both.

Kept, at their upstream paths:

- `linux/src/core/`: the runtime (`nr_runtime.cpp`, `nr_native_plan.cpp` and the headers they include).
- `linux/shaders/rdna3/`, `linux/shaders/passes/`: the network's shaders and the passes around it.
- `linux/build/build_network.py`, `linux/build/arch/rdna3.sh`: the shader build and the host's matching defines.
- `linux/package/model-tools/`: the Python that makes the model files from the user's own `nvngx_dlssnr.dll`
  (310.9.16 or 310.8.0). `engine/src/model.cpp` is its C++ port, and `engine/tools/gen_model_tables.py` builds the
  port's tables from these files (the descriptors, the file lists, the checksums and the scripts' own region tables).

One change: `build_network.py` takes the glslang binary from `NR_GLSLANG` when it is set.

Nothing from NVIDIA is in this tree.
