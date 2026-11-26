//! The engine library (docs/upscaler-engine.md has the ABI): a native library fed the frame's inputs as raw Vulkan
//! handles, for Upscaling: External (vana_upscale_dispatch) and Neural Rendering (vana_nr_dispatch, before the
//! upscale). wgpu may not mix raw and wgpu recording in one encoder, so the frame's work so far is submitted, the
//! engine records into a raw command buffer of its own (submitted next, in order), and the frame goes on in a fresh
//! encoder.

use super::{Inputs, Upscaler};
use crate::render::Gpu;

/// One image handed over (VkImage, VkImageView, VkFormat, VkImageLayout as left by the last use).
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct Image {
    pub image: u64,
    pub view: u64,
    pub format: u32,
    pub layout: u32,
    pub width: u32,
    pub height: u32,
}

/// The frame as the engine gets it (ABI version 1).
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct Frame {
    pub version: u32,
    pub queue_family: u32,
    pub instance: u64,
    pub physical_device: u64,
    pub device: u64,
    pub queue: u64,
    /// Recording; the engine records into it, does not begin, end or submit it.
    pub command_buffer: u64,
    pub color: Image,
    pub depth: Image,
    pub motion: Image,
    pub reactive: Image,
    pub composition: Image,
    /// The engine writes the upscaled linear colour here (output size).
    pub output: Image,
    pub render_size: [u32; 2],
    pub output_size: [u32; 2],
    pub jitter: [f32; 2],
    pub reset: u32,
    pub reversed_z: u32,
    pub frame_time_ms: f32,
    pub near: f32,
    pub far: f32,
    pub fov_y: f32,
    pub meters_per_unit: f32,
    pub exposure: f32,
    pub sharpness: f32,
}

pub const ABI_VERSION: u32 = 1;

/// Puts every input and the output in a known layout before the handover: sampled colour inputs
/// SHADER_READ_ONLY_OPTIMAL, depth DEPTH_STENCIL_READ_ONLY_OPTIMAL, the output GENERAL.
const SETTLE: &str = r#"
@group(0) @binding(0) var a: texture_2d<f32>;
@group(0) @binding(1) var b: texture_2d<f32>;
@group(0) @binding(2) var c: texture_2d<f32>;
@group(0) @binding(3) var d: texture_2d<f32>;
@group(0) @binding(4) var z: texture_depth_2d;
@group(0) @binding(5) var o: texture_storage_2d<rgba16float, write>;
@compute @workgroup_size(1)
fn main() {
    let s = textureLoad(a, vec2<i32>(0), 0) + textureLoad(b, vec2<i32>(0), 0) + textureLoad(c, vec2<i32>(0), 0)
        + textureLoad(d, vec2<i32>(0), 0) + vec4<f32>(textureLoad(z, vec2<i32>(0), 0));
    textureStore(o, vec2<i32>(0), s * 0.0);
}
"#;

type Dispatch = unsafe extern "C" fn(*const Frame) -> i32;

/// The engine library's path: VANA_UPSCALE_ENGINE, else upscale-engine.so / .dll in the data folder.
pub fn library_path() -> std::path::PathBuf {
    if let Some(p) = std::env::var_os("VANA_UPSCALE_ENGINE") {
        return p.into();
    }
    let name = if cfg!(windows) { "upscale-engine.dll" } else { "upscale-engine.so" };
    crate::config::data_dir().join(name)
}

/// The loaded engine library and its entry points: `vana_upscale_dispatch` (an upscaler, Upscaling: External) and
/// `vana_nr_dispatch` (neural rendering on the render-size colour before the upscale).
pub struct Engine {
    #[cfg(any(target_os = "linux", windows))]
    _lib: libloading::Library,
    pub upscale: Option<Dispatch>,
    pub nr: Option<Dispatch>,
    settle: wgpu::ComputePipeline,
}

/// Entry points of the library at `library_path` without a device (Settings asks before any frame): (upscale, nr).
#[cfg(any(target_os = "linux", windows))]
pub fn probe() -> Result<(bool, bool), String> {
    let path = library_path();
    if !path.exists() {
        return Err(format!("no engine at {}", path.display()));
    }
    // Safety: loading runs the library's initialisers; the path is the user's own engine.
    let lib = unsafe { libloading::Library::new(&path) }.map_err(|e| format!("{}: {e}", path.display()))?;
    // Safety: only looked up, not called.
    let has = |n: &[u8]| unsafe { lib.get::<Dispatch>(n) }.is_ok();
    Ok((has(b"vana_upscale_dispatch\0"), has(b"vana_nr_dispatch\0")))
}

#[cfg(not(any(target_os = "linux", windows)))]
pub fn probe() -> Result<(bool, bool), String> {
    Err("the engine runs on Vulkan only (Linux, Windows)".into())
}

/// The engine's calls for the player (no device; safe beside vana_nr_dispatch): its release, the model's state,
/// checking NVIDIA's DLL and making the model from it. Each loads the library at `library_path` for the call. The
/// engine's sentences come back as it wrote them.
#[cfg(any(target_os = "linux", windows))]
pub mod tools {
    use super::library_path;

    /// The sentence buffer's size.
    const MSG: usize = 1024;

    type Version = unsafe extern "C" fn() -> *const std::ffi::c_char;
    type Status = unsafe extern "C" fn(*mut std::ffi::c_char, u32) -> i32;
    type Check = unsafe extern "C" fn(*const std::ffi::c_char, *mut std::ffi::c_char, u32) -> i32;
    type Progress = unsafe extern "C" fn(f32, *mut std::ffi::c_void);
    type Make = unsafe extern "C" fn(
        *const std::ffi::c_char,
        Option<Progress>,
        *mut std::ffi::c_void,
        *mut std::ffi::c_char,
        u32,
    ) -> i32;

    fn open() -> Result<libloading::Library, String> {
        let path = library_path();
        if !path.exists() {
            return Err(format!("no engine at {}", path.display()));
        }
        // Safety: loading runs the library's initialisers; the path is the user's engine.
        unsafe { libloading::Library::new(&path) }.map_err(|e| format!("{}: {e}", path.display()))
    }

    fn sentence(buf: &[u8]) -> String {
        let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
        String::from_utf8_lossy(&buf[..end]).trim().to_string()
    }

    fn c_path(path: &std::path::Path) -> Result<std::ffi::CString, String> {
        let s = path.to_str().ok_or_else(|| format!("{} is not UTF-8", path.display()))?;
        std::ffi::CString::new(s).map_err(|_| format!("{} has a NUL", path.display()))
    }

    /// `vana_nr_version()` ("vana-client/1.0.16"); None without a library or without the export (a player's build).
    pub fn version() -> Option<String> {
        let lib = open().ok()?;
        // Safety: the export's signature (docs/upscaler-engine.md); it returns a static string.
        unsafe {
            let f = lib.get::<Version>(b"vana_nr_version\0").ok()?;
            let p = f();
            (!p.is_null()).then(|| std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned())
        }
    }

    /// `vana_nr_model_status`: 0 ready, 1 no model, 2 its files can't be written; with the engine's sentence.
    pub fn model_status() -> Result<(i32, String), String> {
        let lib = open()?;
        let mut buf = vec![0u8; MSG];
        // Safety: the export's signature; the buffer is MSG bytes.
        let code = unsafe {
            let f = lib.get::<Status>(b"vana_nr_model_status\0").map_err(|e| e.to_string())?;
            f(buf.as_mut_ptr().cast(), MSG as u32)
        };
        Ok((code, sentence(&buf)))
    }

    /// `vana_nr_check_dll`: whether the file can make the model, with the engine's sentence.
    pub fn check_dll(path: &std::path::Path) -> Result<(bool, String), String> {
        let lib = open()?;
        let p = c_path(path)?;
        let mut buf = vec![0u8; MSG];
        // Safety: the export's signature; the path is NUL-terminated and the buffer MSG bytes.
        let code = unsafe {
            let f = lib.get::<Check>(b"vana_nr_check_dll\0").map_err(|e| e.to_string())?;
            f(p.as_ptr(), buf.as_mut_ptr().cast(), MSG as u32)
        };
        Ok((code == 0, sentence(&buf)))
    }

    unsafe extern "C" fn tick(fraction: f32, user: *mut std::ffi::c_void) {
        // Safety: `user` is make_model's `&mut &mut dyn FnMut(f32)` for the call's length.
        let f = unsafe { &mut *(user as *mut &mut dyn FnMut(f32)) };
        f(fraction);
    }

    /// `vana_nr_make_model`: makes the model from the file (blocks for seconds), `progress` with 0..1; whether it was
    /// made, with the engine's sentence. Off the render thread.
    pub fn make_model(path: &std::path::Path, progress: &mut dyn FnMut(f32)) -> Result<(bool, String), String> {
        let lib = open()?;
        let p = c_path(path)?;
        let mut buf = vec![0u8; MSG];
        let mut cb: &mut dyn FnMut(f32) = progress;
        // Safety: the export's signature; `tick` gets `cb` back as user data while the call runs.
        let code = unsafe {
            let f = lib.get::<Make>(b"vana_nr_make_model\0").map_err(|e| e.to_string())?;
            f(p.as_ptr(), Some(tick), (&mut cb as *mut &mut dyn FnMut(f32)).cast(), buf.as_mut_ptr().cast(), MSG as u32)
        };
        Ok((code == 0, sentence(&buf)))
    }
}

/// No engine off Linux and Windows.
#[cfg(not(any(target_os = "linux", windows)))]
pub mod tools {
    const NONE: &str = "the engine runs on Vulkan only (Linux, Windows)";

    pub fn version() -> Option<String> {
        None
    }

    pub fn model_status() -> Result<(i32, String), String> {
        Err(NONE.into())
    }

    pub fn check_dll(_: &std::path::Path) -> Result<(bool, String), String> {
        Err(NONE.into())
    }

    pub fn make_model(_: &std::path::Path, _: &mut dyn FnMut(f32)) -> Result<(bool, String), String> {
        Err(NONE.into())
    }
}

impl Engine {
    #[cfg(any(target_os = "linux", windows))]
    pub fn load(gpu: &Gpu) -> Result<Self, String> {
        super::supported(gpu)?;
        if gpu.adapter.get_info().backend != wgpu::Backend::Vulkan {
            return Err("the engine needs the Vulkan backend".into());
        }
        let path = library_path();
        // Safety: loading runs the library's initialisers; the path is the user's own engine.
        let lib = unsafe { libloading::Library::new(&path) }.map_err(|e| format!("{}: {e}", path.display()))?;
        // Safety: the symbols are this ABI's functions (docs/upscaler-engine.md).
        let sym = |n: &[u8]| unsafe { lib.get::<Dispatch>(n) }.map(|s| *s).ok();
        let (upscale, nr) = (sym(b"vana_upscale_dispatch\0"), sym(b"vana_nr_dispatch\0"));
        if upscale.is_none() && nr.is_none() {
            return Err(format!("{}: neither vana_upscale_dispatch nor vana_nr_dispatch", path.display()));
        }
        let module = gpu.device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("upscale settle"),
            source: wgpu::ShaderSource::Wgsl(SETTLE.into()),
        });
        let settle = gpu.device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("upscale settle"),
            layout: None,
            module: &module,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });
        log::info!("engine {}: upscale {}, neural rendering {}", path.display(), upscale.is_some(), nr.is_some());
        Ok(Engine { _lib: lib, upscale, nr, settle })
    }

    #[cfg(not(any(target_os = "linux", windows)))]
    pub fn load(_gpu: &Gpu) -> Result<Self, String> {
        Err("the engine runs on Vulkan only (Linux, Windows)".into())
    }

    /// Hands the inputs and `out` (GENERAL) to `f`: the frame so far submitted, the engine's command buffer next,
    /// and `encoder` a fresh one after. True when the engine returned 0.
    #[cfg(any(target_os = "linux", windows))]
    pub fn run(
        &self,
        gpu: &Gpu,
        encoder: &mut wgpu::CommandEncoder,
        inp: &Inputs,
        out: &wgpu::Texture,
        f: Dispatch,
    ) -> bool {
        use ash::vk::Handle;
        use wgpu::hal::api::Vulkan;
        let v = |t: &wgpu::Texture| t.create_view(&Default::default());
        let (color, motion, reactive, composition, output) =
            (v(inp.color), v(inp.motion), v(inp.reactive), v(inp.composition), v(out));
        let depth = inp
            .depth
            .create_view(&wgpu::TextureViewDescriptor { aspect: wgpu::TextureAspect::DepthOnly, ..Default::default() });
        let group = gpu.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("upscale settle"),
            layout: &self.settle.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&color) },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&motion) },
                wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::TextureView(&reactive) },
                wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::TextureView(&composition) },
                wgpu::BindGroupEntry { binding: 4, resource: wgpu::BindingResource::TextureView(&depth) },
                wgpu::BindGroupEntry { binding: 5, resource: wgpu::BindingResource::TextureView(&output) },
            ],
        });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("upscale settle"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.settle);
            pass.set_bind_group(0, &group, &[]);
            pass.dispatch_workgroups(1, 1, 1);
        }
        // The frame so far goes first; the engine's buffer after it.
        let prior = std::mem::replace(encoder, gpu.device.create_command_encoder(&Default::default()));
        gpu.queue.submit([prior.finish()]);
        let mut frame = Frame {
            version: ABI_VERSION,
            color: image(inp.color, &color, SHADER_READ_ONLY_OPTIMAL),
            depth: image(inp.depth, &depth, DEPTH_STENCIL_READ_ONLY_OPTIMAL),
            motion: image(inp.motion, &motion, SHADER_READ_ONLY_OPTIMAL),
            reactive: image(inp.reactive, &reactive, SHADER_READ_ONLY_OPTIMAL),
            composition: image(inp.composition, &composition, SHADER_READ_ONLY_OPTIMAL),
            output: image(out, &output, GENERAL),
            render_size: inp.render,
            output_size: inp.output,
            jitter: inp.jitter,
            reset: inp.reset as u32,
            reversed_z: inp.reversed_z as u32,
            frame_time_ms: inp.dt_ms,
            near: inp.near,
            far: inp.far,
            fov_y: inp.fov_y,
            meters_per_unit: inp.meters_per_unit,
            exposure: inp.exposure,
            sharpness: inp.sharpness,
            ..Default::default()
        };
        // Safety: read-only handle queries; wgpu keeps owning everything.
        unsafe {
            if let Some(d) = gpu.device.as_hal::<Vulkan>() {
                frame.device = d.raw_device().handle().as_raw();
                frame.physical_device = d.raw_physical_device().as_raw();
                frame.queue = d.raw_queue().as_raw();
                frame.queue_family = d.queue_family_index();
                frame.instance = d.shared_instance().raw_instance().handle().as_raw();
            }
        }
        let mut raw =
            gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("upscale engine") });
        // Safety: the engine records into the open buffer only, and leaves every image in the layout it got.
        let status = unsafe {
            raw.as_hal_mut::<Vulkan, _, _>(|e| {
                let e = e?;
                frame.command_buffer = e.raw_handle().as_raw();
                Some(f(&frame))
            })
        };
        gpu.queue.submit([raw.finish()]);
        if status != Some(0) {
            log::debug!("engine returned {status:?}");
        }
        status == Some(0)
    }

    #[cfg(not(any(target_os = "linux", windows)))]
    pub fn run(&self, _: &Gpu, _: &mut wgpu::CommandEncoder, _: &Inputs, _: &wgpu::Texture, _: Dispatch) -> bool {
        false
    }
}

/// VkFormat of the formats handed over.
fn vk_format(f: wgpu::TextureFormat) -> u32 {
    use wgpu::TextureFormat as F;
    match f {
        F::Rgba16Float => 97,
        F::Rg16Float => 83,
        F::R8Unorm => 9,
        F::Depth32Float => 126,
        _ => 0,
    }
}

const SHADER_READ_ONLY_OPTIMAL: u32 = 5;
const DEPTH_STENCIL_READ_ONLY_OPTIMAL: u32 = 4;
const GENERAL: u32 = 1;

#[cfg(any(target_os = "linux", windows))]
fn image(tex: &wgpu::Texture, view: &wgpu::TextureView, layout: u32) -> Image {
    use ash::vk::Handle as _;
    use wgpu::hal::api::Vulkan;
    // Safety: the handles are only read; wgpu keeps owning them.
    let (image, view) = unsafe {
        (
            tex.as_hal::<Vulkan>().map_or(0, |t| t.raw_handle().as_raw()),
            view.as_hal::<Vulkan>().map_or(0, |v| v.raw_handle().as_raw()),
        )
    };
    Image { image, view, format: vk_format(tex.format()), layout, width: tex.width(), height: tex.height() }
}

/// A colour target the engine writes (STORAGE for the settle, TEXTURE for what reads it after).
pub fn output_texture(gpu: &Gpu, label: &str, size: [u32; 2]) -> wgpu::Texture {
    gpu.device.create_texture(&wgpu::TextureDescriptor {
        label: Some(label),
        size: wgpu::Extent3d { width: size[0].max(1), height: size[1].max(1), depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: super::COLOR_FORMAT,
        usage: wgpu::TextureUsages::STORAGE_BINDING
            | wgpu::TextureUsages::TEXTURE_BINDING
            | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    })
}

/// Upscaling: External, through the engine's vana_upscale_dispatch.
pub struct External {
    engine: std::sync::Arc<Engine>,
    output: Option<wgpu::Texture>,
}

impl External {
    pub fn new(engine: std::sync::Arc<Engine>) -> Result<Self, String> {
        if engine.upscale.is_none() {
            return Err("the engine has no vana_upscale_dispatch".into());
        }
        Ok(External { engine, output: None })
    }
}

impl Upscaler for External {
    fn name(&self) -> &'static str {
        "external"
    }

    fn dispatch(&mut self, gpu: &Gpu, encoder: &mut wgpu::CommandEncoder, inp: &Inputs) -> Option<wgpu::TextureView> {
        let f = self.engine.upscale?;
        if self.output.as_ref().is_none_or(|t| [t.width(), t.height()] != inp.output) {
            self.output = Some(output_texture(gpu, "upscale external output", inp.output));
        }
        let out = self.output.as_ref()?;
        self.engine.run(gpu, encoder, inp, out, f).then(|| out.create_view(&Default::default()))
    }
}

#[cfg(all(test, any(target_os = "linux", windows)))]
mod tests {
    /// The engine's player calls on a real engine and DLL (VANA_NR_TEST_SO: a copy of the engine in a scratch folder,
    /// its nr/ written beside it; VANA_NR_TEST_DLL: nvngx_dlssnr.dll or its zip). Skipped without them.
    #[test]
    fn engine_tools() {
        let (Some(so), Some(dll)) = (std::env::var_os("VANA_NR_TEST_SO"), std::env::var_os("VANA_NR_TEST_DLL")) else {
            return;
        };
        // Safety: set before the calls read it; only this test sets it.
        unsafe { std::env::set_var("VANA_UPSCALE_ENGINE", &so) };
        let v = super::tools::version().expect("vana_nr_version");
        assert!(v.starts_with("vana-client/"), "{v}");
        let (code, msg) = super::tools::model_status().unwrap();
        eprintln!("before: {code} {msg}");
        let (ok, msg) = super::tools::check_dll(std::path::Path::new(&dll)).unwrap();
        assert!(ok, "{msg}");
        let (bad, why) = super::tools::check_dll(std::path::Path::new(&so)).unwrap();
        assert!(!bad && !why.is_empty(), "{why}");
        let mut seen = Vec::new();
        let (made, msg) = super::tools::make_model(std::path::Path::new(&dll), &mut |f| seen.push(f)).unwrap();
        assert!(made, "{msg}");
        assert!(!seen.is_empty() && seen.windows(2).all(|w| w[0] <= w[1]), "{seen:?}");
        let (code, msg) = super::tools::model_status().unwrap();
        assert_eq!(code, 0, "{msg}");
        eprintln!("version {v}; check: {msg}; progress {} calls", seen.len());
    }
}
