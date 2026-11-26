//! The first-start window on Android: All files access first, then game files from Square Enix's installer volumes
//! the user downloaded (kept where they are), or an install already on the device.

use super::{
    Action, MARKER, Stage, VOLUMES, closing_note, existing, install_complete, install_incomplete_detail, needs_recovery,
    set, volume,
};
use crate::install::Progress;
use anyhow::Result;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

/// PlayOnline's page for the five FFXIFullSetup volumes (the browser downloads them; the install reads them locally).
const SE_CLIENT_DOWNLOAD: &str = "https://www.playonline.com/ff11us/download/media/install_win.html";

fn downloads() -> PathBuf {
    crate::config::downloads_dir().unwrap_or_default()
}

/// Folders searched for the installer volumes: the install's own `.download`, the install folder, Download and the
/// folders directly under it.
fn installer_search_dirs(install_parent: &Path) -> Vec<PathBuf> {
    let downloads = downloads();
    let mut dirs = vec![install_parent.join(".download"), install_parent.to_path_buf(), downloads.clone()];
    if let Ok(rd) = std::fs::read_dir(&downloads) {
        dirs.extend(rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()));
    }
    dirs.sort();
    dirs.dedup();
    dirs
}

fn installer_parts_in(dir: &Path) -> usize {
    (1..=VOLUMES)
        .filter(|i| {
            let Some(p) = crate::install::find_installer_volume(dir, *i) else { return false };
            crate::install::installer_volume_ok(&p, *i).is_ok()
        })
        .count()
}

/// `archives` and its immediate subfolders (some browsers unzip into a child folder).
fn archive_candidate_dirs(archives: &Path) -> Vec<PathBuf> {
    if archives.as_os_str().is_empty() {
        return vec![];
    }
    let mut dirs = vec![archives.to_path_buf()];
    if let Ok(rd) = std::fs::read_dir(archives) {
        dirs.extend(rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()));
    }
    dirs.sort();
    dirs.dedup();
    dirs
}

/// The folder holding all five volumes: the one typed in, else the first found.
fn installer_dir(install_parent: &Path, archives: &Path) -> Option<PathBuf> {
    for d in archive_candidate_dirs(archives) {
        if installer_parts_in(&d) == VOLUMES {
            return Some(d);
        }
    }
    installer_search_dirs(install_parent).into_iter().find(|d| installer_parts_in(d) == VOLUMES)
}

/// The folder with the most volumes, for the note when none has all five.
fn best_installer_parts(install_parent: &Path) -> Option<(PathBuf, usize)> {
    installer_search_dirs(install_parent)
        .into_iter()
        .map(|d| {
            let n = installer_parts_in(&d);
            (d, n)
        })
        .filter(|(_, n)| *n > 0)
        .max_by_key(|(_, n)| *n)
}

fn short_path(p: &Path) -> String {
    let s = p.display().to_string().replace("/storage/emulated/0", "/sdcard");
    let n = s.chars().count();
    if n > 44 { format!("…{}", s.chars().skip(n - 40).collect::<String>()) } else { s }
}

/// Normalized install-root path for comparisons (`/sdcard` → emulated storage).
fn norm_install_root(path: &Path) -> String {
    path.to_string_lossy().replace("/sdcard", "/storage/emulated/0").trim_end_matches('/').to_string()
}

/// The config default (`/storage/emulated/0/Game/FFXI`).
pub fn is_default_install_dir(path: &Path) -> bool {
    norm_install_root(path) == norm_install_root(&crate::config::default_game_dir())
}

fn install_dir_has_content(game_dir: &Path) -> bool {
    game_dir.is_dir() && std::fs::read_dir(game_dir).map(|mut rd| rd.next().is_some()).unwrap_or(false)
}

/// Deletes everything under the install folder (not the folder itself). Non-default paths need `allow_non_default`.
pub fn wipe_install_dir(game_dir: &Path, allow_non_default: bool) -> std::io::Result<()> {
    if !is_default_install_dir(game_dir) && !allow_non_default {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "refusing to wipe a non-default install folder without confirmation",
        ));
    }
    if !game_dir.is_dir() {
        return Ok(());
    }
    for entry in std::fs::read_dir(game_dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            std::fs::remove_dir_all(path)?;
        } else {
            std::fs::remove_file(path)?;
        }
    }
    Ok(())
}

/// Which choice the in-app folder list is filling in.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Browse {
    Existing,
    Archives,
    InstallTo,
}

#[derive(Clone)]
enum WipeStatus {
    Running,
    Finished(Result<(), String>),
}

pub struct FirstRun {
    game_dir: PathBuf,
    stage: Arc<Mutex<Stage>>,
    progress: Arc<Progress>,
    /// The folder that will hold `FINAL FANTASY XI`, as typed.
    path_input: String,
    /// The folder with the installer volumes, as typed.
    archive_path_input: String,
    browse: Option<Browse>,
    /// Folder the in-app list is showing while `browse` is set.
    browser_at: PathBuf,
    note: String,
    /// A tap on **Remove old install files** for a custom install folder is waiting for confirmation.
    wipe_confirm: Option<PathBuf>,
    wipe_job: Arc<Mutex<Option<WipeStatus>>>,
    /// Install folder being wiped (for the success note).
    wipe_active_path: Option<PathBuf>,
}

impl FirstRun {
    /// The game folder (parent of `FINAL FANTASY XI`) if the install path field resolves.
    fn resolved_game_dir(&self) -> Option<PathBuf> {
        let typed = PathBuf::from(self.path_input.trim());
        let pick = if typed.as_os_str().is_empty() { self.game_dir.clone() } else { typed };
        existing(&pick).ok()
    }

    fn try_start(&mut self, action: &mut Action) {
        self.note.clear();
        if !crate::android_fs::has_all_files_access() {
            self.note = "Turn on All files access (step 1), then tap Start.".into();
            return;
        }
        let typed = PathBuf::from(self.path_input.trim());
        let pick = if typed.as_os_str().is_empty() { self.game_dir.clone() } else { typed };
        match existing(&pick) {
            Ok(game_dir) => {
                log::info!("starting with game files in {}", game_dir.display());
                self.path_input = game_dir.display().to_string();
                self.game_dir = game_dir;
                *action = Action::Ready;
            }
            Err(e) => self.note = format!("{e:#}"),
        }
    }

    pub fn new(game_dir: PathBuf) -> Self {
        // Configs from before shared storage kept the game in app storage.
        let game_dir =
            if crate::config::in_app_storage(&game_dir) { crate::config::default_game_dir() } else { game_dir };
        let stage = if needs_recovery(&game_dir) {
            Stage::Recovery
        } else {
            Stage::Ask
        };
        Self {
            path_input: game_dir.display().to_string(),
            archive_path_input: downloads().display().to_string(),
            game_dir,
            stage: Arc::new(Mutex::new(stage)),
            progress: Arc::new(Progress::default()),
            browse: None,
            browser_at: crate::client::folder_pick::storage_root(),
            note: String::new(),
            wipe_confirm: None,
            wipe_job: Arc::new(Mutex::new(None)),
            wipe_active_path: None,
        }
    }

    fn wipe_running(&self) -> bool {
        matches!(&*self.wipe_job.lock().unwrap(), Some(WipeStatus::Running))
    }

    fn start_wipe(&mut self, path: PathBuf, allow_non_default: bool) {
        if self.wipe_running() {
            return;
        }
        self.note.clear();
        self.wipe_active_path = Some(path.clone());
        let job = self.wipe_job.clone();
        *job.lock().unwrap() = Some(WipeStatus::Running);
        std::thread::spawn(move || {
            let r = wipe_install_dir(&path, allow_non_default).map_err(|e| e.to_string());
            if r.is_ok() {
                crate::android_fs::clear_setup_done();
                log::info!("wiped {}", path.display());
            }
            *job.lock().unwrap() = Some(WipeStatus::Finished(r));
        });
    }

    fn poll_wipe_job(&mut self) {
        let snap = self.wipe_job.lock().unwrap().clone();
        let Some(WipeStatus::Finished(r)) = snap else { return };
        *self.wipe_job.lock().unwrap() = None;
        let path = self.wipe_active_path.take();
        match r {
            Ok(()) => {
                if let Some(p) = path {
                    self.note = format!("Removed old files under {}.", short_path(&p));
                }
                self.wipe_confirm = None;
                if matches!(*self.stage.lock().unwrap(), Stage::Recovery) {
                    *self.stage.lock().unwrap() = Stage::Ask;
                }
            }
            Err(e) => self.note = format!("Could not remove files: {e}"),
        }
    }

    fn wipe_progress_ui(&self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            ui.spinner();
            ui.label(egui::RichText::new("Removing files…").size(14.0));
        });
        ui.label(
            egui::RichText::new("Large installs can take a few minutes. Leave this screen open.")
                .size(11.0)
                .weak(),
        );
    }

    /// Where the game files go (the config default, or the folder picked).
    pub fn game_dir(&self) -> &Path {
        &self.game_dir
    }

    fn install_parent(&self) -> PathBuf {
        let typed = PathBuf::from(self.path_input.trim());
        if typed.as_os_str().is_empty() { self.game_dir.clone() } else { typed }
    }

    fn begin_install(&mut self) -> Action {
        self.note.clear();
        let parent = PathBuf::from(self.path_input.trim());
        let default = crate::config::default_game_dir();
        if parent.as_os_str().is_empty() {
            self.note = format!(
                "Enter the install folder (for example {}, which will hold FINAL FANTASY XI).",
                default.display()
            );
            return Action::None;
        }
        if crate::config::in_app_storage(&parent) {
            self.note = format!(
                "Install on shared storage (for example {}), not in the app's private data.",
                default.display()
            );
            return Action::None;
        }
        if let Err(e) = std::fs::create_dir_all(&parent) {
            self.note = format!("Cannot use that install folder: {e}");
            return Action::None;
        }
        let archives = PathBuf::from(self.archive_path_input.trim());
        let Some(archive_dir) = installer_dir(&parent, &archives) else {
            let hint = if !archives.as_os_str().is_empty() {
                format!("Found {} valid of {VOLUMES} parts in {}.", installer_parts_in(&archives), archives.display())
            } else {
                best_installer_parts(&parent)
                    .map(|(d, n)| format!("Found {n} valid of {VOLUMES} parts in {}.", d.display()))
                    .unwrap_or_else(|| format!("No installer parts in {}.", downloads().display()))
            };
            self.note = format!(
                "{hint} Put all five files (FFXIFullSetup_US.part1.exe and part2–5.rar) in the archives folder, or fix the path above."
            );
            return Action::None;
        };
        if let Err(e) = crate::install::validate_installer_dir(&archive_dir) {
            self.note = format!("{e:#}");
            return Action::None;
        }
        log::info!("installing from the volumes in {} to {}", archive_dir.display(), parent.display());
        self.game_dir = parent.clone();
        self.archive_path_input = archive_dir.display().to_string();
        self.start(archive_dir);
        Action::Begin(parent)
    }

    fn start(&self, archive_dir: PathBuf) {
        *self.stage.lock().unwrap() = Stage::Working;
        let (game_dir, stage, progress) = (self.game_dir.clone(), self.stage.clone(), self.progress.clone());
        std::thread::spawn(move || {
            // A panic would leave the window on its progress bar for good.
            let r =
                std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| install(&game_dir, &archive_dir, &progress)))
                    .unwrap_or_else(|_| Err(anyhow::anyhow!("the install stopped unexpectedly (see logcat)")));
            *stage.lock().unwrap() = match r {
                Ok(stash) => Stage::CleanupOffer(stash),
                Err(e) => {
                    log::warn!("first start: {e:#}");
                    Stage::Failed(format!("{e:#}"))
                }
            };
        });
    }

    /// Applies a folder from the system picker (`browse` says which field it was for).
    fn apply_folder_pick(&mut self, what: Browse, dir: &Path) {
        log::info!("folder picked: {}", dir.display());
        match what {
            Browse::Archives => {
                self.archive_path_input = dir.display().to_string();
                let n = installer_parts_in(dir);
                self.note = if n == VOLUMES {
                    format!("Installer: {VOLUMES}/{VOLUMES} in {}", short_path(dir))
                } else {
                    format!(
                        "Found {n}/{VOLUMES} installer parts in {}. Pick the folder that has all five.",
                        short_path(dir)
                    )
                };
            }
            Browse::InstallTo => {
                self.path_input = dir.display().to_string();
                self.game_dir = dir.to_path_buf();
                self.note = format!("Install to {}", short_path(dir));
            }
            Browse::Existing => {
                self.path_input = dir.display().to_string();
                if !crate::android_fs::has_all_files_access() {
                    self.note = "Turn on All files access (step 1), then tap Start.".into();
                } else {
                    match existing(dir) {
                        Ok(game_dir) => {
                            log::info!("picked game files in {}", game_dir.display());
                            self.path_input = game_dir.display().to_string();
                            self.game_dir = game_dir;
                            self.note = "Folder set — tap Start.".into();
                        }
                        Err(e) => {
                            self.note = format!("{e:#} Tap Start to try this path, or pick a parent folder.");
                        }
                    }
                }
            }
        }
    }

    fn open_browser(&mut self, what: Browse, hint: &Path) {
        self.browser_at = crate::client::folder_pick::start_dir(hint);
        self.browse = Some(what);
    }

    /// In-app folder list. Returns true when it drew (the rest of the form stays hidden).
    fn folder_browser(&mut self, ui: &mut egui::Ui) -> bool {
        let Some(what) = self.browse else { return false };
        let title = match what {
            Browse::Archives => "Choose the folder with your FFXI installer downloads",
            _ => "Choose a folder",
        };
        ui.label(egui::RichText::new(title).size(15.0));
        if !self.note.is_empty() {
            ui.label(egui::RichText::new(&self.note).size(13.0).color(egui::Color32::from_rgb(0xe0, 0xa0, 0x70)));
        }
        let cwd = self.browser_at.clone();
        if what == Browse::Archives {
            if ui.button("Open Download folder").clicked() {
                self.browser_at = downloads();
            }
        }
        let listing = crate::client::folder_pick::dir_listing(&cwd);
        if what == Browse::Archives {
            self.archives_files_hint(ui, &cwd);
        }
        match crate::client::folder_pick::browser(ui, &cwd, listing) {
            crate::client::folder_pick::BrowserAction::Up => {
                self.browser_at = crate::client::folder_pick::go_up(&cwd);
            }
            crate::client::folder_pick::BrowserAction::Enter(dir) => self.browser_at = dir,
            crate::client::folder_pick::BrowserAction::Use => {
                self.browse = None;
                self.apply_folder_pick(what, &cwd);
            }
            crate::client::folder_pick::BrowserAction::Cancel => {
                self.browse = None;
                self.note = "No folder was chosen.".into();
            }
            crate::client::folder_pick::BrowserAction::None => {}
        }
        true
    }

    fn archives_files_hint(&self, ui: &mut egui::Ui, cwd: &Path) {
        ui.label(egui::RichText::new("Installer files here:").size(12.0).weak());
        let mut any = false;
        for i in 1..=VOLUMES {
            let want = volume(i);
            let Some(p) = crate::install::find_installer_volume(cwd, i) else {
                ui.label(
                    egui::RichText::new(format!("✗ {want} (missing)"))
                        .size(12.0)
                        .font(egui::FontId::monospace(11.0))
                        .weak(),
                );
                continue;
            };
            any = true;
            let size = std::fs::metadata(&p).map(|m| m.len()).unwrap_or(0);
            let ok = crate::install::installer_volume_ok(&p, i).is_ok();
            let mark = if ok { "✓" } else { "✗" };
            let name = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| want.clone());
            let gb = size as f64 / 1e9;
            ui.label(
                egui::RichText::new(format!("{mark} {name} ({gb:.2} GB)"))
                    .size(12.0)
                    .font(egui::FontId::monospace(11.0)),
            );
        }
        if !any {
            let err = match std::fs::read_dir(cwd) {
                Err(e) => format!("Cannot read this folder: {e}. Turn on All files access (step 1)."),
                Ok(rd) => {
                    let files: Vec<String> = rd
                        .flatten()
                        .filter_map(|e| e.file_type().ok().filter(|t| t.is_file()).map(|_| e))
                        .map(|e| e.file_name().to_string_lossy().into_owned())
                        .collect();
                    if files.is_empty() {
                        "No files here — open a folder that contains the five FFXIFullSetup parts.".into()
                    } else if files.len() <= 6 {
                        format!("No installer volumes here. Files: {}", files.join(", "))
                    } else {
                        format!("No installer volumes here ({n} other files).", n = files.len())
                    }
                }
            };
            ui.label(egui::RichText::new(err).weak().size(11.0));
        }
    }

    /// The window (egui: no game art exists yet).
    pub fn ui(&mut self, ctx: &egui::Context) -> Action {
        self.poll_wipe_job();
        let failed = match &*self.stage.lock().unwrap() {
            Stage::Done => return Action::Ready,
            Stage::Failed(e) => Some(e.clone()),
            _ => None,
        };
        let cleanup = match &*self.stage.lock().unwrap() {
            Stage::CleanupOffer(dir) => Some(dir.clone()),
            _ => None,
        };
        let working = matches!(&*self.stage.lock().unwrap(), Stage::Working);
        let wiping = self.wipe_running();
        let recovery = matches!(&*self.stage.lock().unwrap(), Stage::Recovery);
        let mut action = Action::None;
        let screen = ctx.content_rect();
        let ppp = ctx.pixels_per_point();
        let two_cols = screen.width() / ppp >= 480.0;
        let margin = if two_cols { 14.0 } else { 8.0 };
        let panel_w = (screen.width() - margin * 2.0).max(280.0);
        let pinned_footer = failed.is_some() || cleanup.is_some();
        let scroll_max = (screen.height() - 44.0 - if pinned_footer { 56.0 } else { 0.0 }).max(120.0);
        ctx.layer_painter(egui::LayerId::background()).rect_filled(
            screen,
            0.0,
            egui::Color32::from_rgb(0x12, 0x14, 0x22),
        );
        egui::Area::new(egui::Id::new("first run")).anchor(egui::Align2::CENTER_TOP, [0.0, 6.0]).show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgb(0x1e, 0x22, 0x3a))
                .stroke(egui::Stroke::new(1.0, egui::Color32::from_rgb(0x6a, 0x70, 0xa8)))
                .corner_radius(6.0)
                .inner_margin(12.0)
                .show(ui, |ui| {
                    ui.set_min_width(panel_w);
                    ui.set_max_width(panel_w);
                    ui.style_mut().spacing.button_padding = egui::vec2(10.0, 6.0);
                    ui.label(
                        egui::RichText::new("FINAL FANTASY XI game files")
                            .size(20.0)
                            .color(egui::Color32::from_rgb(0xe8, 0xc8, 0x80)),
                    );
                    ui.add_space(4.0);
                    egui::ScrollArea::vertical()
                        .id_salt("firstrun body")
                        .max_height(scroll_max)
                        .auto_shrink([false, true])
                        .show(ui, |ui| {
                            ui.set_width(ui.available_width());
                            match (&failed, working, &cleanup, recovery) {
                                (Some(e), _, _, _) => self.failed_body(ui, e),
                                (None, true, _, _) => self.progress_ui(ui),
                                (None, false, Some(stash), _) => self.cleanup_offer_body(ui, stash),
                                (None, false, None, true) => self.recovery_ui(ui, &mut action),
                                (None, false, None, false) => {
                                    self.ask_ui_scroll(ui, two_cols);
                                    if self.browse.is_none() {
                                        self.ask_ui_start_row(ui, &mut action);
                                    }
                                }
                            }
                        });
                    if let Some(e) = &failed {
                        self.failed_actions(ui, e, &mut action);
                    } else if let Some(stash) = &cleanup {
                        self.cleanup_offer_actions(ui, stash, &mut action);
                    }
                });
        });
        ctx.request_repaint_after(std::time::Duration::from_millis(if working || wiping { 250 } else { 16 }));
        action
    }

    /// Start loads an existing install, or unpacks the five volumes into Install to.
    fn can_start(&self) -> bool {
        if !crate::android_fs::poll_all_files_access().unwrap_or(false) {
            return false;
        }
        if self.resolved_game_dir().is_some() {
            return true;
        }
        let archives = PathBuf::from(self.archive_path_input.trim());
        poll_installer_ready(&self.install_parent(), &archives) == Some(true)
    }

    fn on_start(&mut self, action: &mut Action) {
        if self.resolved_game_dir().is_some() {
            self.try_start(action);
        } else {
            *action = self.begin_install();
        }
    }

    fn check_install_complete(&mut self, action: &mut Action) {
        self.note.clear();
        if !crate::android_fs::has_all_files_access() {
            self.note = "Turn on All files access in settings, then try again.".into();
            return;
        }
        let parent = self.install_parent();
        let ffxi = parent.join("FINAL FANTASY XI");
        if !install_complete(&ffxi) {
            self.note = install_incomplete_detail(&ffxi);
            return;
        }
        match existing(&parent) {
            Ok(game_dir) => {
                log::info!("recovery: install at {} is complete", game_dir.display());
                self.game_dir = game_dir.clone();
                self.path_input = game_dir.display().to_string();
                *action = Action::Ready;
            }
            Err(e) => self.note = format!("{e:#}"),
        }
    }

    fn recovery_wipe(&mut self, install_parent: &Path) {
        if is_default_install_dir(install_parent) {
            self.start_wipe(install_parent.to_path_buf(), false);
        } else {
            self.wipe_confirm = Some(install_parent.to_path_buf());
            self.note.clear();
        }
    }

    fn recovery_ui(&mut self, ui: &mut egui::Ui, action: &mut Action) {
        if self.wipe_running() {
            self.wipe_progress_ui(ui);
            return;
        }
        let install_parent = self.install_parent();
        let ffxi = install_parent.join("FINAL FANTASY XI");
        ui.label(egui::RichText::new("Install needs attention").size(17.0));
        ui.label(
            egui::RichText::new(
                "Game files on disk look incomplete or stale (a crash, partial install, or a cleared setup flag).",
            )
            .size(13.0)
            .weak(),
        );
        ui.add_space(6.0);
        ui.label(
            egui::RichText::new(short_path(&install_parent))
                .size(13.0)
                .font(egui::FontId::monospace(13.0)),
        );
        ui.label(
            egui::RichText::new(install_incomplete_detail(&ffxi))
                .size(12.0)
                .color(egui::Color32::from_rgb(0xe0, 0xa0, 0x70)),
        );
        if let Some(pending) = self.wipe_confirm.clone() {
            if norm_install_root(&pending) != norm_install_root(&install_parent) {
                self.wipe_confirm = None;
            }
        }
        if let Some(pending) = self.wipe_confirm.clone() {
            ui.add_space(8.0);
            ui.label(
                egui::RichText::new(format!(
                    "Delete everything under {}? This cannot be undone.",
                    short_path(&pending)
                ))
                .size(12.0)
                .color(egui::Color32::from_rgb(0xe0, 0xa0, 0x70)),
            );
            ui.horizontal(|ui| {
                if ui
                    .add_enabled(!self.wipe_running(), egui::Button::new("Delete all"))
                    .clicked()
                {
                    self.start_wipe(pending.clone(), true);
                }
                if ui.add_enabled(!self.wipe_running(), egui::Button::new("Cancel")).clicked() {
                    self.wipe_confirm = None;
                }
            });
        }
        if !self.note.is_empty() {
            ui.add_space(6.0);
            ui.label(egui::RichText::new(&self.note).size(12.0).weak());
        }
        ui.add_space(10.0);
        ui.horizontal_wrapped(|ui| {
            if ui
                .add_enabled(!self.wipe_running(), egui::Button::new(egui::RichText::new("Check install complete").size(15.0)))
                .clicked()
            {
                self.check_install_complete(action);
            }
            if self.wipe_confirm.is_none() {
                let wipe_label = if is_default_install_dir(&install_parent) {
                    "Wipe Game/FFXI folder"
                } else {
                    "Wipe install folder"
                };
                if ui
                    .add_enabled(!self.wipe_running(), egui::Button::new(egui::RichText::new(wipe_label).size(15.0)))
                    .clicked()
                {
                    self.recovery_wipe(&install_parent);
                }
            }
            if ui.add_enabled(!self.wipe_running(), egui::Button::new("Continue to setup")).clicked() {
                *self.stage.lock().unwrap() = Stage::Ask;
                self.note.clear();
            }
            if ui.button("Quit").clicked() {
                *action = Action::Quit;
            }
        });
        if !crate::android_fs::poll_all_files_access().unwrap_or(false) {
            ui.label(egui::RichText::new("All files access is required to check or wipe on-device files.").weak());
        }
    }

    fn ask_ui_scroll(&mut self, ui: &mut egui::Ui, two_cols: bool) {
        if self.folder_browser(ui) {
            return;
        }
        let install_parent = self.install_parent();
        let archives = PathBuf::from(self.archive_path_input.trim());
        let _ = crate::android_fs::poll_all_files_access();
        request_installer_ready(&install_parent, &archives);
        let all_files = crate::android_fs::poll_all_files_access().unwrap_or(false);
        let step = |n: &str| egui::RichText::new(n).size(14.0).color(egui::Color32::LIGHT_GRAY);
        let green = egui::Color32::from_rgb(0x90, 0xc8, 0x90);

        ui.label(step("Step 1"));
        ui.label(egui::RichText::new("All files access").size(15.0));
        ui.horizontal(|ui| {
            if ui.button("Open settings").clicked() {
                crate::android_fs::request_all_files_access();
            }
            let (status, color) =
                if all_files { ("Active", green) } else { ("Not active", egui::Color32::from_rgb(0xe0, 0xa0, 0x70)) };
            ui.label(egui::RichText::new(status).size(13.0).color(color));
        });
        ui.add_space(10.0);
        ui.label(step("Step 2"));
        ui.label(
            egui::RichText::new("Install from one of: Square Enix, local FFXIFullSetup, or an existing install.")
                .size(13.0),
        );
        ui.add_space(6.0);
        ui.horizontal_wrapped(|ui| {
            if ui.button("Square Enix").clicked() {
                crate::android_fs::open_url(SE_CLIENT_DOWNLOAD);
                self.note = "Download all five FFXIFullSetup parts to one folder, then use Local installer.".into();
            }
            if ui.button("Local installer").clicked() {
                self.note = "Choose the folder that holds all five FFXIFullSetup parts.".into();
                if archives.as_os_str().is_empty() {
                    self.open_browser(Browse::Archives, &downloads());
                } else {
                    self.open_browser(Browse::Archives, &archives);
                }
            }
            if ui.button("Existing install").clicked() {
                self.note = "Choose the folder that contains FINAL FANTASY XI.".into();
                self.open_browser(Browse::Existing, &install_parent);
            }
        });
        if !self.note.is_empty() {
            ui.label(egui::RichText::new(&self.note).size(13.0).color(egui::Color32::from_rgb(0xe0, 0xa0, 0x70)));
        }
        ui.add_space(8.0);
        if two_cols {
            let gap = 12.0;
            let col_w = ((ui.available_width() - gap) * 0.5).max(120.0);
            ui.horizontal_top(|ui| {
                ui.allocate_ui_with_layout(egui::vec2(col_w, 0.0), egui::Layout::top_down(egui::Align::Min), |ui| {
                    self.ask_ui_archives(ui, &archives, green);
                });
                ui.add_space(gap);
                ui.allocate_ui_with_layout(egui::vec2(col_w, 0.0), egui::Layout::top_down(egui::Align::Min), |ui| {
                    self.ask_ui_install_to(ui, &install_parent);
                });
            });
        } else {
            self.ask_ui_archives(ui, &archives, green);
            ui.add_space(8.0);
            self.ask_ui_install_to(ui, &install_parent);
        }
    }

    fn ask_ui_archives(&mut self, ui: &mut egui::Ui, archives: &Path, green: egui::Color32) {
        ui.label(egui::RichText::new("Installer downloads").size(14.0));
        ui.label(
            egui::RichText::new(short_path(archives))
                .size(13.0)
                .font(egui::FontId::monospace(13.0)),
        );
        ui.horizontal(|ui| {
            if ui.button("Browse Download").clicked() {
                self.note.clear();
                self.open_browser(Browse::Archives, archives);
            }
            let n = installer_parts_in(archives);
            if n > 0 {
                ui.label(egui::RichText::new(format!("{n}/{VOLUMES} valid")).size(12.0).color(if n == VOLUMES {
                    green
                } else {
                    egui::Color32::from_rgb(0xe0, 0xa0, 0x70)
                }));
            }
        });
    }

    fn ask_ui_install_to(&mut self, ui: &mut egui::Ui, install_parent: &Path) {
        ui.label(egui::RichText::new("Install to").size(14.0));
        ui.label(egui::RichText::new(short_path(install_parent)).size(13.0).font(egui::FontId::monospace(13.0)));
        if ui.button("Browse install folder").clicked() {
            self.note.clear();
            self.open_browser(Browse::InstallTo, install_parent);
        }
        self.ask_ui_wipe_install(ui, install_parent);
    }

    fn ask_ui_wipe_install(&mut self, ui: &mut egui::Ui, install_parent: &Path) {
        if self.wipe_running() {
            ui.add_space(6.0);
            self.wipe_progress_ui(ui);
            return;
        }
        if !install_dir_has_content(install_parent) {
            self.wipe_confirm = None;
            return;
        }
        if let Some(pending) = self.wipe_confirm.clone() {
            if norm_install_root(&pending) != norm_install_root(install_parent) {
                self.wipe_confirm = None;
            }
        }
        if let Some(pending) = self.wipe_confirm.clone() {
            ui.add_space(6.0);
            ui.label(
                egui::RichText::new(format!(
                    "Delete everything under {}? This cannot be undone.",
                    short_path(&pending)
                ))
                .size(12.0)
                .color(egui::Color32::from_rgb(0xe0, 0xa0, 0x70)),
            );
            ui.horizontal(|ui| {
                if ui
                    .add_enabled(!self.wipe_running(), egui::Button::new("Delete all"))
                    .clicked()
                {
                    self.start_wipe(pending.clone(), true);
                }
                if ui.add_enabled(!self.wipe_running(), egui::Button::new("Cancel")).clicked() {
                    self.wipe_confirm = None;
                }
            });
            return;
        }
        ui.add_space(4.0);
        if ui.add_enabled(!self.wipe_running(), egui::Button::new("Remove old install files")).clicked() {
            if is_default_install_dir(install_parent) {
                self.start_wipe(install_parent.to_path_buf(), false);
            } else {
                self.wipe_confirm = Some(install_parent.to_path_buf());
                self.note.clear();
            }
        }
    }

    fn ask_ui_start_row(&mut self, ui: &mut egui::Ui, action: &mut Action) {
        ui.add_space(8.0);
        ui.horizontal(|ui| {
            if ui.button("Quit").clicked() {
                *action = Action::Quit;
            }
            let start = ui.add_enabled(self.can_start(), egui::Button::new(egui::RichText::new("Start").size(18.0)));
            if start.clicked() {
                self.on_start(action);
            }
        });
        if !crate::android_fs::poll_all_files_access().unwrap_or(false) {
            ui.label(egui::RichText::new("All files access must be Active before Start.").size(12.0).weak());
        }
    }

    fn progress_ui(&self, ui: &mut egui::Ui) {
        let p = &self.progress;
        let (done, total) = (p.done.load(Ordering::Relaxed), p.total.load(Ordering::Relaxed));
        let phase = p.phase.lock().unwrap().clone();
        let width = ui.available_width();
        let (left, gap) = ((width * 0.38).clamp(120.0, 280.0), 10.0);
        ui.horizontal_top(|ui| {
            ui.allocate_ui_with_layout(egui::vec2(left, 0.0), egui::Layout::top_down(egui::Align::Min), |ui| {
                ui.label(egui::RichText::new(&phase).size(14.0));
                if total > 0 {
                    ui.label(
                        egui::RichText::new(format!("{:.2} / {:.2} GB", done as f64 / 1e9, total as f64 / 1e9))
                            .size(12.0)
                            .weak(),
                    );
                }
                let note = closing_note(&phase);
                if !note.is_empty() {
                    ui.label(egui::RichText::new(note).weak().size(11.0));
                }
            });
            ui.add_space(gap);
            ui.vertical(|ui| {
                ui.add_space(4.0);
                ui.add(
                    egui::ProgressBar::new(p.fraction())
                        .desired_width((width - left - gap).max(80.0))
                        .fill(egui::Color32::from_rgb(0x9a, 0x7a, 0x40)),
                );
            });
        });
    }

    fn cleanup_offer_body(&mut self, ui: &mut egui::Ui, stash: &Path) {
        ui.label(egui::RichText::new("Installation finished.").size(16.0));
        let gb = crate::install::installer_dir_bytes(stash) as f64 / 1e9;
        ui.label(
            egui::RichText::new(format!(
                "Installer volumes are in {} ({gb:.1} GB). They stay on disk unless you delete them.",
                short_path(stash)
            ))
            .size(13.0)
            .weak(),
        );
    }

    fn cleanup_offer_actions(&mut self, ui: &mut egui::Ui, stash: &Path, action: &mut Action) {
        ui.add_space(8.0);
        ui.horizontal(|ui| {
            if ui.button(egui::RichText::new("Delete installer files").size(16.0)).clicked() {
                if let Err(e) = crate::install::remove_installer_volumes(stash) {
                    log::warn!("installer cleanup: {e:#}");
                }
                *self.stage.lock().unwrap() = Stage::Done;
                *action = Action::Ready;
            }
            if ui.button(egui::RichText::new("Keep files").size(16.0)).clicked() {
                *self.stage.lock().unwrap() = Stage::Done;
                *action = Action::Ready;
            }
        });
    }

    fn failed_body(&mut self, ui: &mut egui::Ui, failed: &str) {
        ui.label("It did not finish:");
        ui.label(egui::RichText::new(failed).weak().size(13.0));
    }

    fn failed_actions(&mut self, ui: &mut egui::Ui, _failed: &str, action: &mut Action) {
        ui.add_space(8.0);
        ui.horizontal_wrapped(|ui| {
            if ui.button("Try again").clicked() {
                *self.stage.lock().unwrap() = Stage::Ask;
                *action = self.begin_install();
            }
            if needs_recovery(&self.install_parent())
                && ui.button("Recovery options").clicked()
            {
                *self.stage.lock().unwrap() = Stage::Recovery;
                self.note.clear();
            }
            if ui.button("Quit").clicked() {
                *action = Action::Quit;
            }
        });
    }
}

enum InstallerPoll {
    Loading,
    Ready(bool),
}

static INSTALLER: Mutex<Option<(PathBuf, PathBuf, InstallerPoll)>> = Mutex::new(None);

fn request_installer_ready(parent: &Path, archives: &Path) {
    let mut g = INSTALLER.lock().unwrap();
    if g.as_ref().is_some_and(|(p, a, s)| p == parent && a == archives && !matches!(s, InstallerPoll::Loading)) {
        return;
    }
    if g.as_ref().is_some_and(|(p, a, s)| p == parent && a == archives && matches!(s, InstallerPoll::Loading)) {
        return;
    }
    let (parent, archives) = (parent.to_path_buf(), archives.to_path_buf());
    *g = Some((parent.clone(), archives.clone(), InstallerPoll::Loading));
    std::thread::spawn(move || {
        let ok = installer_dir(&parent, &archives).is_some_and(|d| crate::install::validate_installer_dir(&d).is_ok());
        *INSTALLER.lock().unwrap() = Some((parent, archives, InstallerPoll::Ready(ok)));
    });
}

fn poll_installer_ready(parent: &Path, archives: &Path) -> Option<bool> {
    request_installer_ready(parent, archives);
    match &*INSTALLER.lock().unwrap() {
        Some((p, a, InstallerPoll::Ready(ok))) if p == parent && a == archives => Some(*ok),
        _ => None,
    }
}

/// Stage volumes under `game_dir/.download`, install, patch; caller offers to delete the stash.
fn install(game_dir: &Path, archive_dir: &Path, p: &Arc<Progress>) -> Result<PathBuf> {
    let stash = game_dir.join(".download");
    crate::android_fs::clear_setup_done();
    std::fs::write(game_dir.join(MARKER), b"")?;
    crate::install::stage_installer_volumes(archive_dir, &stash, p)?;
    let root = game_dir.join("FINAL FANTASY XI");
    let opts = crate::install::Options {
        source: stash.join(volume(1)),
        staging: game_dir.join(".staging"),
        game_dir: game_dir.to_path_buf(),
        verify: true,
        keep_staging: false,
    };
    crate::install::install(&opts, p.clone())?;
    set(p, "Checking for game updates", 0, 0);
    let plan = crate::patch::plan(&root, true, false)?;
    let total: u64 = plan.todo.iter().map(|t| t.2).sum();
    let n = plan.todo.len();
    crate::patch::apply(&root, &plan, 4, &|f, b| set(p, format!("Updating game files ({f} of {n})"), b, total))?;
    set(p, "Installed", 0, 0);
    let _ = std::fs::remove_dir_all(game_dir.join(".staging"));
    std::fs::remove_file(game_dir.join(MARKER))?;
    Ok(stash)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_install_dir_matches_emulated_and_sdcard_aliases() {
        let default = crate::config::default_game_dir();
        assert!(is_default_install_dir(&default));
        assert!(is_default_install_dir(&PathBuf::from("/sdcard/Game/FFXI")));
        assert!(!is_default_install_dir(&PathBuf::from("/storage/emulated/0/Documents/FFXI")));
    }

    #[test]
    fn wipe_refuses_custom_install_root_without_confirmation() {
        let base = std::env::temp_dir().join(format!("vana-wipe-{}", std::process::id()));
        let custom = base.join("MyGame");
        std::fs::create_dir_all(&custom).unwrap();
        std::fs::write(custom.join("leftover.txt"), b"x").unwrap();
        assert!(wipe_install_dir(&custom, false).is_err());
        wipe_install_dir(&custom, true).unwrap();
        assert!(!install_dir_has_content(&custom));
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    fn installer_volumes_must_share_one_folder() {
        let base = std::env::temp_dir().join(format!("vana-installer-{}", std::process::id()));
        let install_parent = base.join("SquareEnix");
        let stash = install_parent.join(".download");
        std::fs::create_dir_all(&stash).unwrap();
        let fake = |path: &Path, part: usize| {
            let mut f = std::fs::File::create(path).unwrap();
            std::io::Write::write_all(&mut f, b"Rar!\x1a\x07\x00").unwrap();
            let len = if part == 1 { 1_000_001u64 } else { 50_000_001 };
            f.set_len(len).unwrap();
        };
        fake(&stash.join(volume(1)), 1);
        fake(&stash.join(volume(2)), 2);
        assert_eq!(best_installer_parts(&install_parent).unwrap().1, 2);
        assert!(installer_dir(&install_parent, Path::new("")).is_none());
        for i in 3..=VOLUMES {
            fake(&stash.join(volume(i)), i);
        }
        assert_eq!(installer_dir(&install_parent, Path::new("")).unwrap(), stash);
        std::fs::remove_dir_all(&base).unwrap();
    }
}
