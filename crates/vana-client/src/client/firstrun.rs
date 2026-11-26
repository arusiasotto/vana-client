//! First start without game files (not retail: retail's installer was its program). The title and login are
//! drawn from the DATs, so until they exist a small window of ours asks to download the free retail client from
//! Square Enix, installs its game files, brings them up to date and deletes what it downloaded, or to point at game
//! files already on disk.
// Android draws its own window (android.rs) over the same install steps; the download path is desktop's.
#![cfg_attr(target_os = "android", allow(dead_code, unused_imports))]

use crate::install::Progress;
use anyhow::{Context, Result};
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

/// Square Enix's download of the full client, five RAR volumes (part1 is the self-extractor).
const CDN: &str = "https://gdl.square-enix.com/ffxi/download/us";
const VOLUMES: usize = 5;
/// 7,734,210,712 bytes, what the CDN's lengths add up to (for the estimate before the first response).
const TOTAL: u64 = 7_734_210_712;

fn volume(i: usize) -> String {
    crate::install::installer_volume_name(i)
}

/// The first-start window's size (fixed; the configured size applies once the game files are in).
pub const WINDOW: [u32; 2] = [760, 540];

/// Left in the game folder while the first start runs: one stopped part-way resumes in this window.
const MARKER: &str = ".vana-installing";

/// Install staging under the game folder (parent of `FINAL FANTASY XI`): a partial run may leave the marker while the
/// retail tree already has `VTABLE.DAT`.
pub fn interrupted_install(game_dir: &Path) -> bool {
    game_dir.join(MARKER).is_file()
        || game_dir.join(".staging").is_dir()
        || game_dir.join(".download").join(volume(1)).is_file()
        || game_dir.join(".download").is_dir()
}

/// The install at `ffxi_dir` is missing game files or was stopped part-way.
pub fn incomplete(ffxi_dir: &Path) -> bool {
    if !ffxi_dir.join("VTABLE.DAT").is_file() {
        return true;
    }
    if !ffxi_dir.join("FTABLE.DAT").is_file() || !crate::dat::ffximain(ffxi_dir).is_file() {
        return true;
    }
    ffxi_dir.parent().is_some_and(interrupted_install)
}

/// True when the retail tree is present and no install staging markers remain.
pub fn install_complete(ffxi_dir: &Path) -> bool {
    !incomplete(ffxi_dir)
}

/// Short explanation for the recovery screen when [`incomplete`] is true.
pub fn install_incomplete_detail(ffxi_dir: &Path) -> String {
    let mut parts = Vec::new();
    if !ffxi_dir.join("VTABLE.DAT").is_file() {
        parts.push("VTABLE.DAT is missing");
    }
    if !ffxi_dir.join("FTABLE.DAT").is_file() {
        parts.push("FTABLE.DAT is missing");
    }
    if !crate::dat::ffximain(ffxi_dir).is_file() {
        parts.push("FFXiMain.dll is missing");
    }
    if let Some(parent) = ffxi_dir.parent() {
        if parent.join(MARKER).is_file() {
            parts.push("a previous install did not finish (.vana-installing)");
        }
        if parent.join(".staging").is_dir() {
            parts.push("installer staging (.staging) is still present");
        }
        if parent.join(".download").join(volume(1)).is_file() {
            parts.push("installer volumes are staged under .download");
        }
    }
    if parts.is_empty() {
        "The install could not be verified.".into()
    } else {
        parts.join("; ")
    }
}

/// Partial or interrupted install under `game_dir` (parent of `FINAL FANTASY XI`).
#[cfg(target_os = "android")]
pub fn needs_recovery(game_dir: &Path) -> bool {
    if interrupted_install(game_dir) {
        return true;
    }
    let ffxi = game_dir.join("FINAL FANTASY XI");
    if install_complete(&ffxi) && !crate::android_fs::setup_done() {
        return true;
    }
    if !incomplete(&ffxi) {
        return false;
    }
    ffxi.join("VTABLE.DAT").is_file()
        || game_dir.is_dir() && std::fs::read_dir(game_dir).map(|mut rd| rd.next().is_some()).unwrap_or(false)
}

/// On Android, `installed` in `config.json` is cleared with the app; [`crate::android_fs::setup_done`] is the durable
/// setup marker in app-private storage (also cleared on **Clear data**).
#[cfg(target_os = "android")]
pub fn sync_config(cfg: &mut crate::config::Config) {
    let ffxi = cfg.ffxi_dir();
    let game_dir = &cfg.game_dir;
    if crate::android_fs::setup_done()
        && !interrupted_install(game_dir)
        && !incomplete(&ffxi)
        && !cfg.installed
    {
        log::info!("restoring installed from app setup marker");
        cfg.installed = true;
        if let Err(e) = cfg.save() {
            log::warn!("saving the config: {e:#}");
        }
    }
    if crate::android_fs::setup_done() && (interrupted_install(game_dir) || incomplete(&ffxi)) {
        log::info!("clearing app setup marker (install incomplete)");
        crate::android_fs::clear_setup_done();
    }
    if !before_title(game_dir, &ffxi, cfg.installed) {
        return;
    }
    if !cfg.installed {
        return;
    }
    log::info!("game install at {} is incomplete; opening first-start", ffxi.display());
    cfg.installed = false;
    crate::android_fs::clear_setup_done();
    if let Err(e) = cfg.save() {
        log::warn!("saving the config: {e:#}");
    }
}

/// Whether first-start / recovery should run before the opening movie and title.
///
/// Checks [`interrupted_install`] on `game_dir` first so `.vana-installing` is not missed when the config path and
/// `ffxi_dir.parent()` differ or the retail tree already has `VTABLE.DAT`.
///
/// On Android, game files live on shared storage and survive **Clear data**; only app storage (including
/// `config.json`, `installed`, and `files/setup_done`) is wiped. The boot gate reads the app setup marker first, then
/// shared storage ([`needs_recovery`]) so a complete tree after clear data opens recovery instead of the title.
pub fn before_title(game_dir: &Path, ffxi_dir: &Path, installed: bool) -> bool {
    if interrupted_install(game_dir) {
        log::info!("first-start: install staging under {}", game_dir.display());
        return true;
    }
    if incomplete(ffxi_dir) {
        return true;
    }
    #[cfg(target_os = "android")]
    {
        if needs_recovery(game_dir) {
            return true;
        }
        if !crate::android_fs::setup_done() {
            return true;
        }
        if !installed {
            return true;
        }
    }
    false
}

/// Whether the client should open the first-start window before the title screen.
pub fn needed(ffxi_dir: &Path, installed: bool) -> bool {
    let game_dir = ffxi_dir.parent().unwrap_or(ffxi_dir);
    before_title(game_dir, ffxi_dir, installed)
}

/// The game folder (the one that holds `FINAL FANTASY XI`) for an install picked in the window: the
/// `FINAL FANTASY XI` folder itself, or a folder above it in the Windows layout (`PlayOnline/SquareEnix`).
pub fn existing(picked: &Path) -> Result<PathBuf> {
    let candidates = [
        picked.parent().filter(|_| picked.file_name().is_some_and(|n| n == "FINAL FANTASY XI")).map(Path::to_path_buf),
        Some(picked.to_path_buf()),
        Some(picked.join("SquareEnix")),
        Some(picked.join("PlayOnline").join("SquareEnix")),
    ];
    let found = candidates.into_iter().flatten().find(|g| g.join("FINAL FANTASY XI").join("VTABLE.DAT").is_file());
    let Some(game_dir) = found else {
        anyhow::bail!(
            "No game files in {}: pick the FINAL FANTASY XI folder (the one with VTABLE.DAT) or a folder above it.",
            picked.display()
        );
    };
    if incomplete(&game_dir.join("FINAL FANTASY XI")) {
        anyhow::bail!(
            "The install in {} did not finish: choose Download and install with that folder to resume it.",
            game_dir.display()
        );
    }
    Ok(game_dir)
}

/// What closing the client does to the step under way.
fn closing_note(phase: &str) -> &'static str {
    if phase.starts_with("Downloading") {
        "Closing vana-client stops this; the download resumes next time."
    } else if phase.starts_with("Unpacking") || phase.starts_with("Installing") {
        "Closing vana-client stops this; installing starts over next time (the download is kept)."
    } else if phase.starts_with("Updating") || phase.starts_with("Checking") {
        "Closing vana-client stops this; the update picks up where it left off next time."
    } else {
        ""
    }
}

enum Stage {
    /// Android: stale or partial install on disk before the normal setup steps.
    Recovery,
    Ask,
    Working,
    /// Install finished; the user chooses whether to delete staged installer volumes.
    CleanupOffer(PathBuf),
    Done,
    Failed(String),
}

pub enum Action {
    None,
    Quit,
    /// The download starts in this folder: the config keeps it, so a resumed start finds it.
    Begin(PathBuf),
    /// Game files are in: load the title.
    Ready,
}

#[cfg(not(target_os = "android"))]
pub struct FirstRun {
    game_dir: PathBuf,
    stage: Arc<Mutex<Stage>>,
    progress: Arc<Progress>,
    /// The folder picker's answer (it runs on a separate thread so the window keeps drawing).
    picked: Arc<Mutex<Option<Option<PathBuf>>>>,
    /// The picker open, and what its answer is for.
    picking: Option<Pick>,
    /// The game files were found in place rather than downloaded.
    found: bool,
    /// The finish page's choices (Linux): an application menu entry, a desktop shortcut.
    menu: bool,
    shortcut: bool,
    note: String,
}

#[cfg(not(target_os = "android"))]
#[derive(Clone, Copy)]
enum Pick {
    /// Where to download and install.
    Install,
    /// An install already on disk.
    Existing,
}

#[cfg(not(target_os = "android"))]
impl FirstRun {
    pub fn new(game_dir: PathBuf) -> Self {
        Self {
            game_dir,
            stage: Arc::new(Mutex::new(Stage::Ask)),
            progress: Arc::new(Progress::default()),
            picked: Default::default(),
            picking: None,
            found: false,
            menu: true,
            shortcut: false,
            note: String::new(),
        }
    }

    /// Where the game files go (the config default, or the folder picked).
    pub fn game_dir(&self) -> &Path {
        &self.game_dir
    }

    fn pick(&mut self, what: Pick) {
        self.picking = Some(what);
        let (start, out) = (self.game_dir.clone(), self.picked.clone());
        let title = match what {
            Pick::Install => "Install the game files in",
            Pick::Existing => "The FINAL FANTASY XI folder",
        };
        std::thread::spawn(move || {
            let mut dialog = rfd::FileDialog::new().set_title(title);
            if let Some(dir) = start.ancestors().find(|d| d.is_dir()) {
                dialog = dialog.set_directory(dir);
            }
            *out.lock().unwrap() = Some(dialog.pick_folder());
        });
    }

    fn start(&self) {
        *self.stage.lock().unwrap() = Stage::Working;
        let (game_dir, stage, progress) = (self.game_dir.clone(), self.stage.clone(), self.progress.clone());
        std::thread::spawn(move || {
            let r = run(&game_dir, &progress);
            *stage.lock().unwrap() = match r {
                Ok(()) => Stage::Done,
                Err(e) => {
                    log::warn!("first start: {e:#}");
                    Stage::Failed(format!("{e:#}"))
                }
            };
        });
    }

    /// The window (egui: no game art exists yet).
    pub fn ui(&mut self, ctx: &egui::Context) -> Action {
        let mut action = Action::None;
        let stage = match &*self.stage.lock().unwrap() {
            Stage::Recovery | Stage::Ask => 0,
            Stage::Working => 1,
            Stage::Done | Stage::CleanupOffer(_) => 2,
            Stage::Failed(_) => 3,
        };
        if stage == 2 && !super::desktop::supported() {
            return Action::Ready;
        }
        if let Some(answer) = self.picked.lock().unwrap().take()
            && let Some(what) = self.picking.take()
            && let Some(dir) = answer
        {
            self.note.clear();
            match what {
                Pick::Install => self.game_dir = dir,
                Pick::Existing => match existing(&dir) {
                    Ok(game_dir) => {
                        self.game_dir = game_dir;
                        self.found = true;
                        *self.stage.lock().unwrap() = Stage::Done;
                        if !super::desktop::supported() {
                            return Action::Ready;
                        }
                    }
                    Err(e) => self.note = format!("{e:#}"),
                },
            }
        }
        let failed = match &*self.stage.lock().unwrap() {
            Stage::Failed(e) => e.clone(),
            _ => String::new(),
        };
        let gold = egui::Color32::from_rgb(0xe8, 0xc8, 0x80);
        let screen = ctx.content_rect();
        ctx.layer_painter(egui::LayerId::background()).rect_filled(
            screen,
            0.0,
            egui::Color32::from_rgb(0x12, 0x14, 0x22),
        );
        egui::Area::new(egui::Id::unique("first run")).anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0]).show(ctx, |ui| {
            {
                egui::Frame::new()
                    .fill(egui::Color32::from_rgb(0x1e, 0x22, 0x3a))
                    .stroke(egui::Stroke::new(1.0, egui::Color32::from_rgb(0x6a, 0x70, 0xa8)))
                    .corner_radius(6.0)
                    .inner_margin(32.0)
                    .show(ui, |ui| {
                        ui.set_max_width(620.0);
                        ui.style_mut().spacing.button_padding = egui::vec2(14.0, 8.0);
                        ui.vertical(|ui| {
                            ui.label(egui::RichText::new("FINAL FANTASY XI game files").size(30.0).color(gold));
                            ui.add_space(10.0);
                            match stage {
                                0 => {
                                    ui.label(egui::RichText::new(format!(
                                        "vana-client uses the game files of the free FINAL FANTASY XI client. Download it from Square Enix \
                                         (about 7.7 GB) and install its game files to\n\n{}\n\nThe download is deleted once the game \
                                         files are installed and up to date. About 25 GB of free space is needed while it runs.",
                                        self.game_dir.display()
                                    )).size(17.0));
                                    ui.add_space(6.0);
                                    let picking = self.picking.is_some();
                                    ui.horizontal(|ui| {
                                        if ui.add_enabled(!picking, egui::Button::new(egui::RichText::new("Change install folder...").size(15.0))).clicked() {
                                            self.pick(Pick::Install);
                                        }
                                        if ui.add_enabled(!picking, egui::Button::new(egui::RichText::new("Use existing game files...").size(15.0))).clicked() {
                                            self.pick(Pick::Existing);
                                        }
                                    });
                                    if !self.note.is_empty() {
                                        ui.label(egui::RichText::new(&self.note).color(egui::Color32::from_rgb(0xe0, 0x80, 0x70)));
                                    }
                                    ui.add_space(16.0);
                                    ui.horizontal(|ui| {
                                        if ui.add_enabled(!picking, egui::Button::new(egui::RichText::new("Download and install").size(19.0))).clicked() {
                                            self.start();
                                            action = Action::Begin(self.game_dir.clone());
                                        }
                                        if ui.button(egui::RichText::new("Quit").size(19.0)).clicked() {
                                            action = Action::Quit;
                                        }
                                    });
                                }
                                2 => {
                                    if self.found {
                                        ui.label(egui::RichText::new(format!(
                                            "Using the game files in\n\n{}\n\nIf they are behind the current version, the Update button on the \
                                             title screen brings them up to date.",
                                            self.game_dir.join("FINAL FANTASY XI").display()
                                        )).size(17.0));
                                    } else {
                                        ui.label(egui::RichText::new("The game files are installed and up to date.").size(17.0));
                                    }
                                    ui.add_space(12.0);
                                    ui.checkbox(&mut self.menu, egui::RichText::new("Add vana-client to the application menu").size(16.0));
                                    ui.checkbox(&mut self.shortcut, egui::RichText::new("Add a shortcut to the desktop").size(16.0));
                                    if !self.note.is_empty() {
                                        ui.label(egui::RichText::new(&self.note).weak());
                                    }
                                    ui.add_space(16.0);
                                    if ui.button(egui::RichText::new("Continue").size(19.0)).clicked() {
                                        let r = super::desktop::install(self.menu).and_then(|()| if self.shortcut { super::desktop::desktop_shortcut() } else { Ok(()) });
                                        match r {
                                            Ok(()) => action = Action::Ready,
                                            Err(e) => self.note = format!("Could not add it: {e:#}"),
                                        }
                                    }
                                }
                                1 => {
                                    let p = &self.progress;
                                    let (done, total) = (p.done.load(Ordering::Relaxed), p.total.load(Ordering::Relaxed));
                                    ui.label(egui::RichText::new(p.phase.lock().unwrap().clone()).size(19.0));
                                    ui.add_space(8.0);
                                    ui.add(egui::ProgressBar::new(p.fraction()).desired_width(620.0).fill(egui::Color32::from_rgb(0x9a, 0x7a, 0x40)));
                                    if total > 0 {
                                        ui.label(format!("{:.2} of {:.2} GB", done as f64 / 1e9, total as f64 / 1e9));
                                    }
                                    ui.add_space(8.0);
                                    let note = closing_note(&p.phase.lock().unwrap());
                                    if !note.is_empty() {
                                        ui.label(egui::RichText::new(note).weak());
                                    }
                                    ctx.request_repaint_after(std::time::Duration::from_millis(250));
                                }
                                _ => {
                                    ui.label("It did not finish:");
                                    ui.label(egui::RichText::new(&failed).weak());
                                    ui.add_space(16.0);
                                    ui.horizontal(|ui| {
                                        if ui.button(egui::RichText::new("Try again").size(19.0)).clicked() {
                                            self.start();
                                        }
                                        if ui.button(egui::RichText::new("Quit").size(19.0)).clicked() {
                                            action = Action::Quit;
                                        }
                                    });
                                }
                            }
                        });
                    });
            }
        });
        action
    }
}

fn set(p: &Progress, phase: impl Into<String>, done: u64, total: u64) {
    *p.phase.lock().unwrap() = phase.into();
    p.done.store(done, Ordering::Relaxed);
    p.total.store(total, Ordering::Relaxed);
}

/// Download, install, update, clean up.
fn run(game_dir: &Path, p: &Arc<Progress>) -> Result<()> {
    let dl = game_dir.join(".download");
    std::fs::create_dir_all(&dl).with_context(|| dl.display().to_string())?;
    std::fs::write(game_dir.join(MARKER), b"")?;
    // Bytes already on disk count toward the bar, so a resumed download starts where it was.
    let mut before = 0u64;
    for i in 1..=VOLUMES {
        let dest = dl.join(volume(i));
        if dest.is_file() {
            before += std::fs::metadata(&dest)?.len();
            continue;
        }
        let base = before;
        super::updater::download(&format!("{CDN}/{}", volume(i)), &dest, &|d, _| {
            set(p, format!("Downloading from Square Enix (part {i} of {VOLUMES})"), base + d, TOTAL)
        })?;
        before += std::fs::metadata(&dest)?.len();
    }
    // A finished install from an earlier, stopped run is not unpacked again.
    let root = game_dir.join("FINAL FANTASY XI");
    let installed = root.join("VTABLE.DAT").is_file() && !dl.join(volume(1)).is_file();
    let opts = crate::install::Options {
        source: dl.join(volume(1)),
        staging: game_dir.join(".staging"),
        game_dir: game_dir.to_path_buf(),
        verify: true,
        keep_staging: false,
    };
    if !installed {
        crate::install::install(&opts, p.clone())?;
    }
    set(p, "Checking for game updates", 0, 0);
    let plan = crate::patch::plan(&root, true, false)?;
    let total: u64 = plan.todo.iter().map(|t| t.2).sum();
    let n = plan.todo.len();
    crate::patch::apply(&root, &plan, 4, &|f, b| set(p, format!("Updating game files ({f} of {n})"), b, total))?;
    set(p, "Cleaning up", 0, 0);
    std::fs::remove_dir_all(&dl).with_context(|| format!("removing {}", dl.display()))?;
    let _ = std::fs::remove_dir_all(game_dir.join(".staging"));
    std::fs::remove_file(game_dir.join(MARKER))?;
    Ok(())
}

#[cfg(target_os = "android")]
mod android;
#[cfg(target_os = "android")]
pub use android::FirstRun;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn before_title_sees_marker_on_game_dir_with_retail_tree() {
        let base = std::env::temp_dir().join(format!("vana-before-title-{}", std::process::id()));
        let game = base.join("Game").join("FFXI");
        let ffxi = game.join("FINAL FANTASY XI");
        std::fs::create_dir_all(&ffxi).unwrap();
        std::fs::write(ffxi.join("VTABLE.DAT"), b"").unwrap();
        std::fs::write(ffxi.join("FTABLE.DAT"), &[0u8; 2]).unwrap();
        std::fs::write(ffxi.join("FFXiMain.dll"), b"").unwrap();
        assert!(!incomplete(&ffxi));
        assert!(!needed(&ffxi, true));
        std::fs::write(game.join(MARKER), b"").unwrap();
        assert!(before_title(&game, &ffxi, true));
        assert!(before_title(&game, &ffxi, false));
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    #[cfg(target_os = "android")]
    fn needs_recovery_when_setup_marker_cleared_with_complete_tree() {
        crate::android_fs::clear_setup_done();
        let base = std::env::temp_dir().join(format!("vana-setup-done-{}", std::process::id()));
        let game = base.join("Game").join("FFXI");
        let ffxi = game.join("FINAL FANTASY XI");
        std::fs::create_dir_all(&ffxi).unwrap();
        std::fs::write(ffxi.join("VTABLE.DAT"), b"").unwrap();
        std::fs::write(ffxi.join("FTABLE.DAT"), &[0u8; 2]).unwrap();
        std::fs::write(ffxi.join("FFXiMain.dll"), b"").unwrap();
        assert!(!crate::android_fs::setup_done());
        assert!(needs_recovery(&game));
        crate::android_fs::mark_setup_done(&game);
        assert!(!needs_recovery(&game));
        crate::android_fs::clear_setup_done();
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    #[cfg(target_os = "android")]
    fn needs_recovery_when_install_is_partial() {
        let base = std::env::temp_dir().join(format!("vana-recovery-{}", std::process::id()));
        let game = base.join("Game").join("FFXI");
        let ffxi = game.join("FINAL FANTASY XI");
        std::fs::create_dir_all(&ffxi).unwrap();
        assert!(!needs_recovery(&game));
        std::fs::write(game.join(MARKER), b"").unwrap();
        assert!(needs_recovery(&game));
        std::fs::write(ffxi.join("VTABLE.DAT"), b"").unwrap();
        assert!(needs_recovery(&game));
        std::fs::write(ffxi.join("FTABLE.DAT"), &[0u8; 2]).unwrap();
        std::fs::write(ffxi.join("FFXiMain.dll"), b"").unwrap();
        assert!(needs_recovery(&game));
        std::fs::remove_file(game.join(MARKER)).unwrap();
        assert!(!needs_recovery(&game));
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    fn needed_follows_installed_on_android() {
        let base = std::env::temp_dir().join(format!("vana-needed-{}", std::process::id()));
        let ffxi = base.join("FINAL FANTASY XI");
        std::fs::create_dir_all(&ffxi).unwrap();
        std::fs::write(ffxi.join("VTABLE.DAT"), b"").unwrap();
        assert!(incomplete(&ffxi));
        assert!(needed(&ffxi, false));
        #[cfg(not(target_os = "android"))]
        assert!(!needed(&ffxi, false));
        std::fs::write(ffxi.join("FTABLE.DAT"), &[0u8; 2]).unwrap();
        std::fs::write(ffxi.join("FFXiMain.dll"), b"").unwrap();
        assert!(!incomplete(&ffxi));
        #[cfg(target_os = "android")]
        assert!(!needed(&ffxi, true));
        #[cfg(target_os = "android")]
        assert!(needed(&ffxi, false));
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    fn existing_finds_the_game_folder_from_any_level() {
        let base = std::env::temp_dir().join(format!("vana-firstrun-{}", std::process::id()));
        let game = base.join("PlayOnline").join("SquareEnix");
        let ffxi = game.join("FINAL FANTASY XI");
        std::fs::create_dir_all(&ffxi).unwrap();
        assert!(existing(&base).is_err());
        std::fs::write(ffxi.join("VTABLE.DAT"), b"").unwrap();
        for picked in [&ffxi, &game, &base.join("PlayOnline"), &base] {
            assert_eq!(existing(picked).unwrap(), game, "picked {}", picked.display());
        }
        // An install vana-client stopped part-way is resumed, not used.
        std::fs::write(game.join(MARKER), b"").unwrap();
        assert!(existing(&ffxi).is_err());
        std::fs::remove_dir_all(&base).unwrap();
    }
}
