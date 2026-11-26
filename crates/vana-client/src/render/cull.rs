//! Frustum culling of scenery on the GPU (ours: retail walks the MZB's tree on the CPU, FUN_1017c8b0). One compute
//! pass marks each instance visible (retail's draw distance and its LOD band to the origin, its mesh's box against the
//! view frustum with the far plane at the draw distance), a second copies each run's visible instances, in order,
//! into a second instance buffer and writes its draws' indirect arguments; the scenery then draws from those.

use super::{Gpu, INSTANCE_BYTES, Instance, Put};
use bytemuck::{Pod, Zeroable};
use glam::{Mat4, Vec3, Vec4};

/// A block of instances drawn together (a mesh's normal or mirrored placements, or both): where its visible copies
/// go, and its draws' arguments (`args_start..+args_count` in the run-args list).
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
pub struct Run {
    inst_start: u32,
    inst_end: u32,
    out_start: u32,
    args_start: u32,
    args_count: u32,
    pad: [u32; 3],
}

/// A draw's fixed arguments: index count, first index, base vertex.
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct ArgBase {
    index_count: u32,
    first_index: u32,
    base_vertex: i32,
    pad: u32,
}

/// A run as the CPU tests it before submitting its draws: the world box around its placements' geometry, the box
/// around their origins (the LOD band is measured to the origin), the union of their bands (None: one draws at any
/// distance), whether any keeps the zone's draw distance and the largest own one squared, and whether it moves (door
/// parts, a voyage's world), which is never skipped.
#[derive(Clone, Copy)]
struct RunBox {
    lo: Vec3,
    hi: Vec3,
    org_lo: Vec3,
    org_hi: Vec3,
    band: Option<(f32, f32)>,
    plain: bool,
    own: f32,
    moves: bool,
}

/// A placement's distance rule (FUN_1017c9c0, doors FUN_10183da0) as cs_cull_vis takes it: its distance squared,
/// and 0 = within the zone's draw distance D, 1 = within its distance times K, 2 (a door group's) = within both.
pub fn reach(own: Option<f32>, door: bool) -> [f32; 2] {
    match own {
        Some(k) => [k * k, if door { 2.0 } else { 1.0 }],
        None => [0.0, 0.0],
    }
}

/// What the culling needs of a geometry, built with it (ZoneGeometry::build_keyed).
#[derive(Default)]
pub struct CullData {
    /// Per instance: its mesh's box in model space, centre then half extents; the fourth words its reach().
    bounds: Vec<[f32; 8]>,
    runs: Vec<Run>,
    boxes: Vec<RunBox>,
    run_args: Vec<u32>,
    args: Vec<ArgBase>,
    /// Each argument slot's run.
    arg_run: Vec<u32>,
    /// Instances the visible copies can take (the runs' lengths summed).
    out_len: u32,
}

impl CullData {
    /// The compaction pass's read-only tables in one buffer (one storage buffer fewer each, for GPUs that allow 8):
    /// word 0 where the argument bases start, word 1 where the runs' argument slots start, then from word 4 the runs
    /// (8 words each), the argument bases (4 each) and the slots.
    fn tables(&self) -> Vec<u32> {
        let runs: &[u32] = bytemuck::cast_slice(&self.runs);
        let args: &[u32] = bytemuck::cast_slice(&self.args);
        let mut t = Vec::with_capacity(4 + runs.len() + args.len() + self.run_args.len());
        t.extend([0, 0, 0, 0]);
        t.extend_from_slice(runs);
        t[0] = t.len() as u32;
        t.extend_from_slice(args);
        t[1] = t.len() as u32;
        t.extend_from_slice(&self.run_args);
        t
    }

    /// `bounds`: each instance's box; `draws`: each draw's sub-draws (instance range, index count, first index, base
    /// vertex). Returns each sub-draw's argument slot.
    pub fn build(
        bounds: Vec<[f32; 8]>,
        instances: &[Instance],
        draws: &[Vec<(std::ops::Range<u32>, u32, u32, i32)>],
    ) -> (Self, Vec<Vec<u32>>) {
        let mut runs: Vec<(std::ops::Range<u32>, Vec<u32>)> = Vec::new();
        let mut by_range: std::collections::HashMap<(u32, u32), usize> = std::collections::HashMap::new();
        let mut args = Vec::new();
        let mut slots = Vec::with_capacity(draws.len());
        for subs in draws {
            let mut s = Vec::with_capacity(subs.len());
            for (range, index_count, first_index, base_vertex) in subs {
                let run = *by_range.entry((range.start, range.end)).or_insert_with(|| {
                    runs.push((range.clone(), Vec::new()));
                    runs.len() - 1
                });
                let slot = args.len() as u32;
                args.push(ArgBase {
                    index_count: *index_count,
                    first_index: *first_index,
                    base_vertex: *base_vertex,
                    pad: 0,
                });
                runs[run].1.push(slot);
                s.push(slot);
            }
            slots.push(s);
        }
        let (mut out, mut run_args, mut gpu_runs, mut boxes) =
            (0u32, Vec::new(), Vec::with_capacity(runs.len()), Vec::with_capacity(runs.len()));
        let mut arg_run = vec![0u32; args.len()];
        for (r, (range, a)) in runs.into_iter().enumerate() {
            gpu_runs.push(Run {
                inst_start: range.start,
                inst_end: range.end,
                out_start: out,
                args_start: run_args.len() as u32,
                args_count: a.len() as u32,
                pad: [0; 3],
            });
            boxes.push(run_box(&bounds, instances, range.clone()));
            out += range.end - range.start;
            for &slot in &a {
                arg_run[slot as usize] = r as u32;
            }
            run_args.extend(a);
        }
        (Self { bounds, runs: gpu_runs, boxes, run_args, args, arg_run, out_len: out }, slots)
    }
}

/// A run's boxes from its instances (each mesh box through its placement matrix).
fn run_box(bounds: &[[f32; 8]], instances: &[Instance], range: std::ops::Range<u32>) -> RunBox {
    let mut b = RunBox {
        lo: Vec3::splat(f32::MAX),
        hi: Vec3::splat(f32::MIN),
        org_lo: Vec3::splat(f32::MAX),
        org_hi: Vec3::splat(f32::MIN),
        band: Some((f32::MAX, f32::MIN)),
        plain: false,
        own: 0.0,
        moves: false,
    };
    for i in range {
        let (Some(inst), Some(bd)) = (instances.get(i as usize), bounds.get(i as usize)) else { continue };
        b.moves |= inst.band[2] != 0.0 || inst.band[3] != 0.0;
        if bd[7] == 0.0 {
            b.plain = true;
        } else {
            b.own = b.own.max(bd[3]);
        }
        let m = Mat4::from_cols_array_2d(&inst.model);
        let centre = m.transform_point3(Vec3::new(bd[0], bd[1], bd[2]));
        let reach =
            m.x_axis.truncate().abs() * bd[4] + m.y_axis.truncate().abs() * bd[5] + m.z_axis.truncate().abs() * bd[6];
        (b.lo, b.hi) = (b.lo.min(centre - reach), b.hi.max(centre + reach));
        let origin = m.w_axis.truncate();
        (b.org_lo, b.org_hi) = (b.org_lo.min(origin), b.org_hi.max(origin));
        b.band = match b.band {
            Some((near, far)) if inst.band[1] > 0.0 => Some((near.min(inst.band[0]), far.max(inst.band[1]))),
            _ => None,
        };
    }
    b
}

/// The six planes of the view frustum (clip x, y in -w..w, z in 0..w) from the view-projection matrix.
fn planes(view_proj: Mat4) -> [Vec4; 6] {
    let r = [view_proj.row(0), view_proj.row(1), view_proj.row(2), view_proj.row(3)];
    [r[3] + r[0], r[3] - r[0], r[3] + r[1], r[3] - r[1], r[2], r[3] - r[2]]
}

impl RunBox {
    /// Could any of its placements be drawn: its geometry box (a little larger, so the GPU's test decides at the
    /// edges) inside the frustum, and its origins within reach of the draw distance (`dk`: D, K; D 0 = none) and of
    /// its bands.
    fn maybe_visible(&self, planes: &[Vec4; 6], eye: Vec3, dk: [f32; 2]) -> bool {
        if self.moves {
            return true;
        }
        let (c, e) = ((self.lo + self.hi) / 2.0, (self.hi - self.lo) / 2.0 * 1.02 + Vec3::splat(0.5));
        if planes.iter().any(|p| p.truncate().dot(c) + p.w < -(p.truncate().abs().dot(e))) {
            return false;
        }
        let nearest = eye.clamp(self.org_lo, self.org_hi).distance_squared(eye);
        // Own distances always hold; D 0 lifts only the zone's.
        let zone = if dk[0] > 0.0 { dk[0] * dk[0] } else { f32::INFINITY };
        let limit = (if self.plain { zone } else { 0.0 }).max(dk[1] * self.own);
        if nearest * 0.98 - 1.0 > limit {
            return false;
        }
        let Some((near, far)) = self.band else { return true };
        let farthest = (eye - self.org_lo).abs().max((eye - self.org_hi).abs()).length_squared();
        farthest * 1.02 + 1.0 > near && nearest * 0.98 - 1.0 <= far
    }
}

/// The culling of one geometry on the GPU: its buffers and the bind group over them and the source instances.
pub struct Cull {
    group: wgpu::BindGroup,
    instances: u32,
    runs: u32,
    boxes: Vec<RunBox>,
    arg_run: Vec<u32>,
    /// Each run's instances, and while a camera list is in force (set_mask), the runs with a listed instance.
    ranges: Vec<(u32, u32)>,
    listed: Option<Vec<bool>>,
    /// Word 0: a camera list is in force; word 1 the reach squared past which the second set draws, word 2 the words
    /// per set; then a bit per instance in each set: listed (it may draw), then unlisted but drawn beyond the reach.
    mask: wgpu::Buffer,
    /// The visible instances, run by run (the scenery's instance vertex buffer), and the draws' indirect arguments.
    pub out: wgpu::Buffer,
    pub args: wgpu::Buffer,
}

impl Cull {
    /// None without indirect draws that start past instance 0, with nothing to draw, or with FFXI_NO_CULL set (a
    /// check against the unculled scene).
    pub fn new(
        gpu: &Gpu,
        layout: Option<&wgpu::BindGroupLayout>,
        data: &CullData,
        instances: &wgpu::Buffer,
    ) -> Option<Self> {
        let layout = layout?;
        if data.runs.is_empty() || data.bounds.is_empty() || std::env::var_os("FFXI_NO_CULL").is_some() {
            return None;
        }
        let device = &gpu.device;
        let with = |label, bytes: &[u8], usage: wgpu::BufferUsages| {
            let b = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: (bytes.len() as u64).max(16),
                usage: usage | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            gpu.queue.put(&b, 0, bytes);
            b
        };
        let empty = |label, size: u64, usage: wgpu::BufferUsages| {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: size.max(16),
                usage,
                mapped_at_creation: false,
            })
        };
        let storage = wgpu::BufferUsages::STORAGE;
        let tables = with("cull tables", bytemuck::cast_slice(&data.tables()), storage);
        let bounds = with("cull bounds", bytemuck::cast_slice(&data.bounds), storage);
        let out = empty("culled instances", data.out_len as u64 * INSTANCE_BYTES, storage | wgpu::BufferUsages::VERTEX);
        let args = empty(
            "cull args",
            data.args.len() as u64 * 20,
            storage | wgpu::BufferUsages::INDIRECT | wgpu::BufferUsages::COPY_SRC,
        );
        let vis = empty("cull visibility", data.bounds.len() as u64 * 4, storage);
        let mask = with("cull camera list", &vec![0u8; (3 + 2 * data.bounds.len().div_ceil(32)) * 4], storage);
        let group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("cull"),
            layout,
            entries: &[&tables, &bounds, instances, &out, &args, &vis, &mask]
                .iter()
                .enumerate()
                .map(|(k, b)| wgpu::BindGroupEntry { binding: k as u32, resource: b.as_entire_binding() })
                .collect::<Vec<_>>(),
        });
        log::info!(
            "scenery culled on the GPU: {} instances in {} runs, {} draws",
            data.bounds.len(),
            data.runs.len(),
            data.args.len()
        );
        let ranges = data.runs.iter().map(|r| (r.inst_start, r.inst_end)).collect();
        Some(Self {
            group,
            instances: data.bounds.len() as u32,
            runs: data.runs.len() as u32,
            boxes: data.boxes.clone(),
            arg_run: data.arg_run.clone(),
            ranges,
            listed: None,
            mask,
            out,
            args,
        })
    }

    /// A camera list in force (FUN_1017b510: the slot draws only its placements): per instance whether it is
    /// listed and whether, unlisted, it draws beyond `reach` (ours, the Draw Distance setting past Retail); None for
    /// every instance.
    pub fn set_mask(&mut self, gpu: &Gpu, mask: Option<(&[bool], &[bool], f32)>) {
        let n = (self.instances as usize).div_ceil(32);
        let mut words = vec![0u32; 3 + 2 * n];
        self.listed = mask.map(|(allowed, beyond, reach)| {
            (words[0], words[1], words[2]) = (1, (reach * reach).to_bits(), n as u32);
            for (set, flags) in [allowed, beyond].iter().enumerate() {
                for (i, _) in flags.iter().enumerate().filter(|(_, on)| **on) {
                    words[3 + set * n + i / 32] |= 1 << (i % 32);
                }
            }
            let any =
                |f: &[bool], s: u32, e: u32| f.get(s as usize..e as usize).is_some_and(|r| r.iter().any(|&on| on));
            self.ranges.iter().map(|&(s, e)| any(allowed, s, e) || any(beyond, s, e)).collect()
        });
        gpu.queue.put(&self.mask, 0, bytemuck::cast_slice(&words));
    }

    /// The last culling's draws with an instance, of all, and the instances drawn (a blocking readback, for the
    /// offscreen benchmark).
    pub fn stats(&self, gpu: &Gpu) -> (u32, u32, u32) {
        let size = self.args.size();
        let read = gpu.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut e = gpu.device.create_command_encoder(&Default::default());
        e.copy_buffer_to_buffer(&self.args, 0, &read, 0, size);
        gpu.queue.submit([e.finish()]);
        read.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        let _ = gpu.device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None });
        let Ok(v) = read.slice(..).get_mapped_range() else { return (0, 0, 0) };
        let words: &[u32] = bytemuck::cast_slice(&v);
        let counts: Vec<u32> = words.chunks(5).map(|a| a[1]).collect();
        (counts.iter().filter(|&&c| c > 0).count() as u32, counts.len() as u32, counts.iter().sum())
    }

    /// Per run, whether its draws go in this frame (RunBox::maybe_visible); the GPU counts what they draw.
    pub fn runs_shown(&self, view_proj: Mat4, eye: Vec3, dk: [f32; 2]) -> Vec<bool> {
        let p = planes(view_proj);
        self.boxes
            .iter()
            .enumerate()
            .map(|(k, b)| self.listed.as_ref().is_none_or(|l| l[k]) && b.maybe_visible(&p, eye, dk))
            .collect()
    }

    /// The run of an argument slot.
    pub fn run_of(&self, slot: u32) -> usize {
        self.arg_run[slot as usize] as usize
    }

    /// Both passes, with the scenery's globals (camera, voyage, door parts) bound at group 0.
    pub fn run(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        globals: &wgpu::BindGroup,
        pipes: &[wgpu::ComputePipeline; 2],
    ) {
        let mut pass =
            encoder.begin_compute_pass(&wgpu::ComputePassDescriptor { label: Some("cull"), timestamp_writes: None });
        pass.set_bind_group(0, globals, &[]);
        pass.set_bind_group(3, &self.group, &[]);
        pass.set_pipeline(&pipes[0]);
        pass.dispatch_workgroups(self.instances.div_ceil(64), 1, 1);
        pass.set_pipeline(&pipes[1]);
        pass.dispatch_workgroups(self.runs, 1, 1);
    }
}

/// The storage buffers the culling passes bind in the compute stage: group 3's seven and the globals' door parts.
/// Mali's GLES and Vulkan drivers allow 8.
pub const STORAGE_NEEDED: u32 = 8;

/// Whether the GPU culling can run on `device`: indirect draws that start past instance 0 (wgpu never offers them on
/// GLES) and the storage buffers. Without it the scenery is culled on the CPU (CpuCull) and the passes aren't built.
pub fn on_gpu(device: &wgpu::Device) -> bool {
    device.features().contains(wgpu::Features::INDIRECT_FIRST_INSTANCE)
        && device.limits().max_storage_buffers_per_shader_stage >= STORAGE_NEEDED
}

/// The bind group layout of group 3: the tables (CullData::tables), bounds, source instances, culled instances, args,
/// visibility, the camera list's mask.
pub fn layout(device: &wgpu::Device) -> wgpu::BindGroupLayout {
    let entry = |binding: u32, read_only: bool| wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::COMPUTE,
        ty: wgpu::BindingType::Buffer {
            ty: wgpu::BufferBindingType::Storage { read_only },
            has_dynamic_offset: false,
            min_binding_size: None,
        },
        count: None,
    };
    device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("cull"),
        entries: &[
            entry(0, true),
            entry(1, true),
            entry(2, true),
            entry(3, false),
            entry(4, false),
            entry(5, false),
            entry(6, true),
        ],
    })
}

/// What one frame's CPU culling reads of the scenery's uniforms.
pub struct View {
    pub view_proj: Mat4,
    pub eye: Vec3,
    /// The voyage matrix (identity off a ship's voyage).
    pub voyage: Mat4,
    /// The draw distance D (0 = none) and K (the `area_info` z / w the shader reads).
    pub clip: [f32; 2],
}

/// The culling of one geometry on the CPU where the GPU's can't run (no indirect draws from any instance: GLES, older
/// GL): the same test per instance (cull_visible), each run's visible instances copied in order into `out` on the GPU
/// (buffer copies of each span, so what the GPU writes into them, the sway step, comes along), drawn with direct
/// draws. Drawing what the GPU culling would leave out wastes time; leaving out what it would draw is
/// a difference, so the distance, band and camera list rules are exact; only moving instances (door parts, a
/// voyage's world) skip the frustum test and draw as they would unculled.
pub struct CpuCull {
    state: std::sync::Mutex<CpuState>,
    bounds: Vec<[f32; 8]>,
    runs: Vec<Run>,
    boxes: Vec<RunBox>,
    arg_run: Vec<u32>,
    pub out: wgpu::Buffer,
}

struct CpuState {
    /// The source instances as the CPU wrote them (patch keeps them in step): their placement and band.
    instances: Vec<Instance>,
    /// The camera list (set_mask): per instance listed, drawn beyond the reach, and the reach.
    mask: Option<(Vec<bool>, Vec<bool>, f32)>,
    listed: Option<Vec<bool>>,
    /// The instances the last run left in.
    drawn: usize,
}

impl CpuCull {
    /// None with nothing to draw or FFXI_NO_CPU_CULL set (the unculled scene, a check).
    pub fn new(gpu: &Gpu, data: &CullData, instances: &[u8]) -> Option<Self> {
        if data.runs.is_empty() || data.bounds.is_empty() || std::env::var_os("FFXI_NO_CPU_CULL").is_some() {
            return None;
        }
        let instances: Vec<Instance> = bytemuck::pod_collect_to_vec(instances);
        let out = gpu.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("culled instances (CPU)"),
            size: (data.out_len as u64 * INSTANCE_BYTES).max(16),
            // COPY_SRC: read back by the tests.
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        log::info!(
            "scenery culled on the CPU: {} instances in {} runs, {} draws",
            data.bounds.len(),
            data.runs.len(),
            data.args.len()
        );
        Some(Self {
            state: std::sync::Mutex::new(CpuState { instances, mask: None, listed: None, drawn: 0 }),
            bounds: data.bounds.clone(),
            runs: data.runs.clone(),
            boxes: data.boxes.clone(),
            arg_run: data.arg_run.clone(),
            out,
        })
    }

    fn state(&self) -> std::sync::MutexGuard<'_, CpuState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// The source buffer took `bytes` at `offset` (a write the GPU culling would read from there).
    pub fn patch(&self, offset: u64, bytes: &[u8]) {
        let mut s = self.state();
        let all: &mut [u8] = bytemuck::cast_slice_mut(&mut s.instances);
        if let Some(dst) = all.get_mut(offset as usize..offset as usize + bytes.len()) {
            dst.copy_from_slice(bytes);
        }
    }

    /// Cull::set_mask's camera list.
    pub fn set_mask(&self, mask: Option<(&[bool], &[bool], f32)>) {
        let mut s = self.state();
        s.listed = mask.map(|(allowed, beyond, _)| {
            let any = |f: &[bool], r: &Run| {
                f.get(r.inst_start as usize..r.inst_end as usize).is_some_and(|x| x.iter().any(|&on| on))
            };
            self.runs.iter().map(|r| any(allowed, r) || any(beyond, r)).collect()
        });
        s.mask = mask.map(|(a, b, reach)| (a.to_vec(), b.to_vec(), reach));
    }

    /// Cull::runs_shown.
    pub fn runs_shown(&self, view_proj: Mat4, eye: Vec3, dk: [f32; 2]) -> Vec<bool> {
        let p = planes(view_proj);
        let s = self.state();
        self.boxes
            .iter()
            .enumerate()
            .map(|(k, b)| s.listed.as_ref().is_none_or(|l| l[k]) && b.maybe_visible(&p, eye, dk))
            .collect()
    }

    /// The run of an argument slot.
    pub fn run_of(&self, slot: u32) -> usize {
        self.arg_run[slot as usize] as usize
    }

    /// The instances the last run left in (the offscreen benchmark).
    pub fn drawn(&self) -> usize {
        self.state().drawn
    }

    /// Culls the runs `shown` lets through and records the copies of their visible instances from `src` (the
    /// geometry's instance buffer, after this frame's sway step) into `out`: per run, its instances there.
    pub fn run(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        src: &wgpu::Buffer,
        view: &View,
        shown: &[bool],
    ) -> Vec<std::ops::Range<u32>> {
        let mut guard = self.state();
        let s = &mut *guard;
        let planes = frustum(view);
        let mut placed = Vec::with_capacity(self.runs.len());
        let mut n = 0u32;
        // Consecutive visible instances go in one copy.
        let mut span: Option<(u32, u32, u32)> = None;
        let mut flush = |span: &mut Option<(u32, u32, u32)>| {
            if let Some((from, to, len)) = span.take() {
                let b = INSTANCE_BYTES;
                encoder.copy_buffer_to_buffer(src, from as u64 * b, &self.out, to as u64 * b, len as u64 * b);
            }
        };
        for (k, r) in self.runs.iter().enumerate() {
            let start = n;
            if shown.get(k).copied().unwrap_or(false) {
                for i in r.inst_start..r.inst_end {
                    let (Some(inst), Some(b)) = (s.instances.get(i as usize), self.bounds.get(i as usize)) else {
                        continue;
                    };
                    if !visible(i as usize, inst, b, view, &planes, s.mask.as_ref()) {
                        continue;
                    }
                    match &mut span {
                        Some((from, to, len)) if *from + *len == i && *to + *len == n => *len += 1,
                        _ => {
                            flush(&mut span);
                            span = Some((i, n, 1));
                        }
                    }
                    n += 1;
                }
            }
            placed.push(start..n);
        }
        flush(&mut span);
        s.drawn = n as usize;
        placed
    }
}

/// cull_visible's seven planes: the view frustum, then retail's far plane at view depth D (none when D is 0).
fn frustum(view: &View) -> [Vec4; 7] {
    let r = [view.view_proj.row(0), view.view_proj.row(1), view.view_proj.row(2), view.view_proj.row(3)];
    let far = view.clip[0];
    let depth = if far > 0.0 { Vec4::new(0.0, 0.0, 0.0, far) - r[3] } else { Vec4::new(0.0, 0.0, 0.0, 1.0) };
    [r[3] + r[0], r[3] - r[0], r[3] + r[1], r[3] - r[1], r[2], r[3] - r[2], depth]
}

/// zone.wgsl cull_visible on the CPU: the camera list, the draw distance to the origin, the LOD band, then the mesh's
/// box against `planes`. A zeroed instance (a hidden link) draws nothing anyway and is left out; a moving one (a
/// door part, a voyage's world) is not tested against the frustum.
fn visible(
    i: usize,
    inst: &Instance,
    b: &[f32; 8],
    view: &View,
    planes: &[Vec4; 7],
    mask: Option<&(Vec<bool>, Vec<bool>, f32)>,
) -> bool {
    let m = Mat4::from_cols_array_2d(&inst.model);
    if m == Mat4::ZERO {
        return false;
    }
    let band = inst.band;
    let voyaged = band[3] != 0.0;
    let origin = if voyaged { (view.voyage * m.w_axis).truncate() } else { m.w_axis.truncate() };
    let d = view.eye - origin;
    let d2 = d.dot(d);
    if let Some((allowed, beyond, reach)) = mask
        && !allowed.get(i).copied().unwrap_or(false)
    {
        let beyond = beyond.get(i).copied().unwrap_or(false);
        if !beyond || d2 <= reach * reach {
            return false;
        }
    }
    let far = view.clip[0];
    // Its distance always holds; D 0 (Settings' Unlimited) lifts only the zone's.
    let own = view.clip[1] * b[3];
    let zone_d = if far > 0.0 { far * far } else { 3.4e38 };
    let limit = if b[7] > 0.5 { if b[7] > 1.5 { own.min(zone_d) } else { own } } else { zone_d };
    if d2 > limit {
        return false;
    }
    if band[1] > 0.0 && !(d2 > band[0] && d2 <= band[1]) {
        return false;
    }
    if band[2] != 0.0 || voyaged {
        return true;
    }
    let centre = m.transform_point3(Vec3::new(b[0], b[1], b[2]));
    let (ax, ay, az) = (m.x_axis.truncate() * b[4], m.y_axis.truncate() * b[5], m.z_axis.truncate() * b[6]);
    planes.iter().all(|p| {
        let n = p.truncate();
        let reach = n.dot(ax).abs() + n.dot(ay).abs() + n.dot(az).abs();
        n.dot(centre) + p.w >= -reach
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The compaction pass's merged tables (one storage buffer for three): each run's fields, each argument base and
    /// each run's slots where zone.wgsl cull_run / cull_arg_base / the slot lookup read them.
    #[test]
    fn tables_put_each_record_where_the_shader_reads_it() {
        let insts: Vec<Instance> = (0..6).map(|k| at(Vec3::new(k as f32, 0.0, 5.0), [0.0; 4])).collect();
        let bounds = vec![[0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0]; 6];
        let draws = [vec![(0..4, 30, 6, -2), (4..6, 12, 0, 7)], vec![(0..4, 9, 90, 3)]];
        let (data, slots) = CullData::build(bounds, &insts, &draws);
        let t = data.tables();
        let (arg_at, slot_at) = (t[0] as usize, t[1] as usize);
        assert_eq!(arg_at, 4 + 8 * data.runs.len());
        assert_eq!(slot_at, arg_at + 4 * data.args.len());
        assert_eq!(t.len(), slot_at + data.run_args.len());
        for (r, run) in data.runs.iter().enumerate() {
            let w = &t[4 + 8 * r..4 + 8 * r + 5];
            assert_eq!(w, [run.inst_start, run.inst_end, run.out_start, run.args_start, run.args_count]);
            for a in 0..run.args_count {
                let slot = t[slot_at + (run.args_start + a) as usize];
                assert_eq!(data.arg_run[slot as usize], r as u32);
            }
        }
        for (subs, got) in draws.iter().zip(&slots) {
            for (&(_, count, first, base), &slot) in subs.iter().zip(got) {
                let b = &t[arg_at + 4 * slot as usize..][..3];
                assert_eq!(b, [count, first, base as u32]);
            }
        }
    }

    /// The GPU culling's passes reading the merged tables: two draws sharing a run and a third in its own run get
    /// their own index count, first index and base vertex, their run's visible count and its first culled instance.
    #[test]
    fn gpu_cull_writes_each_draws_arguments() {
        let Ok(gpu) = Gpu::headless() else { return };
        if !on_gpu(&gpu.device) {
            return;
        }
        let device = &gpu.device;
        let p = gpu.pipes.zone(wgpu::TextureFormat::Rgba8Unorm);
        let (layout, pipes) = p.cull.as_ref().expect("the culling passes");
        let insts: Vec<Instance> =
            [10.0, -10.0, 20.0, 30.0, -5.0, 15.0].iter().map(|&z| at(Vec3::new(0.0, 0.0, z), [0.0; 4])).collect();
        let bounds = vec![[0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0]; insts.len()];
        let draws = [vec![(0..5, 30, 6, -2), (0..5, 12, 0, 7)], vec![(5..6, 9, 90, 3)]];
        let (data, slots) = CullData::build(bounds, &insts, &draws);
        let buf = |bytes: &[u8], usage: wgpu::BufferUsages| {
            let b = device.create_buffer(&wgpu::BufferDescriptor {
                label: None,
                size: bytes.len() as u64,
                usage: usage | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            gpu.queue.put(&b, 0, bytes);
            b
        };
        let instances = buf(bytemuck::cast_slice(&insts), wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::VERTEX);
        let cam = crate::render::Camera {
            jitter: glam::Vec2::ZERO,
            eye: Vec3::ZERO,
            target: Vec3::Z,
            up: Vec3::NEG_Y,
            fov_y: 0.8,
        };
        let mut u = crate::render::Uniforms::zeroed();
        u.view_proj = cam.view_proj(1.0).to_cols_array_2d();
        u.voyage = Mat4::IDENTITY.to_cols_array_2d();
        u.area_info = [0.0, 0.0, 100.0, 1.0];
        let uniforms = buf(bytemuck::bytes_of(&u), wgpu::BufferUsages::UNIFORM);
        let zeros = vec![0u8; 4096];
        let [lights, areas, parts, deltas] = [(); 4].map(|_| buf(&zeros, wgpu::BufferUsages::STORAGE));
        let lamp = buf(&zeros, wgpu::BufferUsages::UNIFORM);
        let globals = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &p.globals_layout,
            entries: &[&uniforms, &lights, &areas, &parts, &deltas, &lamp]
                .iter()
                .enumerate()
                .map(|(k, b)| wgpu::BindGroupEntry { binding: k as u32, resource: b.as_entire_binding() })
                .collect::<Vec<_>>(),
        });
        let c = Cull::new(&gpu, Some(layout), &data, &instances).expect("a GPU culling");
        let read = device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: c.args.size(),
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut enc = device.create_command_encoder(&Default::default());
        c.run(&mut enc, &globals, pipes);
        enc.copy_buffer_to_buffer(&c.args, 0, &read, 0, c.args.size());
        gpu.queue.submit([enc.finish()]);
        read.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        let _ = device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None });
        let words: Vec<u32> = bytemuck::pod_collect_to_vec(&read.slice(..).get_mapped_range().expect("mapped"));
        // Run 0..5 keeps the instances at z 10, 20 and 30 (copied from 0); run 5..6 keeps its one (copied from 5).
        let want = [
            (slots[0][0], [30, 3, 6, -2i32 as u32, 0]),
            (slots[0][1], [12, 3, 0, 7, 0]),
            (slots[1][0], [9, 1, 90, 3, 5]),
        ];
        for (slot, args) in want {
            assert_eq!(words[slot as usize * 5..][..5], args, "slot {slot}");
        }
    }

    fn at(pos: Vec3, band: [f32; 4]) -> Instance {
        Instance { model: Mat4::from_translation(pos).to_cols_array_2d(), lights: [0; 4], area: [0; 4], band }
    }

    /// The CPU test keeps what the GPU's would: in front within the draw distance, not behind, not past D (a
    /// placement without its own distance) or its own distance times K, not outside its band, never a zeroed one;
    /// a moving one skips the frustum test.
    #[test]
    fn cpu_visible_follows_cull_visible() {
        let cam = crate::render::Camera {
            jitter: glam::Vec2::ZERO,
            eye: Vec3::ZERO,
            target: Vec3::Z,
            up: Vec3::NEG_Y,
            fov_y: 0.8,
        };
        let view = View { view_proj: cam.view_proj(1.0), eye: Vec3::ZERO, voyage: Mat4::IDENTITY, clip: [100.0, 1.0] };
        let planes = frustum(&view);
        // A unit box; no own distance (the zone's D), or its own 30 (900 squared, flag 1).
        let zone = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0];
        let own = [0.0, 0.0, 0.0, 900.0, 1.0, 1.0, 1.0, 1.0];
        let vis = |inst: &Instance, b: &[f32; 8]| visible(0, inst, b, &view, &planes, None);
        assert!(vis(&at(Vec3::new(0.0, 0.0, 10.0), [0.0; 4]), &zone));
        assert!(!vis(&at(Vec3::new(0.0, 0.0, -10.0), [0.0; 4]), &zone));
        assert!(!vis(&at(Vec3::new(0.0, 0.0, 150.0), [0.0; 4]), &zone));
        assert!(vis(&at(Vec3::new(0.0, 0.0, 25.0), [0.0; 4]), &own));
        assert!(!vis(&at(Vec3::new(0.0, 0.0, 40.0), [0.0; 4]), &own));
        // Band 20..50 (squared 400..2500).
        assert!(!vis(&at(Vec3::new(0.0, 0.0, 10.0), [400.0, 2500.0, 0.0, 0.0]), &zone));
        assert!(vis(&at(Vec3::new(0.0, 0.0, 30.0), [400.0, 2500.0, 0.0, 0.0]), &zone));
        assert!(!vis(&Instance::zeroed(), &zone));
        // A door part behind the eye still draws (its part matrix moves it).
        assert!(vis(&at(Vec3::new(0.0, 0.0, -10.0), [0.0, 0.0, 3.0, 0.0]), &zone));
        // The camera list: unlisted is out, unless drawn beyond the reach and past it.
        let mask = (vec![false], vec![true], 5.0);
        let near = at(Vec3::new(0.0, 0.0, 3.0), [0.0; 4]);
        assert!(!visible(0, &near, &zone, &view, &planes, Some(&mask)));
        assert!(visible(0, &at(Vec3::new(0.0, 0.0, 10.0), [0.0; 4]), &zone, &view, &planes, Some(&mask)));
    }

    /// The copies: the visible instances of a run land in `out` in order, from the GPU's instance buffer (two spans
    /// here, around the one behind the eye), and the run's draws take that range.
    #[test]
    fn cpu_cull_copies_visible_spans() {
        // FFXI_NO_CPU_CULL turns the culling off (CpuCull::new None): nothing to check.
        if std::env::var_os("FFXI_NO_CPU_CULL").is_some() {
            return;
        }
        let Ok(gpu) = Gpu::headless() else { return };
        let insts: Vec<Instance> = [10.0, -10.0, 20.0, 30.0, -5.0]
            .iter()
            .enumerate()
            .map(|(k, &z)| Instance { area: [k as u32, 0, 0, 0], ..at(Vec3::new(0.0, 0.0, z), [0.0; 4]) })
            .collect();
        let bounds = vec![[0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0]; insts.len()];
        let (data, slots) = CullData::build(bounds, &insts, &[vec![(0..5, 3, 0, 0)]]);
        let c = CpuCull::new(&gpu, &data, bytemuck::cast_slice(&insts)).expect("a CPU culling");
        let src = gpu.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: 5 * INSTANCE_BYTES,
            usage: wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        gpu.queue.put(&src, 0, bytemuck::cast_slice(&insts));
        let cam = crate::render::Camera {
            jitter: glam::Vec2::ZERO,
            eye: Vec3::ZERO,
            target: Vec3::Z,
            up: Vec3::NEG_Y,
            fov_y: 0.8,
        };
        let view = View { view_proj: cam.view_proj(1.0), eye: Vec3::ZERO, voyage: Mat4::IDENTITY, clip: [100.0, 1.0] };
        let read = gpu.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: 3 * INSTANCE_BYTES,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut enc = gpu.device.create_command_encoder(&Default::default());
        let placed = c.run(&mut enc, &src, &view, &[true]);
        enc.copy_buffer_to_buffer(&c.out, 0, &read, 0, 3 * INSTANCE_BYTES);
        gpu.queue.submit([enc.finish()]);
        read.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        let _ = gpu.device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None });
        let got: Vec<Instance> = bytemuck::pod_collect_to_vec(&read.slice(..).get_mapped_range().expect("mapped"));
        assert_eq!(placed[c.run_of(slots[0][0])], 0..3);
        assert_eq!(got.iter().map(|i| i.area[0]).collect::<Vec<_>>(), [0, 2, 3]);
        assert_eq!(c.drawn(), 3);
    }
}
