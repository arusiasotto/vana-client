//! The first-start window on Android: All files access first, then game files from Square Enix's installer volumes
//! the user downloaded (kept where they are), or an install already on the device.

use super::{Action, MARKER, Stage, VOLUMES, closing_note, existing, set, volume};
use crate::install::Progress;
use anyhow::Result;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

/// PlayOnline's page for the five FFXIFullSetup volumes (the browser downloads them; the install reads them locally).
const SE_CLIENT_DOWNLOAD: &str = "https://www.playonline.com/ff11us/download/us/download_a.html";

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
    (1..=VOLUMES).filter(|i| dir.join(volume(*i)).is_file()).count()
}

/// The folder holding all five volumes: the one typed in, else the first found.
fn installer_dir(install_parent: &Path, archives: &Path) -> Option<PathBuf> {
    if !archives.as_os_str().is_empty() && installer_parts_in(archives) == VOLUMES {
        return Some(archives.to_path_buf());
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

/// What the system folder picker is open for.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Browse {
    Existing,
    Archives,
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
    note: String,
}

impl FirstRun {
    pub fn new(game_dir: PathBuf) -> Self {
        // Configs from before shared storage kept the game in app storage.
        let game_dir =
            if crate::config::in_app_storage(&game_dir) { crate::config::default_game_dir() } else { game_dir };
        Self {
            path_input: game_dir.display().to_string(),
            archive_path_input: downloads().join("FFXI-setup").display().to_string(),
            game_dir,
            stage: Arc::new(Mutex::new(Stage::Ask)),
            progress: Arc::new(Progress::default()),
            browse: None,
            note: String::new(),
        }
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
                format!("Found {} of {VOLUMES} parts in {}.", installer_parts_in(&archives), archives.display())
            } else {
                best_installer_parts(&parent)
                    .map(|(d, n)| format!("Found {n} of {VOLUMES} parts in {}.", d.display()))
                    .unwrap_or_else(|| format!("No installer parts in {}.", downloads().display()))
            };
            self.note = format!(
                "{hint} Put all five files (FFXIFullSetup_US.part1.exe and part2–5.rar) in the archives folder, or fix the path above."
            );
            return Action::None;
        };
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
                Ok(()) => Stage::Done,
                Err(e) => {
                    log::warn!("first start: {e:#}");
                    Stage::Failed(format!("{e:#}"))
                }
            };
        });
    }

    /// The system folder picker's answer, once it comes.
    fn take_picked(&mut self, ctx: &egui::Context) -> Option<Action> {
        let what = self.browse?;
        let Some(picked) = crate::client::folder_pick::poll() else {
            ctx.request_repaint_after(std::time::Duration::from_millis(100));
            return None;
        };
        self.browse = None;
        self.note.clear();
        let Some(dir) = picked else {
            self.note = "No folder was chosen.".into();
            return None;
        };
        match what {
            Browse::Archives => self.archive_path_input = dir.display().to_string(),
            Browse::Existing => match existing(&dir) {
                Ok(game_dir) => {
                    self.path_input = game_dir.display().to_string();
                    self.game_dir = game_dir;
                    *self.stage.lock().unwrap() = Stage::Done;
                    return Some(Action::Ready);
                }
                Err(e) => self.note = format!("{e:#}"),
            },
        }
        None
    }

    /// The window (egui: no game art exists yet).
    pub fn ui(&mut self, ctx: &egui::Context) -> Action {
        if let Some(action) = self.take_picked(ctx) {
            return action;
        }
        let failed = match &*self.stage.lock().unwrap() {
            Stage::Done => return Action::Ready,
            Stage::Failed(e) => Some(e.clone()),
            _ => None,
        };
        let working = matches!(&*self.stage.lock().unwrap(), Stage::Working);
        let mut action = Action::None;
        let screen = ctx.content_rect();
        ctx.layer_painter(egui::LayerId::background()).rect_filled(
            screen,
            0.0,
            egui::Color32::from_rgb(0x12, 0x14, 0x22),
        );
        egui::Area::new(egui::Id::unique("first run")).anchor(egui::Align2::CENTER_TOP, [0.0, 10.0]).show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgb(0x1e, 0x22, 0x3a))
                .stroke(egui::Stroke::new(1.0, egui::Color32::from_rgb(0x6a, 0x70, 0xa8)))
                .corner_radius(6.0)
                .inner_margin(12.0)
                .show(ui, |ui| {
                    ui.set_max_width((screen.width() - 28.0).max(320.0));
                    ui.style_mut().spacing.button_padding = egui::vec2(10.0, 6.0);
                    ui.label(
                        egui::RichText::new("FINAL FANTASY XI game files")
                            .size(20.0)
                            .color(egui::Color32::from_rgb(0xe8, 0xc8, 0x80)),
                    );
                    ui.add_space(4.0);
                    egui::ScrollArea::vertical()
                        .max_height((screen.height() - 20.0).max(160.0))
                        .auto_shrink([false; 2])
                        .show(ui, |ui| match (&failed, working) {
                            (Some(e), _) => self.failed_ui(ui, e, &mut action),
                            (None, true) => self.progress_ui(ui),
                            (None, false) => self.ask_ui(ui, &mut action),
                        });
                });
        });
        ctx.request_repaint_after(std::time::Duration::from_millis(if working { 250 } else { 16 }));
        action
    }

    fn ask_ui(&mut self, ui: &mut egui::Ui, action: &mut Action) {
        let busy = self.browse.is_some();
        let install_parent = self.install_parent();
        let archives = PathBuf::from(self.archive_path_input.trim());
        let ready = installer_dir(&install_parent, &archives);
        let all_files = crate::android_fs::has_all_files_access();
        let step = |n: &str| egui::RichText::new(n).size(14.0).color(egui::Color32::LIGHT_GRAY);
        let green = egui::Color32::from_rgb(0x90, 0xc8, 0x90);

        ui.label(step("Step 1"));
        ui.label(egui::RichText::new("All files access").size(15.0));
        ui.horizontal(|ui| {
            if ui.add_enabled(!busy, egui::Button::new("Open settings")).clicked() {
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
            if ui.add_enabled(!busy, egui::Button::new("Square Enix")).clicked() {
                crate::android_fs::open_url(SE_CLIENT_DOWNLOAD);
                self.note = "Download all five FFXIFullSetup parts to one folder, then use Local installer.".into();
            }
            if ui.add_enabled(!busy, egui::Button::new("Local installer")).clicked() {
                if ready.is_some() {
                    *action = self.begin_install();
                } else {
                    self.note = format!(
                        "Put all five parts in the archives folder below (found {}/{VOLUMES}).",
                        installer_parts_in(&archives)
                    );
                }
            }
            if ui.add_enabled(!busy, egui::Button::new("Existing install")).clicked() {
                self.note.clear();
                self.browse = Some(Browse::Existing);
                crate::client::folder_pick::start(&install_parent);
            }
        });
        ui.add_space(4.0);
        ui.label(egui::RichText::new("Local installer paths").size(12.0).weak());
        if let Some(dir) = &ready {
            ui.label(egui::RichText::new(format!("Ready: {VOLUMES}/5 in {}", short_path(dir))).size(12.0).color(green));
        } else if !archives.as_os_str().is_empty() {
            ui.label(
                egui::RichText::new(format!(
                    "Found {}/{VOLUMES} parts in {}",
                    installer_parts_in(&archives),
                    short_path(&archives)
                ))
                .weak()
                .size(12.0),
            );
        }
        ui.horizontal(|ui| {
            ui.label(egui::RichText::new("Archives").size(12.0));
            egui::TextEdit::singleline(&mut self.archive_path_input)
                .desired_width(ui.available_width() * 0.42)
                .font(egui::TextStyle::Monospace)
                .show(ui);
            if ui.add_enabled(!busy, egui::Button::new("…")).clicked() {
                self.note.clear();
                self.browse = Some(Browse::Archives);
                let start = if archives.as_os_str().is_empty() { downloads() } else { archives.clone() };
                crate::client::folder_pick::start(&start);
            }
        });
        ui.horizontal(|ui| {
            ui.label(egui::RichText::new("Install to").size(12.0));
            egui::TextEdit::singleline(&mut self.path_input)
                .desired_width(ui.available_width() * 0.42)
                .font(egui::TextStyle::Monospace)
                .show(ui);
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("Quit").clicked() {
                    *action = Action::Quit;
                }
            });
        });
        if !self.note.is_empty() {
            ui.label(egui::RichText::new(&self.note).size(13.0).color(egui::Color32::from_rgb(0xe0, 0x80, 0x70)));
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

    fn failed_ui(&mut self, ui: &mut egui::Ui, failed: &str, action: &mut Action) {
        ui.label("It did not finish:");
        ui.label(egui::RichText::new(failed).weak().size(13.0));
        ui.horizontal(|ui| {
            if ui.button("Try again").clicked() {
                *self.stage.lock().unwrap() = Stage::Ask;
                *action = self.begin_install();
            }
            if ui.button("Quit").clicked() {
                *action = Action::Quit;
            }
        });
    }
}

/// Install from the volumes in `archive_dir` (left in place), update, clean up.
fn install(game_dir: &Path, archive_dir: &Path, p: &Arc<Progress>) -> Result<()> {
    std::fs::write(game_dir.join(MARKER), b"")?;
    let root = game_dir.join("FINAL FANTASY XI");
    let opts = crate::install::Options {
        source: archive_dir.join(volume(1)),
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
    set(p, "Cleaning up", 0, 0);
    let _ = std::fs::remove_dir_all(game_dir.join(".staging"));
    std::fs::remove_file(game_dir.join(MARKER))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn installer_volumes_must_share_one_folder() {
        let base = std::env::temp_dir().join(format!("vana-installer-{}", std::process::id()));
        let install_parent = base.join("SquareEnix");
        let stash = install_parent.join(".download");
        std::fs::create_dir_all(&stash).unwrap();
        std::fs::write(stash.join(volume(1)), b"stub").unwrap();
        std::fs::write(stash.join(volume(2)), b"stub").unwrap();
        assert_eq!(best_installer_parts(&install_parent).unwrap().1, 2);
        assert!(installer_dir(&install_parent, Path::new("")).is_none());
        for i in 3..=VOLUMES {
            std::fs::write(stash.join(volume(i)), b"stub").unwrap();
        }
        assert_eq!(installer_dir(&install_parent, Path::new("")).unwrap(), stash);
        std::fs::remove_dir_all(&base).unwrap();
    }
}
