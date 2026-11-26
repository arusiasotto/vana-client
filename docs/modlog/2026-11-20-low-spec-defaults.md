## First start on a low-spec GPU: cheaper defaults (2026-11-20)

Not retail (settings defaults). A GPU on the GL / GLES backend, one without BC textures (mobile and SBC GPUs: Raspberry
Pi, Mali, Adreno) or a software rasterizer counts as low-spec (`render::GpuClass`). On a first start (no config file yet, `Config::first_start`)
on one, these take cheaper values than the defaults (`Config::low_spec_defaults`):

- Bump mapping (0017) off: FFXiMain's own default.
- Anisotropic filtering 1 (retail samples without it), Draw Distance Retail. The frame limit stays at its default
  (300); retail's 30 is a setting.
- Background resolution: half the window on a software rasterizer (as before), three quarters on a low-spec GPU
  whose window is over 960 wide. The UI stays at the window's size.
- A window larger than its screen (640x480 / 720x720 handhelds) goes borderless at the screen's size.

Desktop GPUs on Vulkan / DX12 / Metal (all have BC) keep every default. An existing config is never rewritten (an
upgrade, or one run with `WGPU_BACKEND=gl`); the older once-only software-adapter step (`software_gpu_seen`) is gone.
Measured on llvmpipe (zone pass, 1280x720, Bastok Markets / Konschtat): defaults 34.6 / 34.7 ms, bump off 27.3 /
28.2, bump off + anisotropy 1 21.3 / 19.0, background halved 18.6 / 16.1.
