//! Native replacement for FFXISetup.exe + FINAL_FANTASY_XI.msi: unpacks the game data.
//! PlayOnline, DirectX and the registry are Windows runtime concerns and are skipped; of the PlayOnline Viewer only
//! the name dictionary the character creator reads is copied (poldic.rs).

use crate::cabx;
use crate::msi_db::{Database, DirResolver};
use anyhow::{Context, Result, anyhow, bail};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

/// Square Enix's five FFXIFullSetup volumes (part1 is the self-extracting RAR).
pub const INSTALLER_VOLUMES: usize = 5;

pub fn installer_volume_name(i: usize) -> String {
    if i == 1 { "FFXIFullSetup_US.part1.exe".into() } else { format!("FFXIFullSetup_US.part{i}.rar") }
}

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

fn has_rar_magic(buf: &[u8]) -> bool {
    buf.windows(7).any(|w| w.starts_with(b"Rar!\x1a\x07"))
}

/// True when a volume looks like a real Square Enix part, not a stub or a failed browser download.
pub fn installer_volume_ok(path: &Path, part: usize) -> Result<()> {
    let name = path.file_name().and_then(|s| s.to_str()).unwrap_or("?");
    let meta = std::fs::metadata(path).with_context(|| format!("cannot read {name}"))?;
    let size = meta.len();
    let min = if part == 1 { 1_000_000 } else { 50_000_000 };
    if size < min {
        bail!(
            "{name} is only {size} bytes (expected at least {min}). Download all five FFXIFullSetup parts from Square Enix into one folder — partial or placeholder files cannot install."
        );
    }
    let mut f = std::fs::File::open(path).with_context(|| format!("cannot open {name}"))?;
    let mut head = vec![0u8; if part == 1 { 1 << 20 } else { 16 }];
    let n = f.read(&mut head)?;
    let head = &head[..n];
    if !has_rar_magic(head) {
        bail!(
            "{name} is not a valid installer volume (no RAR data). Remove it and download again; failed downloads often save an HTML page with the right filename."
        );
    }
    Ok(())
}

/// Byte size of the five volumes when every file is present.
pub fn installer_dir_bytes(dir: &Path) -> u64 {
    (1..=INSTALLER_VOLUMES)
        .filter_map(|i| {
            let p = dir.join(installer_volume_name(i));
            std::fs::metadata(&p).ok().map(|m| m.len())
        })
        .sum()
}

/// Copies or moves validated volumes into `stash` (for example `game_dir/.download`).
pub fn stage_installer_volumes(src: &Path, stash: &Path, progress: &Progress) -> Result<()> {
    validate_installer_dir(src)?;
    std::fs::create_dir_all(stash)?;
    let same = src
        .canonicalize()
        .ok()
        .zip(stash.canonicalize().ok())
        .is_some_and(|(a, b)| a == b);
    if same {
        return validate_installer_dir(stash);
    }
    let total: u64 = (1..=INSTALLER_VOLUMES)
        .map(|i| std::fs::metadata(src.join(installer_volume_name(i))).map(|m| m.len()).unwrap_or(0))
        .sum();
    progress.begin("Preparing installer files", total);
    let mut done = 0u64;
    for i in 1..=INSTALLER_VOLUMES {
        let name = installer_volume_name(i);
        let from = src.join(&name);
        let dest = stash.join(&name);
        installer_volume_ok(&from, i)?;
        if dest.is_file() {
            installer_volume_ok(&dest, i)?;
            done += std::fs::metadata(&dest)?.len();
            progress.done.store(done, Ordering::Relaxed);
            continue;
        }
        *progress.phase.lock().unwrap() = format!("Staging {name}");
        if std::fs::rename(&from, &dest).is_err() {
            copy_file_progress(&from, &dest, progress, &mut done)?;
            std::fs::remove_file(&from).with_context(|| format!("removing {name} after copy"))?;
        } else {
            done += std::fs::metadata(&dest)?.len();
            progress.done.store(done, Ordering::Relaxed);
        }
    }
    validate_installer_dir(stash)
}

fn copy_file_progress(from: &Path, to: &Path, progress: &Progress, done: &mut u64) -> Result<()> {
    let mut src = std::fs::File::open(from)?;
    let mut dst = std::fs::File::create(to)?;
    let mut buf = [0u8; 1024 * 1024];
    loop {
        let n = src.read(&mut buf)?;
        if n == 0 {
            break;
        }
        dst.write_all(&buf[..n])?;
        *done += n as u64;
        progress.done.store(*done, Ordering::Relaxed);
    }
    Ok(())
}

/// Deletes the five FFXIFullSetup volumes and removes `dir` when empty.
pub fn remove_installer_volumes(dir: &Path) -> Result<()> {
    for i in 1..=INSTALLER_VOLUMES {
        let p = dir.join(installer_volume_name(i));
        if p.is_file() {
            std::fs::remove_file(&p).with_context(|| format!("removing {}", p.display()))?;
        }
    }
    if dir.exists() {
        let _ = std::fs::remove_dir(dir);
    }
    Ok(())
}

/// All five volumes in one folder, each readable and large enough to unpack.
pub fn validate_installer_dir(dir: &Path) -> Result<()> {
    for i in 1..=INSTALLER_VOLUMES {
        let path = dir.join(installer_volume_name(i));
        if !path.is_file() {
            bail!("missing {}", path.file_name().and_then(|s| s.to_str()).unwrap_or("?"));
        }
        installer_volume_ok(&path, i)?;
    }
    Ok(())
}

/// Extracts the wanted files from the multi-volume RAR self-extractor; the package folder they land in.
fn unpack_rar(
    first_volume: &Path,
    staging: &Path,
    progress: &Progress,
    wanted: impl Fn(&Path) -> bool,
) -> Result<PathBuf> {
    if let Some(dir) = first_volume.parent() {
        validate_installer_dir(dir)?;
    }
    let first_volume = std::fs::canonicalize(first_volume).unwrap_or_else(|_| first_volume.to_path_buf());
    let mut total = 0;
    let mut listing = unrar::Archive::new(&first_volume)
        .open_for_listing()
        .with_context(|| format!("opening RAR archive at {}", first_volume.display()))?;
    while let Some(Ok(entry)) = listing.next() {
        if entry.is_file() && wanted(&entry.filename) && !entry.is_split_before() {
            total += entry.unpacked_size;
        }
    }
    progress.begin("Unpacking installer archive", total);

    std::fs::create_dir_all(staging)?;
    let mut archive = unrar::Archive::new(&first_volume).open_for_processing()?;
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
    // The files below go back to the installer's versions: once the first is written the applied version no longer
    // describes the folder (crate::patch::forget_applied), so the next update reads every file. An install that fails
    // before writing any leaves the folder's version as it was.
    let forgot: std::sync::OnceLock<std::result::Result<(), String>> = std::sync::OnceLock::new();
    progress.begin(format!("Installing {} files", targets.len()), total);

    let cab_dir = root.join("FINAL_FANTASY_XI");
    let results: Vec<Result<Vec<cabx::Extracted>>> = std::thread::scope(|s| {
        let handles: Vec<_> = db
            .media
            .iter()
            .map(|media| {
                let (targets, progress, cab) = (&targets, &progress, cab_dir.join(&media.cabinet));
                let (forgot, install_root) = (&forgot, &install_root);
                s.spawn(move || {
                    let file = std::fs::File::open(&cab).with_context(|| format!("opening {}", cab.display()))?;
                    cabx::extract_all(
                        file,
                        |name| {
                            let (p, _) = targets.get(name)?;
                            let ok = forgot.get_or_init(|| {
                                crate::patch::forget_applied(install_root).map_err(|e| format!("{e:#}"))
                            });
                            ok.is_ok().then(|| p.clone())
                        },
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

    if let Some(Err(e)) = forgot.get() {
        bail!("dropping the applied version: {e}");
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn fake_volume(path: &Path, part: usize) {
        let mut f = std::fs::File::create(path).unwrap();
        f.write_all(b"Rar!\x1a\x07\x00").unwrap();
        let len = if part == 1 { 1_000_001u64 } else { 50_000_001 };
        f.set_len(len).unwrap();
    }

    #[test]
    fn rejects_stub_installer_parts() {
        let dir = std::env::temp_dir().join(format!("vana-install-check-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(installer_volume_name(1)), b"stub").unwrap();
        assert!(installer_volume_ok(&dir.join(installer_volume_name(1)), 1).is_err());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn accepts_sparse_fake_volumes() {
        let dir = std::env::temp_dir().join(format!("vana-install-check-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for i in 1..=INSTALLER_VOLUMES {
            fake_volume(&dir.join(installer_volume_name(i)), i);
        }
        validate_installer_dir(&dir).unwrap();
        std::fs::remove_dir_all(&dir).ok();
    }
}
