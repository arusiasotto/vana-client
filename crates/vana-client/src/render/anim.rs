//! Motion evaluation on the GPU: animation keys and skeletons go up once per model, and a compute pass
//! poses every world actor each frame (dat/character.rs `pose`, plus the cross-fade of
//! render/character.rs `pose_blend`) straight into the pose regions vs_skinned reads.

use super::Gpu;
use super::Put;
use crate::dat::character::{Animation, Character};
use std::any::Any;
use std::collections::HashMap;
use std::sync::Arc;

/// Bones a pose region holds (render/mod.rs MAX_BONES) and the per-animation bone table size.
const TABLE: usize = crate::dat::animpack::TABLE;
/// Queue entries per pose (motionq::Layer): up to seven regions, each with the one or two entries a blend holds
/// (a fourth entry in a region cuts the oldest within a tick).
pub const MAX_SET: usize = 24;
/// Job header: skeleton, output, the layer count, the weights of the overlay regions 5 and 6, then the head look
/// (weight, two bones, model-space point, bones used, point 4, limits, point 4 drop, point 3 offset), then the drawn
/// weapons' grip pairs (words 29 / 30). Each layer after it is 4 words: animation, frame, weight, and its kind
/// (0 body, 1 / 2 overlay region 5 / 6) with bit 8 on the first of a region.
const HEAD: usize = 32;
const JOB_WORDS: usize = HEAD + 4 * MAX_SET;
const NO_BONE: u32 = u32::MAX;
const UNKEYED: u32 = crate::dat::animpack::UNKEYED;

/// Where a layer's animation is: the model's list, or a motion file's.
#[derive(Clone, Copy)]
pub enum AnimSrc<'a> {
    Model(usize),
    File(&'a Arc<crate::dat::motionfile::MotionFile>, usize),
}

/// One layer of a pose job (motionq::Layer).
#[derive(Clone, Copy)]
pub struct JobLayer<'a> {
    pub src: AnimSrc<'a>,
    pub frame: f32,
    pub weight: f32,
    pub start: bool,
    pub over: u8,
}

/// A plain list of the model's (animation, frame) where the latest track wins, as layers, one region each,
/// last first (the first region to write a bone keeps it).
pub fn plain_layers<'a>(ch: &Character, to: &[(&Animation, f32)]) -> Vec<JobLayer<'a>> {
    to.iter()
        .rev()
        .filter_map(|(a, frame)| {
            let i = ch.animations.iter().position(|x| std::ptr::eq(x, *a))?;
            Some(JobLayer { src: AnimSrc::Model(i), frame: *frame, weight: 1.0, start: true, over: 0 })
        })
        .collect()
}

/// A head look for the compute pass (FUN_1002a140 / FUN_1002ac60): from the body reference point 4 - point 3,
/// the head (point 3's bone) turns toward the point as far as its tangent ellipse allows and the neck (point 7's)
/// takes the rest, at `weight`; one bone only when sitting or riding.
#[derive(Clone, Copy, Debug)]
pub struct HeadLook {
    pub bones: [Option<u16>; 2],
    pub two: bool,
    pub weight: f32,
    pub point: glam::Vec3,
    pub p3: glam::Vec3,
    pub p4: (u16, glam::Vec3),
    /// Point 4 raised (model y) on a chocobo or a mount.
    pub drop: f32,
    pub limits: [[f32; 3]; 2],
}
/// Scratch vec4s per job: each bone's rotation, translation and scale.
const SCRATCH: usize = TABLE * 3;

const WGSL: &str = r#"
@group(0) @binding(0) var<storage, read> data: array<u32>;
@group(0) @binding(1) var<storage, read> jobs: array<u32>;
@group(0) @binding(2) var<storage, read_write> pose: array<vec4<f32>>;
@group(0) @binding(3) var<storage, read_write> scratch: array<vec4<f32>>;

fn fl(i: u32) -> f32 { return bitcast<f32>(data[i]); }

// Channel::pair: the keys either side of `frame` (clamped to the last) and the fraction, a constant twice with 0;
// key offsets count from the animation `an`.
fn keys(an: u32, c: u32, frame: f32) -> vec3<f32> {
    let n = data[c];
    let v = data[c + 1u];
    if (n == 0u) { return vec3<f32>(bitcast<f32>(v), bitcast<f32>(v), 0.0); }
    let last = n - 1u;
    let f = clamp(frame, 0.0, f32(last));
    let i = min(u32(f), last);
    let j = min(i + 1u, last);
    return vec3<f32>(fl(an + v + i), fl(an + v + j), f - f32(i));
}

fn chan(an: u32, c: u32, frame: f32) -> f32 {
    let k = keys(an, c, frame);
    return k.x + (k.y - k.x) * k.z;
}

// Track::sample's rotation: FUN_10032400 negates the next key when the dot is negative, then lerps.
fn rot_at(an: u32, tr: u32, frame: f32) -> vec4<f32> {
    let x = keys(an, tr, frame);
    let y = keys(an, tr + 2u, frame);
    let z = keys(an, tr + 4u, frame);
    let w = keys(an, tr + 6u, frame);
    let a = vec4<f32>(x.x, y.x, z.x, w.x);
    var b = vec4<f32>(x.y, y.y, z.y, w.y);
    if (dot(a, b) < 0.0) { b = -b; }
    return normalize(mix(a, b, max(max(x.z, y.z), max(z.z, w.z))));
}

fn qmul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z);
}

fn qrot(q: vec4<f32>, v: vec3<f32>) -> vec3<f32> {
    let t = 2.0 * cross(q.xyz, v);
    return v + q.w * t + cross(q.xyz, t);
}

// Shortest rotation taking unit u to unit v.
fn arc(u: vec3<f32>, v: vec3<f32>) -> vec4<f32> {
    let c = dot(u, v);
    if (c < -0.9999) { return vec4<f32>(0.0, 1.0, 0.0, 0.0); }
    return normalize(vec4<f32>(cross(u, v), 1.0 + c));
}

fn qconj(q: vec4<f32>) -> vec4<f32> { return vec4<f32>(-q.xyz, q.w); }

fn jf(i: u32) -> f32 { return bitcast<f32>(jobs[i]); }

// FUN_1002b140: v clamped to the ellipse |X| <= a, |Y| <= b at depth c in the tangent frame LookAt(0, d, +y).
fn look_clamp(d: vec3<f32>, v: vec3<f32>, a0: f32, b0: f32, c: f32) -> vec3<f32> {
    let a = select(a0, 0.001, a0 == 0.0);
    let b = select(b0, 0.001, b0 == 0.0);
    var xa = cross(vec3<f32>(0.0, 1.0, 0.0), d);
    if (length(xa) < 1e-5) { xa = vec3<f32>(1.0, 0.0, 0.0); }
    xa = normalize(xa);
    let ya = cross(d, xa);
    var l = vec3<f32>(dot(v, xa), dot(v, ya), dot(v, d));
    var m = b;
    if (a > b) { l.y = l.y * (a / b); m = a; } else { l.x = l.x * (b / a); }
    var xy = select(vec2<f32>(c * l.x, c * l.y) * 200.0, vec2<f32>(c * l.x, c * l.y) / l.z, l.z > 0.0);
    if (length(xy) <= m) { return v; }
    let th = atan2(xy.y, xy.x);
    xy = vec2<f32>(m * cos(th), m * sin(th));
    if (a > b) { xy.y = xy.y / (a / b); } else { xy.x = xy.x / (b / a); }
    return normalize(xy.x * xa + xy.y * ya + c * d);
}

// glam Quat::slerp.
fn slerp(a: vec4<f32>, b0: vec4<f32>, s: f32) -> vec4<f32> {
    var b = b0;
    var d = dot(a, b);
    if (d < 0.0) { b = -b; d = -d; }
    if (d > 1.0 - 1.1920929e-7) { return normalize(a + (b - a) * s); }
    let theta = acos(d);
    let x = 1.0 / sin(theta);
    return (a * sin(theta * (1.0 - s)) + b * sin(theta * s)) * x;
}

// A track's scale channels (words 14..19).
fn scale_at(an: u32, tr: u32, frame: f32) -> vec3<f32> {
    return vec3<f32>(chan(an, tr + 14u, frame), chan(an, tr + 16u, frame), chan(an, tr + 18u, frame));
}

// FUN_10033220 (FUN_10019ee0): straight toward the nearer of b and -b.
fn mixq(a: vec4<f32>, b0: vec4<f32>, s: f32) -> vec4<f32> {
    var b = b0;
    if (dot(a, b) < 0.0) { b = -b; }
    return normalize(a * (1.0 - s) + b * s);
}

// Local transform of bone `b` from the rest pose and the job's queue layers (FUN_1001a420): in a body region the
// first layer keying the bone sets it and the later ones blend over by their weights, and a bone a region wrote is
// closed to the regions after; an overlay region is posed apart and blended over by the region's weight.
fn local_tf(skel: u32, b: u32, job: u32, count: u32, q: ptr<function, vec4<f32>>, t: ptr<function, vec3<f32>>, sc: ptr<function, vec3<f32>>) {
    let s = skel + 1u + b * 8u;
    let rq = vec4<f32>(fl(s + 1u), fl(s + 2u), fl(s + 3u), fl(s + 4u));
    let rt = vec3<f32>(fl(s + 5u), fl(s + 6u), fl(s + 7u));
    *q = rq;
    *t = rt;
    *sc = vec3<f32>(1.0);
    var taken = false;
    var written = false;
    var kind = 0u;
    var oq = rq;
    var ot = rt;
    var os = vec3<f32>(1.0);
    for (var k = 0u; k <= count; k = k + 1u) {
        let at = job + HEADu + 4u * k;
        var mt = 0x100u;
        if (k < count) { mt = jobs[at + 3u]; }
        if ((mt & 0x100u) != 0u) {
            if (written) {
                if (kind == 0u) {
                    taken = true;
                } else {
                    let w = jf(job + 2u + kind);
                    *q = mixq(*q, oq, w);
                    *t = mix(*t, ot, w);
                    *sc = mix(*sc, os, w);
                }
            }
            written = false;
            kind = mt & 0xffu;
        }
        if (k == count) { break; }
        let a = jobs[at];
        let ti = data[a + 2u + b];
        if (ti == 0u || (kind == 0u && taken)) { continue; }
        let w = jf(at + 2u);
        var nq = rq;
        var nt = rt;
        var ns = vec3<f32>(1.0);
        if (ti == UNKEYEDu) {
            // Named but not keyed: back toward the rest pose over an older layer of its body region.
            if (kind != 0u || !written) { continue; }
        } else {
            let frame = jf(at + 1u);
            let tr = a + 2u + 256u + (ti - 1u) * 20u;
            nq = qmul(rot_at(a, tr, frame), rq);
            nt = rt + vec3<f32>(chan(a, tr + 8u, frame), chan(a, tr + 10u, frame), chan(a, tr + 12u, frame));
            ns = scale_at(a, tr, frame);
        }
        if (kind == 0u) {
            if (written) { *q = mixq(*q, nq, w); *t = mix(*t, nt, w); *sc = mix(*sc, ns, w); }
            else { *q = nq; *t = nt; *sc = ns; }
        } else {
            if (written) { oq = mixq(oq, nq, w); ot = mix(ot, nt, w); os = mix(os, ns, w); }
            else { oq = nq; ot = nt; os = ns; }
        }
        written = true;
    }
}

// FUN_100339b0: bone b from its parent p; the child's translation scaled by the parent's accumulated scale, in the
// parent's frame.
fn chain(sc: u32, b: u32, p: u32) {
    let pq = scratch[sc + 3u * p];
    let pt = scratch[sc + 3u * p + 1u].xyz;
    let ps = scratch[sc + 3u * p + 2u].xyz;
    let lq = scratch[sc + 3u * b];
    let lt = scratch[sc + 3u * b + 1u].xyz;
    let ls = scratch[sc + 3u * b + 2u].xyz;
    scratch[sc + 3u * b] = qmul(pq, lq);
    scratch[sc + 3u * b + 1u] = vec4<f32>(pt + qrot(pq, ps * lt), 0.0);
    scratch[sc + 3u * b + 2u] = vec4<f32>(ps * ls, 0.0);
}

// Bone b's output.
fn emit(sc: u32, b: u32, out: u32) {
    pose[out + 3u * b] = scratch[sc + 3u * b];
    pose[out + 3u * b + 1u] = vec4<f32>(scratch[sc + 3u * b + 1u].xyz, 0.0);
    pose[out + 3u * b + 2u] = vec4<f32>(scratch[sc + 3u * b + 2u].xyz, 0.0);
}

@compute @workgroup_size(64)
fn pose_actors(@builtin(workgroup_id) wg: vec3<u32>, @builtin(local_invocation_index) lid: u32) {
    let job = wg.x * JOB_WORDSu;
    let skel = jobs[job];
    let out = jobs[job + 1u];
    let n_to = jobs[job + 2u];
    let look_w = bitcast<f32>(jobs[job + 5u]);
    let look_a = jobs[job + 6u];
    let look_b = jobs[job + 7u];
    let look_p = vec3<f32>(bitcast<f32>(jobs[job + 8u]), bitcast<f32>(jobs[job + 9u]), bitcast<f32>(jobs[job + 10u]));
    let look_n = jobs[job + 11u];
    let p4_bone = jobs[job + 12u];
    let p4_off = vec3<f32>(jf(job + 13u), jf(job + 14u), jf(job + 15u));
    let p3_off = vec3<f32>(jf(job + 23u), jf(job + 24u), jf(job + 25u));
    let lo = min(look_a, look_b);
    var q3 = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var q7 = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    let n = data[skel];
    let sc = wg.x * SCRATCHu;
    // Scratch per bone: (q, t, s) of the pose.
    for (var b = lid; b < n; b = b + 64u) {
        var q: vec4<f32>;
        var t: vec3<f32>;
        var s: vec3<f32>;
        local_tf(skel, b, job, n_to, &q, &t, &s);
        scratch[sc + 3u * b] = q;
        scratch[sc + 3u * b + 1u] = vec4<f32>(t, 0.0);
        scratch[sc + 3u * b + 2u] = vec4<f32>(s, 0.0);
    }
    storageBarrier();
    workgroupBarrier();
    if (lid != 0u) { return; }
    // Drawn weapons (FUN_10029320): (carry | grip << 16) pairs; the grip's local scale takes the carry's.
    var grips = array<u32, 2>(jobs[job + 29u], jobs[job + 30u]);
    for (var i = 0u; i < 2u; i = i + 1u) {
        if (grips[i] == NO_BONEu) { continue; }
        let c = grips[i] & 0xffffu;
        let g = grips[i] >> 16u;
        scratch[sc + 3u * g + 2u] = vec4<f32>(scratch[sc + 3u * g + 2u].xyz * scratch[sc + 3u * c + 2u].xyz, 0.0);
    }
    // Parents precede children: chain in place. A carry bone's subtree waits for pass 1 (flag in .w).
    for (var b = 0u; b < n; b = b + 1u) {
        if (b == 0u) {
            // Bone 0's translation through RotY(3 pi / 2) (FUN_10033800).
            let lt = scratch[sc + 1u].xyz;
            scratch[sc + 1u] = vec4<f32>(-lt.z, lt.y, lt.x, 0.0);
        } else {
            let p = data[skel + 1u + b * 8u];
            let held = scratch[sc + 3u * p + 1u].w == 1.0 || (grips[0] != NO_BONEu && p == (grips[0] & 0xffffu)) || (grips[1] != NO_BONEu && p == (grips[1] & 0xffffu));
            if (held) {
                scratch[sc + 3u * b + 1u].w = 1.0;
                continue;
            }
            chain(sc, b, p);
        }
        // Head look (FUN_1002ac60), worked out at the lower of the two bones from the target pose: the head's
        // world place from the neck (its parent) and its local, point 4 for the body's reference direction.
        if (look_w > 0.0 && b == lo && data[skel + 1u + look_a * 8u] == look_b) {
            let nq = scratch[sc + 3u * b];
            let nt = scratch[sc + 3u * b + 1u].xyz;
            let ns = scratch[sc + 3u * b + 2u].xyz;
            let hq = qmul(nq, scratch[sc + 3u * look_a]);
            let ht = nt + qrot(nq, ns * scratch[sc + 3u * look_a + 1u].xyz);
            let hs = ns * scratch[sc + 3u * look_a + 2u].xyz;
            let p3 = ht + qrot(hq, hs * p3_off);
            var p4: vec3<f32>;
            if (p4_bone == look_a) {
                p4 = ht + qrot(hq, hs * p4_off);
            } else {
                p4 = scratch[sc + 3u * p4_bone + 1u].xyz + qrot(scratch[sc + 3u * p4_bone], scratch[sc + 3u * p4_bone + 2u].xyz * p4_off);
            }
            p4.y = p4.y - jf(job + 22u);
            let d = normalize(p4 - p3);
            var v = normalize(look_p - p3);
            for (var i = 0u; i < look_n; i = i + 1u) {
                let la = jf(job + 16u + 3u * i);
                let lb = jf(job + 17u + 3u * i);
                if (la == 0.0 && lb == 0.0) { continue; }
                let dir = look_clamp(d, v, la, lb, jf(job + 18u + 3u * i));
                let qi = slerp(vec4<f32>(0.0, 0.0, 0.0, 1.0), arc(d, dir), look_w);
                v = qrot(qconj(qi), v);
                if (i == 0u) { q3 = qi; } else { q7 = qi; }
            }
        }
        // The neck turns by its share; the head by both, about its pivot (bone locals turned against the neck's
        // pre-look rotation, FUN_1002ac60's second loop).
        if (look_w > 0.0 && (b == look_a || b == look_b)) {
            let r = select(qmul(qmul(q7, q3), qconj(q7)), q7, b == look_b);
            scratch[sc + 3u * b] = normalize(qmul(r, scratch[sc + 3u * b]));
        }
        emit(sc, b, out);
    }
    // Pass 1: each carry bone on its grip (its scale kept), then the held subtrees in order.
    for (var i = 0u; i < 2u; i = i + 1u) {
        if (grips[i] == NO_BONEu) { continue; }
        let c = grips[i] & 0xffffu;
        let g = grips[i] >> 16u;
        scratch[sc + 3u * c] = scratch[sc + 3u * g];
        scratch[sc + 3u * c + 1u] = vec4<f32>(scratch[sc + 3u * g + 1u].xyz, 0.0);
        emit(sc, c, out);
    }
    for (var b = 1u; b < n; b = b + 1u) {
        if (scratch[sc + 3u * b + 1u].w == 1.0) {
            chain(sc, b, data[skel + 1u + b * 8u]);
            emit(sc, b, out);
        }
    }
}
"#;

/// Keys and skeletons in one u32 buffer (floats as bits), jobs per frame, and the compute pipeline.
pub struct GpuAnim {
    pipeline: wgpu::ComputePipeline,
    layout: wgpu::BindGroupLayout,
    group: super::BindCache<[wgpu::Buffer; 4]>,
    /// Words added since the last upload; they go to `uploaded` and up.
    data: Vec<u32>,
    uploaded: usize,
    data_buf: Option<wgpu::Buffer>,
    /// Uploaded sources by Arc address (the Arc is kept so the address stays theirs): skeleton offset, animation
    /// offsets in order, and the end of their words.
    sources: HashMap<usize, (Arc<dyn Any + Send + Sync>, Option<u32>, Vec<u32>, u32)>,
    /// Where each animation block (by Packed::key) went: start and end.
    blocks: HashMap<u64, (u32, u32)>,
    jobs: Vec<u32>,
    job_buf: Option<(wgpu::Buffer, u64)>,
    scratch: Option<(wgpu::Buffer, u64)>,
}

/// The posing pipeline and its layout (made once per device, render::PipeCache).
pub fn pipeline(device: &wgpu::Device) -> (wgpu::ComputePipeline, wgpu::BindGroupLayout) {
    {
        let src = WGSL
            .replace("JOB_WORDSu", &format!("{JOB_WORDS}u"))
            .replace("SCRATCHu", &format!("{SCRATCH}u"))
            .replace("UNKEYEDu", &format!("{UNKEYED}u"))
            .replace("HEADu", &format!("{HEAD}u"))
            .replace("NO_BONEu", &format!("{NO_BONE}u"));
        let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("pose actors"),
            source: wgpu::ShaderSource::Wgsl(src.into()),
        });
        let entry = |binding, read_only| wgpu::BindGroupLayoutEntry {
            binding,
            visibility: wgpu::ShaderStages::COMPUTE,
            ty: wgpu::BindingType::Buffer {
                ty: wgpu::BufferBindingType::Storage { read_only },
                has_dynamic_offset: false,
                min_binding_size: None,
            },
            count: None,
        };
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("pose actors"),
            entries: &[entry(0, true), entry(1, true), entry(2, false), entry(3, false)],
        });
        let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("pose actors"),
            bind_group_layouts: &[Some(&layout)],
            immediate_size: 0,
        });
        let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("pose actors"),
            layout: Some(&pl),
            module: &module,
            entry_point: Some("pose_actors"),
            compilation_options: Default::default(),
            cache: None,
        });
        (pipeline, layout)
    }
}

impl GpuAnim {
    pub fn new(gpu: &Gpu) -> Self {
        let (pipeline, layout) = gpu.pipes.anim().clone();
        Self {
            group: Default::default(),
            pipeline,
            layout,
            data: Vec::new(),
            uploaded: 0,
            data_buf: None,
            sources: HashMap::new(),
            blocks: HashMap::new(),
            jobs: Vec::new(),
            job_buf: None,
            scratch: None,
        }
    }

    /// Offsets of a source's skeleton (if any) and animations, uploading them the first time. The loader
    /// threads pack them (`packed`); packing here is only for sources that skipped that.
    fn source(
        &mut self,
        key: usize,
        keep: Arc<dyn Any + Send + Sync>,
        skel: Option<&crate::dat::character::Skeleton>,
        anims: &[Animation],
        packed: Option<&crate::dat::animpack::Packed>,
    ) -> (Option<u32>, &[u32]) {
        if !self.sources.contains_key(&key) {
            let at = |d: &Vec<u32>, up: usize| (up + d.len()) as u32;
            let s = skel.map(|sk| {
                let s = at(&self.data, self.uploaded);
                self.data.push(sk.bones.len().min(TABLE - 1) as u32);
                for (i, b) in sk.bones.iter().take(TABLE - 1).enumerate() {
                    self.data.push(if i == 0 { 0 } else { b.parent as u32 });
                    self.data.extend(b.rot.to_array().map(f32::to_bits));
                    self.data.extend(b.pos.to_array().map(f32::to_bits));
                }
                s
            });
            let local;
            let p = match packed {
                Some(p) => p,
                None => {
                    local = crate::dat::animpack::pack(anims);
                    &local
                }
            };
            let (base, block_end) = match self.blocks.get(&p.key) {
                Some(&b) => b,
                None => {
                    let b = at(&self.data, self.uploaded);
                    self.data.extend_from_slice(&p.words);
                    let e = at(&self.data, self.uploaded);
                    self.blocks.insert(p.key, (b, e));
                    crate::client::perf::note(|| format!("anim block {} words", p.words.len()));
                    (b, e)
                }
            };
            let offs = p.offsets.iter().map(|o| base + o).collect();
            let end = block_end.max(s.map_or(0, |_| at(&self.data, self.uploaded)));
            self.sources.insert(key, (keep, s, offs, end));
        }
        let e = &self.sources[&key];
        (e.1, &e.2)
    }

    /// Adds a model's skeleton and animations ahead of its first job.
    pub fn register(&mut self, ch: &Arc<Character>) {
        self.source(Arc::as_ptr(ch) as usize, ch.clone(), Some(&ch.skeleton), &ch.animations, ch.packed.as_deref());
    }

    /// A registered model's words are all on the GPU.
    pub fn ready(&self, ch: &Arc<Character>) -> bool {
        self.sources.get(&(Arc::as_ptr(ch) as usize)).is_some_and(|s| s.3 as usize <= self.uploaded)
    }

    /// Starts a frame's jobs.
    pub fn begin(&mut self) {
        self.jobs.clear();
    }

    /// Queues one actor: its model and the layers of its motion queues (motionq::Queues::layers order, with the
    /// overlay regions' weights), written to pose vec4 index `out`.
    pub fn job(
        &mut self,
        ch: &Arc<Character>,
        layers: &[JobLayer],
        over: [f32; 2],
        out: u32,
        look: Option<HeadLook>,
        grips: &[(u16, u16)],
    ) {
        let (Some(skel), _) =
            self.source(Arc::as_ptr(ch) as usize, ch.clone(), Some(&ch.skeleton), &ch.animations, ch.packed.as_deref())
        else {
            return;
        };
        let mut lookup = |src: AnimSrc| -> Option<u32> {
            match src {
                AnimSrc::Model(i) => self.sources[&(Arc::as_ptr(ch) as usize)].2.get(i).copied(),
                AnimSrc::File(f, i) => {
                    let key = Arc::as_ptr(f) as usize;
                    self.source(key, f.clone(), None, &f.animations, f.packed.as_deref());
                    // A motion file whose words are not up yet sits this frame out.
                    let e = &self.sources[&key];
                    if e.3 as usize <= self.uploaded { e.2.get(i).copied() } else { None }
                }
            }
        };
        let mut words = vec![0u32; JOB_WORDS];
        words[0] = skel;
        words[1] = out;
        words[3] = over[0].to_bits();
        words[4] = over[1].to_bits();
        words[6] = NO_BONE;
        words[7] = NO_BONE;
        // Drawn weapons' (carry, grip) pairs (FUN_10029320), carry | grip << 16.
        for k in 0..2 {
            words[29 + k] = grips.get(k).map_or(NO_BONE, |&(c, g)| c as u32 | (g as u32) << 16);
        }
        if let Some(l) = look.filter(|l| l.weight > 0.0 && l.bones.iter().all(|b| b.is_some_and(|b| b != 0))) {
            words[5] = l.weight.to_bits();
            for (i, b) in l.bones.iter().enumerate() {
                words[6 + i] = b.map_or(NO_BONE, |b| b as u32);
            }
            words[8..11].copy_from_slice(&l.point.to_array().map(f32::to_bits));
            words[11] = if l.two { 2 } else { 1 };
            words[12] = l.p4.0 as u32;
            words[13..16].copy_from_slice(&l.p4.1.to_array().map(f32::to_bits));
            for (i, lim) in l.limits.iter().enumerate() {
                words[16 + 3 * i..19 + 3 * i].copy_from_slice(&lim.map(f32::to_bits));
            }
            words[22] = l.drop.to_bits();
            words[23..26].copy_from_slice(&l.p3.to_array().map(f32::to_bits));
        }
        // A layer that sits out (its file not up yet) hands its region's opening on to the next one of the region.
        let mut k = 0;
        let mut open = false;
        for l in layers {
            open |= l.start;
            if k == MAX_SET {
                break;
            }
            if let Some(off) = lookup(l.src) {
                let at = HEAD + 4 * k;
                words[at] = off;
                words[at + 1] = l.frame.to_bits();
                words[at + 2] = l.weight.to_bits();
                words[at + 3] = l.over as u32 | (std::mem::take(&mut open) as u32) << 8;
                k += 1;
            }
        }
        words[2] = k as u32;
        self.jobs.extend(words);
    }

    /// Words registered but not yet on the GPU go up (under the frame copy budget, or all with `all`), whether or
    /// not anything is posed this frame: models wait for theirs before they are drawn.
    pub fn upload_keys(&mut self, gpu: &Gpu, encoder: &mut wgpu::CommandEncoder, all: bool) {
        let device = &gpu.device;
        // Only new words go up; a bigger buffer takes the old contents by a GPU copy.
        if !self.data.is_empty() || self.data_buf.is_none() {
            let need = ((self.uploaded + self.data.len()).max(4) * 4) as u64;
            if self.data_buf.as_ref().is_none_or(|b| b.size() < need) {
                let size = need.next_power_of_two().max(1 << 20);
                crate::client::perf::note(|| format!("anim keys buffer {size} bytes"));
                let buf = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("anim keys"),
                    size,
                    usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
                    mapped_at_creation: false,
                });
                if let Some(old) = &self.data_buf
                    && self.uploaded > 0
                {
                    encoder.copy_buffer_to_buffer(old, 0, &buf, 0, (self.uploaded * 4) as u64);
                }
                self.data_buf = Some(buf);
            }
            // As much of the tail as the frame's copy budget allows (render/upload.rs).
            if !self.data.is_empty() && (all || gpu.upload_room() > 0) {
                let n = if all { self.data.len() } else { (gpu.piece(self.data.len() as u64 * 4, 4) / 4) as usize };
                gpu.upload(n as u64 * 4, || {
                    gpu.queue.put(
                        self.data_buf.as_ref().unwrap(),
                        (self.uploaded * 4) as u64,
                        bytemuck::cast_slice(&self.data[..n]),
                    )
                });
                self.uploaded += n;
                self.data.drain(..n);
            }
        }
    }

    /// Uploads new keys (under the frame copy budget, or all of them with `all`) and this frame's jobs, then
    /// poses them into `pose` (the ZoneRenderer pose buffer).
    pub fn dispatch(&mut self, gpu: &Gpu, encoder: &mut wgpu::CommandEncoder, pose: &wgpu::Buffer, all: bool) {
        self.upload_keys(gpu, encoder, all);
        if self.jobs.is_empty() {
            return;
        }
        let device = &gpu.device;
        let n = self.jobs.len() / JOB_WORDS;
        let jsize = (self.jobs.len() * 4) as u64;
        if self.job_buf.as_ref().is_none_or(|(_, c)| *c < jsize) {
            let c = jsize.next_power_of_two().max(4096);
            self.job_buf = Some((
                device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("anim jobs"),
                    size: c,
                    usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                    mapped_at_creation: false,
                }),
                c,
            ));
        }
        let ssize = (n * SCRATCH * 16) as u64;
        if self.scratch.as_ref().is_none_or(|(_, c)| *c < ssize) {
            let c = ssize.next_power_of_two();
            self.scratch = Some((
                device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("anim scratch"),
                    size: c,
                    usage: wgpu::BufferUsages::STORAGE,
                    mapped_at_creation: false,
                }),
                c,
            ));
        }
        let (jb, _) = self.job_buf.as_ref().unwrap();
        gpu.queue.put(jb, 0, bytemuck::cast_slice(&self.jobs));
        let (data, scratch) = (self.data_buf.as_ref().unwrap(), &self.scratch.as_ref().unwrap().0);
        let group = self.group.get([data.clone(), jb.clone(), pose.clone(), scratch.clone()], || {
            device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("pose actors"),
                layout: &self.layout,
                entries: &[
                    wgpu::BindGroupEntry { binding: 0, resource: data.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 1, resource: jb.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 2, resource: pose.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 3, resource: scratch.as_entire_binding() },
                ],
            })
        });
        let mut pass = encoder
            .begin_compute_pass(&wgpu::ComputePassDescriptor { label: Some("pose actors"), timestamp_writes: None });
        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &group, &[]);
        pass.dispatch_workgroups(n as u32, 1, 1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dat::character::{Look, load_character, pose};

    /// The compute pass gives the CPU pose (and its cross-fade) for a Hume run blended from idle.
    #[test]
    fn gpu_pose_matches_cpu() {
        let Ok(index) = crate::dat::DatIndex::open(&crate::config::Config::load().ffxi_dir()) else { return };
        let look = Look { race: 1, face: 0, head: 0, body: 8, hands: 8, legs: 8, feet: 8, main: 0, sub: 0, range: 0 };
        let Ok(ch) = load_character(&index, &look) else { return };
        let ch = Arc::new(ch);
        let Ok(gpu) = Gpu::headless() else { return };
        let to: Vec<(&Animation, f32)> = ch.find_animations("run").into_iter().map(|a| (a, 3.37)).collect();
        let from: Vec<(&Animation, f32)> = ch.find_animations("idl").into_iter().map(|a| (a, 7.5)).collect();
        assert!(!to.is_empty() && !from.is_empty());
        check(&gpu, &ch, &to, &from, &[]);
        // Pugil idle: its keys flip sign between frames (the short-way lerp).
        let Ok(pugil) = crate::dat::npc::load_model(&index, 0x15c) else { return };
        let pugil = Arc::new(pugil);
        let idle: Vec<(&Animation, f32)> = pugil.find_animations("idl").into_iter().map(|a| (a, 4.5)).collect();
        assert!(!idle.is_empty());
        check(&gpu, &pugil, &idle, &[], &[]);
    }

    /// Nine's look (Mithra, two daggers on carry bones 96 / 98): the engaged run (file 47223's run1) keys the carry
    /// bones at rest, on the ground; drawn, each rides its grip (FUN_10029320), on the GPU too.
    #[test]
    fn drawn_weapons_ride_the_grips() {
        let Ok(index) = crate::dat::DatIndex::open(&crate::config::Config::load().ffxi_dir()) else { return };
        let look = Look {
            race: 7,
            face: 10,
            head: 0,
            body: 110,
            hands: 110,
            legs: 110,
            feet: 11,
            main: 430,
            sub: 379,
            range: 62,
        };
        let Ok(mut ch) = load_character(&index, &look) else { return };
        let Ok(d) = index.read(47223) else { return };
        let f = crate::dat::character::load_file(&d).unwrap();
        ch.animations.push(f.animations.iter().find(|a| a.name == "run1").expect("run1").clone());
        let ch = Arc::new(ch);
        let grips: Vec<(u16, u16)> = ch.grips.iter().flatten().copied().collect();
        assert_eq!(grips.len(), 2, "{:?}", ch.grips);
        let mut to: Vec<(&Animation, f32)> =
            ch.find_animations("run").into_iter().filter(|a| a.name != "run1").map(|a| (a, 4.0)).collect();
        to.push((ch.animations.last().unwrap(), 4.0));
        let loose = pose(&ch.skeleton, &to);
        let held = crate::dat::character::pose_held(&ch.skeleton, &to, &grips);
        for &(c, g) in &grips {
            let (c, g) = (c as usize, g as usize);
            println!("carry {c} on grip {g}: loose height {:.2}, held {:.2}", -loose[c].t.y, -held[c].t.y);
            assert!((held[c].t - held[g].t).length() < 1e-4 && held[c].q.dot(held[g].q).abs() > 0.9999);
            assert!(-loose[c].t.y < 0.2 && -held[c].t.y > 0.5);
        }
        let Ok(gpu) = Gpu::headless() else { return };
        check(&gpu, &ch, &to, &[], &grips);
    }

    fn posed(gpu: &Gpu, ch: &Arc<Character>, to: &[(&Animation, f32)], look: Option<HeadLook>) -> Vec<glam::Quat> {
        let n = ch.skeleton.bones.len().min(TABLE - 1);
        let mut ga = GpuAnim::new(gpu);
        ga.begin();
        ga.job(ch, &plain_layers(ch, to), [0.0; 2], 0, look, &[]);
        let size = (n * 48) as u64;
        let out = gpu.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let rb = gpu.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let mut enc = gpu.device.create_command_encoder(&Default::default());
        ga.dispatch(gpu, &mut enc, &out, true);
        enc.copy_buffer_to_buffer(&out, 0, &rb, 0, size);
        gpu.queue.submit([enc.finish()]);
        rb.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        gpu.device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None }).unwrap();
        let data = rb.slice(..).get_mapped_range().unwrap();
        let v: &[f32] = bytemuck::cast_slice(&data);
        (0..n).map(|i| glam::Quat::from_slice(&v[i * 12..i * 12 + 4])).collect()
    }

    /// Hume M idle looking far to one side: the neck turns about its 17.7 deg limit and the head, which carries
    /// the neck's turn, about 43 deg in all; a point straight ahead barely moves them.
    #[test]
    fn head_look_limits() {
        let Ok(index) = crate::dat::DatIndex::open(&crate::config::Config::load().ffxi_dir()) else { return };
        let Ok(gpu) = Gpu::headless() else { return };
        for race in 1..=8u8 {
            let look = Look { race, face: 0, head: 0, body: 8, hands: 8, legs: 8, feet: 8, main: 0, sub: 0, range: 0 };
            let Ok(ch) = load_character(&index, &look) else { return };
            let ch = Arc::new(ch);
            let idle: Vec<(&Animation, f32)> = ch.find_animations("idl").into_iter().map(|a| (a, 0.0)).collect();
            let pt = |k: usize| ch.skeleton.points[k];
            let hl = |point: glam::Vec3| HeadLook {
                bones: [Some(pt(3).0), Some(pt(7).0)],
                two: true,
                weight: 1.0,
                point,
                p3: pt(3).1,
                p4: pt(4),
                drop: 0.0,
                limits: ch.skeleton.look_limits,
            };
            let base = posed(&gpu, &ch, &idle, None);
            let side = posed(&gpu, &ch, &idle, Some(hl(glam::Vec3::new(0.0, -1.6, 20.0))));
            let ahead = posed(&gpu, &ch, &idle, Some(hl(glam::Vec3::new(20.0, -1.6, 0.0))));
            let turn = |a: &[glam::Quat], b: usize| (a[b] * base[b].inverse()).to_axis_angle().1.to_degrees();
            let (head, neck) = (pt(3).0 as usize, pt(7).0 as usize);
            println!(
                "race {race} side: head {:.1} neck {:.1}; ahead: head {:.1} neck {:.1}",
                turn(&side, head),
                turn(&side, neck),
                turn(&ahead, head),
                turn(&ahead, neck)
            );
            assert!((turn(&side, neck) - 17.7).abs() < 3.0, "race {race}");
            assert!((turn(&side, head) - 43.3).abs() < 5.0, "race {race}");
            assert!(turn(&ahead, head) < 15.0, "race {race}");
        }
    }

    /// The compute pass against the CPU poser: `to` alone (the latest track wins), and, with `from`, a queue mid
    /// blend: per region `from`'s chunk under `to`'s at weight 0.3, and `to`'s first chunk again as an overlay
    /// region at weight 0.4.
    fn check(
        gpu: &Gpu,
        ch: &Arc<Character>,
        to: &[(&Animation, f32)],
        from: &[(&Animation, f32)],
        grips: &[(u16, u16)],
    ) {
        use crate::dat::character::PoseLayer;
        let index_of = |a: &Animation| ch.animations.iter().position(|x| std::ptr::eq(x, a)).unwrap();
        let region = |a: &Animation| a.name.as_bytes()[3];
        let mut sets: Vec<(Vec<PoseLayer>, [f32; 2])> = Vec::new();
        sets.push((
            to.iter()
                .rev()
                .map(|&(anim, frame)| PoseLayer { anim, frame, weight: 1.0, start: true, over: 0 })
                .collect(),
            [0.0; 2],
        ));
        if !from.is_empty() {
            let mut v = Vec::new();
            for r in (b'0'..=b'4').rev() {
                let mut start = true;
                for (list, weight) in [(from, 1.0), (to, 0.3)] {
                    for &(anim, frame) in list.iter().filter(|(a, _)| region(a) == r) {
                        v.push(PoseLayer { anim, frame, weight, start: std::mem::take(&mut start), over: 0 });
                    }
                }
            }
            v.push(PoseLayer { anim: to[0].0, frame: to[0].1 + 2.0, weight: 1.0, start: true, over: 2 });
            sets.push((v, [0.0, 0.4]));
        }
        for (layers, over) in sets {
            let cpu = crate::dat::character::pose_layers(&ch.skeleton, &layers, over, grips);
            if over == [0.0; 2] {
                let plain = crate::dat::character::pose_held(&ch.skeleton, to, grips);
                assert!(cpu.iter().zip(&plain).all(|(a, b)| (a.t - b.t).length() < 1e-5), "plain layers");
            }
            let job: Vec<JobLayer> = layers
                .iter()
                .map(|l| JobLayer {
                    src: AnimSrc::Model(index_of(l.anim)),
                    frame: l.frame,
                    weight: l.weight,
                    start: l.start,
                    over: l.over,
                })
                .collect();
            let mut ga = GpuAnim::new(gpu);
            ga.begin();
            ga.job(ch, &job, over, 0, None, grips);
            let n = cpu.len().min(TABLE - 1);
            let size = (n * 48) as u64;
            let out = gpu.device.create_buffer(&wgpu::BufferDescriptor {
                label: None,
                size,
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });
            let rb = gpu.device.create_buffer(&wgpu::BufferDescriptor {
                label: None,
                size,
                usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            let mut enc = gpu.device.create_command_encoder(&Default::default());
            ga.dispatch(gpu, &mut enc, &out, true);
            enc.copy_buffer_to_buffer(&out, 0, &rb, 0, size);
            gpu.queue.submit([enc.finish()]);
            rb.slice(..).map_async(wgpu::MapMode::Read, |_| {});
            gpu.device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None }).unwrap();
            let data = rb.slice(..).get_mapped_range().unwrap();
            let v: &[f32] = bytemuck::cast_slice(&data);
            let mut worst = 0f32;
            for (i, b) in cpu.iter().take(n).enumerate() {
                let g = &v[i * 12..i * 12 + 12];
                let gq = glam::Quat::from_slice(&g[0..4]);
                let dq = (gq - b.q).length().min((gq + b.q).length());
                let dp = (glam::Vec3::from_slice(&g[4..7]) - b.t).length();
                let ds = (glam::Vec3::from_slice(&g[8..11]) - b.s).length();
                worst = worst.max(dq).max(dp).max(ds);
            }
            assert!(worst < 1e-3, "{} layers, overlay {over:?}: worst difference {worst}", layers.len());
        }
    }
}
