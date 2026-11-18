//! Native replacement for FFXISetup.exe + FINAL_FANTASY_XI.msi: unpacks the game data.
//! PlayOnline, DirectX and the registry are Windows runtime concerns and are skipped; of the PlayOnline Viewer only
//! the name dictionary the character creator reads is copied (poldic.rs).

use crate::cabx;
use crate::msi_db::{Database, DirResolver};
use anyhow::{Context, Result, anyhow, bail};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

const PACKAGE_DIR: &str = "FFXIFullSetup_US";
const FFXI_MSI: &str = "FINAL_FANTASY_XI/FINAL_FANTASY_XI.msi";
const POL_MSI: &str = "PlayOnline/PlayOnlineViewer.msi";
/// The viewer's dictionary folder under its INSTALLDIR (the "PlayOnline" folder), as `DirResolver` writes it.
const VIEWER_DIC_DIR: &str = "SquareEnix\\PlayOnlineViewer\\data\\dic\\";

#[derive(Default)]
pub struct Progress {
    pub phase: Mutex<String>,
    pub done: AtomicU64,
    pub total: AtomicU64,
}

impl Progress {
    fn begin(&self, phase: impl Into<String>, total: u64) {
        *self.phase.lock().unwrap() = phase.into();
        self.done.store(0, Ordering::Relaxed);
        self.total.store(total, Ordering::Relaxed);
    }

    pub fn fraction(&self) -> f32 {
        let total = self.total.load(Ordering::Relaxed);
        if total == 0 { 0.0 } else { self.done.load(Ordering::Relaxed) as f32 / total as f32 }
    }
}

pub struct Options {
    /// FFXIFullSetup_US.part1.exe, or a folder it was already extracted into.
    pub source: PathBuf,
    pub game_dir: PathBuf,
    pub staging: PathBuf,
    pub verify: bool,
    pub keep_staging: bool,
}

/// Finds the extracted package folder under `dir`, if there is one.
fn package_root(dir: &Path) -> Option<PathBuf> {
    [dir.to_path_buf(), dir.join(PACKAGE_DIR)].into_iter().find(|d| d.join(FFXI_MSI).is_file())
}

/// Extracts the wanted files from the multi-volume RAR self-extractor; the package folder they land in.
fn unpack_rar(
    first_volume: &Path,
    staging: &Path,
    progress: &Progress,
    wanted: impl Fn(&Path) -> bool,
) -> Result<PathBuf> {
    let mut total = 0;
    let mut listing = unrar::Archive::new(first_volume).open_for_listing().context("opening RAR archive")?;
    while let Some(Ok(entry)) = listing.next() {
        if entry.is_file() && wanted(&entry.filename) && !entry.is_split_before() {
            total += entry.unpacked_size;
        }
    }
    progress.begin("Unpacking installer archive", total);

    std::fs::create_dir_all(staging)?;
    let mut archive = unrar::Archive::new(first_volume).open_for_processing()?;
    while let Some(header) = archive.read_header()? {
        let entry = header.entry();
        archive = if entry.is_file() && wanted(&entry.filename) {
            let (name, size) = (entry.filename.clone(), entry.unpacked_size);
            log::info!("unpacking {}", name.display());
            *progress.phase.lock().unwrap() =
                format!("Unpacking {}", name.file_name().unwrap_or_default().to_string_lossy());
            let next = header.extract_with_base(staging)?;
            progress.done.fetch_add(size, Ordering::Relaxed);
            next
        } else {
            header.skip()?
        };
    }
    Ok(staging.join(PACKAGE_DIR))
}

/// Copies the name dictionary ("entryz.dic") out of PlayOnlineViewer.msi into the game folder, where the Windows
/// layout has it (poldic::name_dic_path). The package's one cabinet is a stream inside the MSI.
pub fn copy_name_dic(msi: &Path, game_dir: &Path, verify: bool) -> Result<PathBuf> {
    let (db, mut pkg) = Database::open(msi)?;
    // The row the viewer installs into its data\dic folder, as install() picks rows.
    let resolver = DirResolver::new(&db, HashMap::from([("INSTALLDIR".to_string(), String::new())]));
    let row = db
        .files
        .iter()
        .find(|f| {
            f.name.eq_ignore_ascii_case(crate::poldic::NAME_DIC)
                && db.component_installed(&f.component)
                && db
                    .components
                    .get(&f.component)
                    .and_then(|c| resolver.resolve(&c.directory).ok())
                    .is_some_and(|d| d.eq_ignore_ascii_case(VIEWER_DIC_DIR))
        })
        .ok_or_else(|| anyhow!("{} holds no {}", msi.display(), crate::poldic::NAME_DIC))?;
    let dest = crate::poldic::name_dic_path(game_dir);
    for media in &db.media {
        let Some(stream) = media.cabinet.strip_prefix('#') else { continue };
        let cab = pkg.read_stream(stream).with_context(|| format!("opening {stream} in {}", msi.display()))?;
        let done = cabx::extract_all(cab, |name| (name == row.key).then(|| dest.clone()), |_| {})
            .with_context(|| format!("extracting {stream} of {}", msi.display()))?;
        let Some(item) = done.first() else { continue };
        if verify && db.hashes.get(&item.name).is_some_and(|want| *want != item.md5) {
            std::fs::remove_file(&dest).ok();
            bail!("{} failed its MD5 check", crate::poldic::NAME_DIC);
        }
        return Ok(dest);
    }
    bail!("no cabinet of {} holds {}", msi.display(), crate::poldic::NAME_DIC)
}

/// The name dictionary alone, for an install made before the installer copied it. `source` is the installer
/// (FFXIFullSetup_US.part1.exe), a folder it was extracted into, or PlayOnlineViewer.msi itself.
pub fn install_name_dic(source: &Path, game_dir: &Path, staging: &Path, progress: &Progress) -> Result<PathBuf> {
    let direct = [source.to_path_buf(), source.join(POL_MSI), source.join(PACKAGE_DIR).join(POL_MSI)]
        .into_iter()
        .find(|p| p.is_file() && p.extension().is_some_and(|e| e.eq_ignore_ascii_case("msi")));
    if let Some(msi) = direct {
        return copy_name_dic(&msi, game_dir, true);
    }
    if !source.is_file() {
        bail!("{} is neither the installer, an extracted copy of it, nor {POL_MSI}", source.display());
    }
    let pol = Path::new(PACKAGE_DIR).join(POL_MSI);
    let root = unpack_rar(source, staging, progress, |name| name == pol)?;
    let copied = copy_name_dic(&root.join(POL_MSI), game_dir, true);
    std::fs::remove_dir_all(staging).ok();
    copied
}

pub fn install(opts: &Options, progress: Arc<Progress>) -> Result<()> {
    let (root, unpacked) = match package_root(&opts.source) {
        Some(root) => (root, false),
        None if opts.source.is_file() => {
            let (game, pol) = (Path::new(PACKAGE_DIR).join("FINAL_FANTASY_XI"), Path::new(PACKAGE_DIR).join(POL_MSI));
            let root =
                unpack_rar(&opts.source, &opts.staging, &progress, |name| name.starts_with(&game) || name == pol)?;
            if !root.join(FFXI_MSI).is_file() {
                bail!("archive did not contain {FFXI_MSI}");
            }
            (root, true)
        }
        None => bail!("{} is neither the installer nor an extracted copy of it", opts.source.display()),
    };

    let (db, _) = Database::open(&root.join(FFXI_MSI))?;
    let install_root = opts.game_dir.join("FINAL FANTASY XI");
    // Map DIR_FF11 to "" so every path it resolves is relative to the game folder.
    let resolver = DirResolver::new(&db, HashMap::from([("DIR_FF11".to_string(), String::new())]));

    let mut targets: HashMap<String, (PathBuf, u64)> = HashMap::new();
    for file in &db.files {
        if !db.component_installed(&file.component) {
            continue;
        }
        let Some(dir) = db.components.get(&file.component).and_then(|c| resolver.resolve(&c.directory).ok()) else {
            log::warn!("skipping {} (outside the game folder)", file.name);
            continue;
        };
        let mut path = install_root.clone();
        path.extend(dir.split('\\').filter(|s| !s.is_empty()));
        path.push(&file.name);
        targets.insert(file.key.clone(), (path, file.size));
    }
    let total: u64 = targets.values().map(|(_, size)| size).sum();
    // The files below go back to the installer's versions: the applied manifest no longer describes them, so the
    // next update reads every file (also after a run that stops part way).
    crate::patch::forget_applied(&install_root)?;
    progress.begin(format!("Installing {} files", targets.len()), total);

    let cab_dir = root.join("FINAL_FANTASY_XI");
    let results: Vec<Result<Vec<cabx::Extracted>>> = std::thread::scope(|s| {
        let handles: Vec<_> = db
            .media
            .iter()
            .map(|media| {
                let (targets, progress, cab) = (&targets, &progress, cab_dir.join(&media.cabinet));
                s.spawn(move || {
                    let file = std::fs::File::open(&cab).with_context(|| format!("opening {}", cab.display()))?;
                    cabx::extract_all(
                        file,
                        |name| targets.get(name).map(|(p, _)| p.clone()),
                        |n| {
                            progress.done.fetch_add(n, Ordering::Relaxed);
                        },
                    )
                    .with_context(|| format!("extracting {}", cab.display()))
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap_or_else(|_| Err(anyhow!("extract thread panicked")))).collect()
    });

    let mut extracted = 0usize;
    let mut bad = Vec::new();
    for batch in results {
        for item in batch? {
            extracted += 1;
            if opts.verify && db.hashes.get(&item.name).is_some_and(|want| *want != item.md5) {
                bad.push(item.path.display().to_string());
            }
        }
    }
    if extracted != targets.len() {
        bail!("cabinets held {extracted} of the {} expected files", targets.len());
    }
    if !bad.is_empty() {
        bail!("{} files failed their MD5 check, e.g. {}", bad.len(), bad[0]);
    }

    // The creator's name filter reads PlayOnline's dictionary. The game runs without it (names are then left to the
    // server), so a package without the viewer does not fail the install.
    match copy_name_dic(&root.join(POL_MSI), &opts.game_dir, opts.verify) {
        Ok(path) => log::info!("name dictionary copied to {}", path.display()),
        Err(e) => log::warn!("name dictionary not copied: {e:#}"),
    }

    if unpacked && !opts.keep_staging {
        std::fs::remove_dir_all(&opts.staging).ok();
    }
    *progress.phase.lock().unwrap() = "Installed".into();
    Ok(())
}
