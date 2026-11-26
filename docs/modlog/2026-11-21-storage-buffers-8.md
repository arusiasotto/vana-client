## Effects and scenery culling within 8 storage buffers per stage (2026-11-21)

Not retail (ours: wgpu layouts). Mali's GLES drivers (and FFXI_LOW_LIMITS) allow 8 storage buffers per shader stage.
The effects update bound 9, so the game stopped at start-up on those GPUs, and the GPU culling's passes (10 with the
globals' door parts) were built on every device, even GLES, where they can never run.

- The effects update reads the keyframe curves and their keys from one buffer (`effects::key_words`: the curve count,
  each curve's start and count, then the keys): 8 storage buffers. Same values, same lookups.
- The culling's compaction tables (runs, argument bases, each run's argument slots) are one buffer
  (`CullData::tables`): 8 in the compute stage with the door parts.
- The GPU culling's layout and passes are built only where it can run (`cull::on_gpu`: indirect draws from any
  instance and 8 storage buffers); elsewhere the scenery is culled on the CPU (`CpuCull`), as on GLES before.
- Checked: all tests pass on Vulkan and on GLES 3.1 (Mesa llvmpipe), each also with FFXI_LOW_LIMITS, which fails 5
  effects and scenery tests before this change. Output is unchanged.
