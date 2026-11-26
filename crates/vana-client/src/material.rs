//! Material maps (ours, not retail): a normal map and a roughness / metal map per texture, from a material pack in
//! `<data>/materials` (made by `mat-pack`, texpack.rs). The pack indexes textures by Texture::content_key, so one map
//! serves the stock image and every pack copy it was indexed for.
//!
//! `index.bin`: "VMIX", u32 count, then count x (u64 content key, u64 map key), sorted by content key.
//! `maps/<first two hex digits>/<map key>.vmat`: "VMAT", u32 version (1), u32 width, u32 height, u32 levels, then the
//! normal map's BC5 levels (x, y; DirectX: y down the image), then the roughness / metal map's BC5 levels.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, RwLock, Weak};

pub const INDEX_MAGIC: &[u8; 4] = b"VMIX";
pub const MAP_MAGIC: &[u8; 4] = b"VMAT";

/// One texture's maps, both BC5 with `levels` mips from `width` x `height` (each a multiple of 4).
pub struct Material {
    pub width: u32,
    pub height: u32,
    pub levels: u32,
    pub normal: Vec<u8>,
    pub rough_metal: Vec<u8>,
    /// The two maps on the GPU (normal, roughness / metal), uploaded once for every texture that shares them.
    pub gpu: std::sync::OnceLock<(wgpu::TextureView, wgpu::TextureView)>,
}

impl Material {
    /// The byte size of a BC5 chain.
    pub fn chain_size(w: u32, h: u32, levels: u32) -> usize {
        (0..levels).map(|l| level_size(w >> l, h >> l)).sum()
    }

    pub fn parse(b: &[u8]) -> Option<Material> {
        let u = |at: usize| Some(u32::from_le_bytes(b.get(at..at + 4)?.try_into().ok()?));
        if b.get(..4)? != MAP_MAGIC || u(4)? != 1 {
            return None;
        }
        let (width, height, levels) = (u(8)?, u(12)?, u(16)?);
        let ok = levels >= 1
            && width % 4 == 0
            && height % 4 == 0
            && (width >> (levels - 1)) >= 4
            && (height >> (levels - 1)) >= 4;
        if !ok {
            return None;
        }
        let n = Self::chain_size(width, height, levels);
        let normal = b.get(20..20 + n)?.to_vec();
        let rough_metal = b.get(20 + n..20 + 2 * n)?.to_vec();
        Some(Material { width, height, levels, normal, rough_metal, gpu: Default::default() })
    }

    pub fn write(&self) -> Vec<u8> {
        let mut b = Vec::with_capacity(20 + self.normal.len() + self.rough_metal.len());
        b.extend_from_slice(MAP_MAGIC);
        for v in [1, self.width, self.height, self.levels] {
            b.extend_from_slice(&u32::to_le_bytes(v));
        }
        b.extend_from_slice(&self.normal);
        b.extend_from_slice(&self.rough_metal);
        b
    }
}

/// A BC5 level: 16 bytes a 4 x 4 block.
pub fn level_size(w: u32, h: u32) -> usize {
    (w.div_ceil(4) * h.div_ceil(4) * 16) as usize
}

pub fn map_path(dir: &Path, key: u64) -> PathBuf {
    let k = format!("{key:016x}");
    dir.join("maps").join(&k[..2]).join(format!("{k}.vmat"))
}

struct Pack {
    dir: PathBuf,
    index: Vec<(u64, u64)>,
    /// Maps already read, shared by every texture holding them.
    loaded: Mutex<HashMap<u64, Weak<Material>>>,
}

impl Pack {
    fn open(dir: &Path) -> Option<Pack> {
        let b = std::fs::read(dir.join("index.bin")).ok()?;
        if b.get(..4)? != INDEX_MAGIC {
            return None;
        }
        let n = u32::from_le_bytes(b.get(4..8)?.try_into().ok()?) as usize;
        let body = b.get(8..8 + n * 16)?;
        let index = body
            .as_chunks::<16>()
            .0
            .iter()
            .map(|e| (u64::from_le_bytes(e[..8].try_into().unwrap()), u64::from_le_bytes(e[8..].try_into().unwrap())))
            .collect();
        Some(Pack { dir: dir.to_path_buf(), index, loaded: Default::default() })
    }

    fn get(&self, content: u64) -> Option<Arc<Material>> {
        let at = self.index.binary_search_by_key(&content, |e| e.0).ok()?;
        let key = self.index[at].1;
        if let Some(m) = self.loaded.lock().unwrap().get(&key).and_then(Weak::upgrade) {
            return Some(m);
        }
        let m = Arc::new(Material::parse(&std::fs::read(map_path(&self.dir, key)).ok()?)?);
        self.loaded.lock().unwrap().insert(key, Arc::downgrade(&m));
        Some(m)
    }
}

/// The open pack while config `material_maps` is on (and the pack exists).
static PACK: RwLock<Option<Arc<Pack>>> = RwLock::new(None);

/// The pack folder; VANA_MATERIALS points elsewhere (tests).
pub fn dir() -> PathBuf {
    std::env::var_os("VANA_MATERIALS").map_or_else(|| crate::config::data_dir().join("materials"), PathBuf::from)
}

/// Follows the setting: opens the pack when turned on (once), drops it when off. Takes effect at the next load.
pub fn set_enabled(on: bool) {
    let on = on && gpu_supported();
    let open = PACK.read().unwrap().is_some();
    // A missing pack is looked for once per turn on (or after `reopen`), not every frame.
    if on == open || (on && TRIED.swap(true, std::sync::atomic::Ordering::Relaxed)) {
        if !on {
            TRIED.store(false, std::sync::atomic::Ordering::Relaxed);
        }
        return;
    }
    let pack = if on {
        let p = Pack::open(&dir());
        match &p {
            Some(p) => log::info!("material maps: {} textures indexed in {}", p.index.len(), dir().display()),
            None => log::warn!("material maps: no pack in {}", dir().display()),
        }
        p.map(Arc::new)
    } else {
        None
    };
    // A pack that is missing stays "open" as None: retried on the next turn on.
    *PACK.write().unwrap() = pack;
}

/// Set once a turn on has looked for the pack (cleared by turning off and by `reopen`).
static TRIED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// After the pack was installed or updated: closed, and opened again by the next `set_enabled(true)`.
pub fn reopen() {
    *PACK.write().unwrap() = None;
    TRIED.store(false, std::sync::atomic::Ordering::Relaxed);
}

/// FFXI_MATERIAL_STRENGTH for the offscreen tools (default 1).
pub fn env_strength() -> f32 {
    std::env::var("FFXI_MATERIAL_STRENGTH").ok().and_then(|v| v.parse().ok()).unwrap_or(1.0)
}

/// Whether a pack is open (the setting on, the GPU able to sample the maps, and the pack found).
pub fn available() -> bool {
    PACK.read().unwrap().is_some()
}

/// Whether the GPU samples the maps' BC5 (TEXTURE_COMPRESSION_BC: not on GL / GLES or most mobile Vulkan); set when
/// the device opens. Without it the pack stays closed and Settings shows the row as Unavailable.
static GPU_BC: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

pub fn set_gpu_support(bc: bool) {
    GPU_BC.store(bc, std::sync::atomic::Ordering::Relaxed);
    if !bc {
        *PACK.write().unwrap() = None;
    }
}

pub fn gpu_supported() -> bool {
    GPU_BC.load(std::sync::atomic::Ordering::Relaxed)
}

/// Gives each texture its maps, when the pack has them.
/// Returns how many have maps (0 while the pack is closed).
pub fn attach(textures: &mut [crate::dat::zone::Texture]) -> usize {
    let Some(pack) = PACK.read().unwrap().clone() else { return 0 };
    for t in textures.iter_mut() {
        t.material = pack.get(t.content_key());
    }
    textures.iter().filter(|t| t.material.is_some()).count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn map_round_trip() {
        let n = Material::chain_size(16, 8, 2);
        assert_eq!(n, 8 * 16 + 2 * 16);
        let m = Material {
            width: 16,
            height: 8,
            levels: 2,
            normal: vec![1; n],
            rough_metal: vec![2; n],
            gpu: Default::default(),
        };
        let back = Material::parse(&m.write()).unwrap();
        assert_eq!((back.width, back.height, back.levels), (16, 8, 2));
        assert_eq!(back.normal, m.normal);
        assert_eq!(back.rough_metal, m.rough_metal);
        // A level under 4 texels is refused.
        let bad =
            Material { width: 8, height: 8, levels: 3, normal: vec![], rough_metal: vec![], gpu: Default::default() };
        assert!(Material::parse(&bad.write()).is_none());
    }
}
