## Scenery culling on the CPU where the GPU's can't run (2026-11-21)

Not retail (ours replaces retail's CPU walk of the MZB tree, FUN_1017c8b0, with GPU culling). The GPU culling needs
indirect draws that start past instance 0 (`INDIRECT_FIRST_INSTANCE`), which wgpu never offers on GLES (Raspberry Pi,
Mali / Adreno handhelds, ANGLE) and only on desktop GL 4.2 with `ARB_shader_draw_parameters`. Without it every
instance of every run was submitted (vs_main collapses the out-of-band LOD levels, but they still cost their vertex
work), and the draw distance and camera lists that only the culling applies were lost (a difference from retail on
those GPUs, not only a cost).

- `cull::CpuCull` runs zone.wgsl `cull_visible` on the CPU, the same rules in the same order: camera list, draw
  distance to the origin (D, own times K, a door group's both), LOD band, the mesh box against the frustum and the far
  plane at D. Runs `runs_shown` rejects are skipped whole. Moving instances (door parts, a voyage's world) skip only
  the frustum test; zeroed (hidden link) ones are left out.
- Visible instances are copied span by span from the geometry's instance buffer into `out` on the GPU, so what the
  GPU writes there (the sway step) comes along; the scenery draws them with direct draws (`Culled::Cpu`).
- The CPU keeps the instances' placements in step with the buffer writes (lamp lights, hidden links, the slot leak).
- Checked: with `FFXI_NO_CULL` on Vulkan (forcing this path), Bastok Markets and Konschtat render pixel-identical to
  the GPU culling. GLES 3.1 on llvmpipe, zone pass at 1600x900: Bastok 48.5 -> 44.2 ms, Konschtat 99.7 -> 46.6 ms.
  `FFXI_NO_CPU_CULL` turns it off (the unculled scene, a check).
