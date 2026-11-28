//! Settings' DATs and Mods pages (not retail; the mod manager, XIPivot's job built in). DATs: the installed game-file
//! packs in priority order, each ON / OFF and movable (Move, then Up / Down, Enter to place, Escape to put it back, as
//! the item list's Manual sort), and what is available: the archives found and the catalogue's packs, with Install (or
//! Update). Mods: the installed Lua mods, each ON / OFF (and Update when the catalogue has a newer one; Update All
//! queues them all), the Lua mod archives found, and the standard mods from GitHub (client/catalogue.rs) each with
//! Install, Update or Installed. Archives and the catalogue are read, downloaded and
//! unpacked off the UI thread (crate::modpack). The modern pages also install an archive or a Lua mod's folder picked
//! by hand (`Browse`) and remove a folder.

use super::catalogue::{self, Entry};
use crate::config::ModRef;
use crate::modpack::{self, Pack};
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::mpsc::{Receiver, channel};

pub struct Mods {
    pub packs: Vec<Pack>,
    scan: Option<Receiver<Vec<Pack>>>,
    /// The catalogues' entries (DAT packs, then the standard mods), each to install (Some(false)), to update
    /// (Some(true)) or installed as it is (None).
    pub entries: Vec<(Entry, Option<bool>)>,
    pub server_entries: Vec<(Entry, Option<bool>)>,
    server_keys: Vec<String>,
    list: Option<Receiver<anyhow::Result<Vec<(Entry, Option<bool>)>>>>,
    dat_list: Option<Receiver<anyhow::Result<Vec<(Entry, Option<bool>)>>>>,
    server_list: Option<Receiver<anyhow::Result<Vec<(Entry, Option<bool>)>>>>,
    server_dat_list: Option<Receiver<anyhow::Result<Vec<(Entry, Option<bool>)>>>>,
    /// Server list results waiting until the standard catalogue ids are known (fail closed).
    pending_server_mods: Option<anyhow::Result<Vec<(Entry, Option<bool>)>>>,
    pending_server_dats: Option<anyhow::Result<Vec<(Entry, Option<bool>)>>>,
    /// Why the standard mods' list, or the DAT packs', could not be read.
    pub list_error: Option<String>,
    pub dat_error: Option<String>,
    pub server_list_error: Option<String>,
    pub server_dat_error: Option<String>,
    /// What is being installed, its progress (per mille) and the result (the folder's name).
    installing: Option<(String, Arc<AtomicU32>, Receiver<anyhow::Result<String>>)>,
    /// Catalogue updates waiting for the one installing (Update All), by id.
    queue: Vec<String>,
    /// Mods updated from the catalogue since the caller last took them (a running Lua mod restarts on its new files).
    pub updated: Vec<String>,
    /// A mod being moved: its order before the move.
    pub held: Option<Vec<ModRef>>,
    /// The last install's failure, for the help bar.
    pub error: Option<String>,
    /// The first row shown.
    pub top: usize,
    /// The modern page's file picker, while open.
    pub browse: Option<Browse>,
}

/// Rows shown at once (a page of 296 px from y 36, 34 px apart).
pub const VISIBLE: usize = 7;

/// A row below the installed mods: an archive found, or a catalogue mod.
pub struct Offer {
    /// Its name (with the per cent done while it installs).
    pub label: String,
    /// Install or Update.
    pub button: &'static str,
    pub help: String,
    pub catalogue: bool,
    /// Update All: every update of the page's kind (the last row).
    pub all: bool,
    /// Its place among the archives, then the catalogue's entries.
    at: usize,
}

/// Offer.at of the Update All row.
const ALL: usize = usize::MAX;

/// The catalogue's entries, each with what it is here: to install, to update or installed.
fn statuses(
    list: Vec<Entry>,
    source: catalogue::Source,
    hide_ids: Option<&std::collections::HashSet<String>>,
    server_keys: &[String],
) -> Vec<(Entry, Option<bool>)> {
    list.into_iter()
        .filter(|e| hide_ids.is_none_or(|ids| !ids.contains(&e.id)))
        .map(|e| (e.clone(), catalogue::entry_status(&e, source, server_keys)))
        .collect()
}

/// "1.2 GB", "340 KB".
fn bytes(n: u64) -> String {
    match n {
        n if n >= 1 << 30 => format!("{:.1} GB", n as f64 / (1u64 << 30) as f64),
        n if n >= 1 << 20 => format!("{:.1} MB", n as f64 / (1u64 << 20) as f64),
        n => format!("{} KB", n.div_ceil(1024)),
    }
}

impl Mods {
    /// Starts looking for packs and reading the catalogue.
    pub fn open(server_keys: Vec<String>) -> Self {
        let (tx, rx) = channel();
        std::thread::spawn(move || {
            let _ = tx.send(modpack::scan(&modpack::pack_dirs(), &crate::config::mods_dir()));
        });
        let keys = server_keys.clone();
        let (ltx, lrx) = channel();
        std::thread::spawn(move || {
            let _ = ltx.send(
                catalogue::fetch_from(catalogue::Source::Standard, catalogue::List::Mods, &[])
                    .map(|v| statuses(v, catalogue::Source::Standard, None, &[])),
            );
        });
        let (dtx, drx) = channel();
        std::thread::spawn(move || {
            let _ = dtx.send(
                catalogue::fetch_from(catalogue::Source::Standard, catalogue::List::Dats, &[])
                    .map(|v| statuses(v, catalogue::Source::Standard, None, &[])),
            );
        });
        let sk = server_keys.clone();
        let (sltx, slrx) = channel();
        std::thread::spawn(move || {
            let _ = sltx.send(
                catalogue::fetch_from(catalogue::Source::Server, catalogue::List::Mods, &sk)
                    .map(|v| statuses(v, catalogue::Source::Server, None, &sk)),
            );
        });
        let (sdtx, sdrx) = channel();
        std::thread::spawn(move || {
            let _ = sdtx.send(
                catalogue::fetch_from(catalogue::Source::Server, catalogue::List::Dats, &keys)
                    .map(|v| statuses(v, catalogue::Source::Server, None, &keys)),
            );
        });
        Self {
            packs: Vec::new(),
            scan: Some(rx),
            entries: Vec::new(),
            server_entries: Vec::new(),
            server_keys,
            list: Some(lrx),
            dat_list: Some(drx),
            server_list: Some(slrx),
            server_dat_list: Some(sdrx),
            pending_server_mods: None,
            pending_server_dats: None,
            list_error: None,
            dat_error: None,
            server_list_error: None,
            server_dat_error: None,
            installing: None,
            queue: Vec::new(),
            updated: Vec::new(),
            held: None,
            error: None,
            top: 0,
            browse: None,
        }
    }

    /// No archives and no scan (tests, offscreen shots).
    pub fn empty() -> Self {
        Self {
            packs: Vec::new(),
            scan: None,
            entries: Vec::new(),
            server_entries: Vec::new(),
            server_keys: Vec::new(),
            list: None,
            dat_list: None,
            server_list: None,
            server_dat_list: None,
            pending_server_mods: None,
            pending_server_dats: None,
            list_error: None,
            dat_error: None,
            server_list_error: None,
            server_dat_error: None,
            installing: None,
            queue: Vec::new(),
            updated: Vec::new(),
            held: None,
            error: None,
            top: 0,
            browse: None,
        }
    }

    pub fn refetch_server(&mut self, keys: Vec<String>) {
        self.server_keys = keys.clone();
        self.server_entries.clear();
        self.server_list_error = None;
        self.server_dat_error = None;
        for list in [catalogue::List::Mods, catalogue::List::Dats] {
            catalogue::clear_cache(catalogue::Source::Server, list, &keys);
        }
        self.pending_server_mods = None;
        self.pending_server_dats = None;
        let sk = keys.clone();
        let (ltx, lrx) = channel();
        std::thread::spawn(move || {
            let _ = ltx.send(
                catalogue::fetch_from(catalogue::Source::Server, catalogue::List::Mods, &sk)
                    .map(|v| statuses(v, catalogue::Source::Server, None, &sk)),
            );
        });
        let (dtx, drx) = channel();
        std::thread::spawn(move || {
            let _ = dtx.send(
                catalogue::fetch_from(catalogue::Source::Server, catalogue::List::Dats, &keys)
                    .map(|v| statuses(v, catalogue::Source::Server, None, &keys)),
            );
        });
        self.server_list = Some(lrx);
        self.server_dat_list = Some(drx);
    }

    /// Waits for the scan and the catalogue (offscreen shots).
    pub fn wait_scan(&mut self) {
        if let Some(p) = self.scan.take().and_then(|r| r.recv().ok()) {
            self.packs = p;
        }
        if let Some(l) = self.list.take().and_then(|r| r.recv().ok()) {
            self.take_list(l, false);
        }
        if let Some(l) = self.dat_list.take().and_then(|r| r.recv().ok()) {
            self.take_list(l, true);
        }
    }

    /// Standard mod/DAT ids for hiding colliding server rows; None while the standard lists load; fail closed on error.
    fn standard_hide_ids(&self) -> Option<Option<std::collections::HashSet<String>>> {
        if self.list.is_some() || self.dat_list.is_some() {
            return None;
        }
        if self.list_error.is_some() || self.dat_error.is_some() {
            return Some(None);
        }
        Some(Some(self.entries.iter().map(|(e, _)| e.id.clone()).collect()))
    }

    fn standard_list_holdback_reason(&self) -> String {
        match (&self.list_error, &self.dat_error) {
            (Some(e), _) => format!("the standard mod list could not be read ({e})"),
            (_, Some(e)) => format!("the standard DAT list could not be read ({e})"),
            _ => "the standard list could not be read, so server mods are held back".into(),
        }
    }

    /// Server catalogue is additive: drop any row whose id is already on the standard (lenonk) list.
    fn filter_server_rows(&self, rows: Vec<(Entry, Option<bool>)>) -> Vec<(Entry, Option<bool>)> {
        let Some(hide) = self.standard_hide_ids().flatten() else {
            return Vec::new();
        };
        rows.into_iter().filter(|(e, _)| !hide.contains(&e.id)).collect()
    }

    fn apply_server_list(&mut self, l: anyhow::Result<Vec<(Entry, Option<bool>)>>, dats: bool) {
        if self.standard_hide_ids().is_none() {
            return;
        }
        if self.standard_hide_ids() == Some(None) {
            let msg = self.standard_list_holdback_reason();
            if dats {
                self.server_dat_error = Some(msg);
            } else {
                self.server_list_error = Some(msg);
            }
            return;
        }
        let l = l.map(|rows| self.filter_server_rows(rows));
        self.take_server_list(l, dats);
    }

    fn ingest_server_list(&mut self, l: anyhow::Result<Vec<(Entry, Option<bool>)>>, dats: bool) {
        if self.standard_hide_ids().is_none() {
            if dats {
                self.pending_server_dats = Some(l);
            } else {
                self.pending_server_mods = Some(l);
            }
            return;
        }
        self.apply_server_list(l, dats);
    }

    fn flush_pending_server(&mut self) {
        if self.standard_hide_ids().is_none() {
            return;
        }
        if let Some(l) = self.pending_server_mods.take() {
            self.apply_server_list(l, false);
        }
        if let Some(l) = self.pending_server_dats.take() {
            self.apply_server_list(l, true);
        }
    }

    /// A list come in: its entries kept (the DAT packs' first), or why it could not be read.
    fn take_list(&mut self, l: anyhow::Result<Vec<(Entry, Option<bool>)>>, dats: bool) {
        match l {
            Ok(e) if dats => {
                let rest = std::mem::take(&mut self.entries);
                self.entries = e.into_iter().chain(rest).collect();
            }
            Ok(e) => self.entries.extend(e),
            Err(e) => {
                log::warn!("{} catalogue: {e:#}", if dats { "DAT" } else { "mod" });
                *(if dats { &mut self.dat_error } else { &mut self.list_error }) = Some(format!("{e:#}"));
            }
        }
        self.flush_pending_server();
    }

    fn take_server_list(&mut self, l: anyhow::Result<Vec<(Entry, Option<bool>)>>, dats: bool) {
        match l {
            Ok(e) if dats => {
                let rest = std::mem::take(&mut self.server_entries);
                self.server_entries = e.into_iter().chain(rest).collect();
            }
            Ok(e) => self.server_entries.extend(e),
            Err(e) => {
                log::warn!("server {} catalogue: {e:#}", if dats { "DAT" } else { "mod" });
                *(if dats { &mut self.server_dat_error } else { &mut self.server_list_error }) = Some(format!("{e:#}"));
            }
        }
    }

    fn rows(&self, server: bool) -> &[(Entry, Option<bool>)] {
        if server { &self.server_entries } else { &self.entries }
    }

    /// The archives found of Lua mods (`lua`) or DAT packs, then the catalogue offers for standard or server.
    pub fn offers(&self, lua: bool, server: bool) -> Vec<Offer> {
        let pct =
            |slug: &str, name: String| self.progress(slug).map_or(name.clone(), |pm| format!("{}%  {name}", pm / 10));
        let archives = self.packs.iter().enumerate().filter(|p| p.1.lua.is_some() == lua).map(|(at, p)| {
            let name = p.path.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default();
            let help = match &p.lua {
                Some(l) => format!("Lua mod {} {} in {name}: Install copies it into the mods folder, on. It starts at the next login.", p.slug, l.version),
                None => format!(
                    "{} game file{} in {name}: Install unpacks them into the mods folder, on and first. Takes effect on restart.",
                    p.files,
                    if p.files == 1 { "" } else { "s" }
                ),
            };
            Offer { label: pct(&p.slug, name), button: "Install", help, catalogue: false, all: false, at }
        });
        let n = self.packs.len();
        let listed = self
            .rows(server)
            .iter()
            .enumerate()
            .filter(|e| !lua && e.1.0.kind != "lua")
            .filter_map(|(k, (e, st))| st.map(|u| (k, e, u)))
            .map(|(k, e, update)| {
                let by = if e.authors.is_empty() { String::new() } else { format!(" By {}.", e.authors.join(", ")) };
                let size = if e.size() > 0 { format!(" {}.", bytes(e.size())) } else { String::new() };
                let what = if e.kind == "lua" { "It starts at the next login." } else { "Takes effect on restart." };
                let replace = !server
                    && !update
                    && matches!(
                        catalogue::installed_source(&catalogue::root_of(e), &e.id),
                        Some(catalogue::Source::Server)
                    );
                let verb = if update {
                    "Update"
                } else if replace {
                    "Replace"
                } else {
                    "Install"
                };
                let help = format!(
                    "{}{by}{size} {verb} downloads version {} from GitHub into the mods folder. {what}",
                    e.description.trim(),
                    e.version
                );
                Offer {
                    label: pct(&e.id, format!("{} {}", e.name, e.version)),
                    button: verb,
                    help: help.trim().to_string(),
                    catalogue: true,
                    all: false,
                    at: n + k,
                }
            });
        // Update All: on the Lua page (its updates are on the installed rows), and with two or more DAT packs.
        let ups = self.rows(server).iter().filter(|e| e.1 == Some(true) && (e.0.kind == "lua") == lua).count();
        let all = (ups > usize::from(!lua)).then(|| {
            let what = if lua { "Lua mod" } else { "DAT pack" };
            Offer {
                label: format!("Update all ({ups})"),
                button: "Update All",
                help: format!(
                    "Downloads the newer version of every {what} with one, one after another. {}",
                    if lua { "A mod that is on restarts on it." } else { "Takes effect on restart." }
                ),
                catalogue: true,
                all: true,
                at: ALL,
            }
        });
        archives.chain(listed).chain(all).collect()
    }

    /// The standard Lua mods by name: each entry's place in `entries`.
    fn standard_at(&self) -> Vec<usize> {
        let mut at: Vec<usize> = (0..self.entries.len()).filter(|&k| self.entries[k].0.kind == "lua").collect();
        at.sort_by_key(|&k| self.entries[k].0.name.to_lowercase());
        at
    }

    /// The standard Lua mods by name: each entry and what it is here (to install, to update, installed).
    pub fn standard(&self) -> Vec<(&Entry, Option<bool>)> {
        self.standard_at().into_iter().map(|k| (&self.entries[k].0, self.entries[k].1)).collect()
    }

    /// Standard mod `k` (of `standard`) installed or updated off the UI thread; false when it is installed as it is or
    /// another install runs.
    pub fn install_standard(&mut self, k: usize) -> bool {
        let Some(at) = self.standard_at().get(k).copied().filter(|&at| self.entries[at].1.is_some()) else {
            return false;
        };
        self.install_entry(at, false)
    }

    /// Offer `k` of the Lua mods' (`lua`) or the DAT packs' installed off the UI thread; false while another install
    /// runs.
    pub fn install_offer(&mut self, k: usize, lua: bool, server: bool) -> bool {
        let Some(at) = self.offers(lua, server).get(k).map(|o| o.at) else { return false };
        if at == ALL {
            return self.update_all(lua, Some(server)) > 0;
        }
        if at < self.packs.len() {
            return self.install(at);
        }
        self.install_entry(at - self.packs.len(), server)
    }

    pub fn server_standard(&self) -> Vec<(&Entry, Option<bool>)> {
        let mut at: Vec<usize> =
            (0..self.server_entries.len()).filter(|&k| self.server_entries[k].0.kind == "lua").collect();
        at.sort_by_key(|&k| self.server_entries[k].0.name.to_lowercase());
        at.into_iter().map(|k| (&self.server_entries[k].0, self.server_entries[k].1)).collect()
    }

    pub fn install_server_standard(&mut self, k: usize) -> bool {
        let mut at: Vec<usize> =
            (0..self.server_entries.len()).filter(|&i| self.server_entries[i].0.kind == "lua").collect();
        at.sort_by_key(|&i| self.server_entries[i].0.name.to_lowercase());
        let Some(at) = at.get(k).copied().filter(|&at| self.server_entries[at].1.is_some()) else { return false };
        self.install_entry(at, true)
    }

    fn rows_for_installed_source(&self, id: &str) -> &[(Entry, Option<bool>)] {
        match catalogue::installed_source_for_id(id) {
            Some(catalogue::Source::Server) => &self.server_entries,
            Some(catalogue::Source::Standard) | None => &self.entries,
        }
    }

    /// The newer version the catalogue has of installed mod or pack `id`.
    pub fn update_for(&self, id: &str) -> Option<&str> {
        self.rows_for_installed_source(id)
            .iter()
            .find(|e| e.1 == Some(true) && e.0.id.eq_ignore_ascii_case(id))
            .map(|e| e.0.version.as_str())
    }

    /// The installed Lua mods (`lua`) or DAT packs with a newer version in their install source's catalogue.
    pub fn updates(&self, lua: bool) -> usize {
        let mut ids = std::collections::HashSet::new();
        for e in self.entries.iter().chain(self.server_entries.iter()) {
            if e.1 == Some(true) && (e.0.kind == "lua") == lua && self.update_for(&e.0.id).is_some() {
                ids.insert(e.0.id.as_str());
            }
        }
        ids.len()
    }

    /// Updates of the kind neither installing nor queued: what Update All would start.
    pub fn waiting(&self, lua: bool) -> usize {
        let busy = |id: &str| self.progress(id).is_some() || self.queued(id);
        let mut seen = std::collections::HashSet::new();
        self.entries
            .iter()
            .chain(self.server_entries.iter())
            .filter(|e| e.1 == Some(true) && (e.0.kind == "lua") == lua && !busy(&e.0.id))
            .filter(|e| seen.insert(e.0.id.as_str()))
            .filter(|e| self.update_for(&e.0.id).is_some())
            .count()
    }

    /// Waiting for another update to finish.
    pub fn queued(&self, id: &str) -> bool {
        self.queue.iter().any(|q| q.eq_ignore_ascii_case(id))
    }

    /// Installed mod or pack `id` updated from the catalogue, now or after the install running; false when it has no
    /// update.
    pub fn update(&mut self, id: &str) -> bool {
        let server = matches!(catalogue::installed_source_for_id(id), Some(catalogue::Source::Server));
        let rows = if server { &self.server_entries } else { &self.entries };
        let Some(at) = rows.iter().position(|e| e.1 == Some(true) && e.0.id.eq_ignore_ascii_case(id)) else {
            return false;
        };
        let pick = (at, server);
        if self.installing.as_ref().is_some_and(|i| i.0.eq_ignore_ascii_case(id)) || self.queued(id) {
            return true;
        }
        if self.installing.is_some() {
            let slug =
                if pick.1 { self.server_entries[pick.0].0.id.clone() } else { self.entries[pick.0].0.id.clone() };
            self.queue.push(slug);
            return true;
        }
        self.install_entry(pick.0, pick.1)
    }

    /// Every Lua mod (`lua`) or DAT pack with an update, one after another; how many.
    pub fn update_all(&mut self, lua: bool, server_only: Option<bool>) -> usize {
        let mut ids = Vec::new();
        let mut seen = std::collections::HashSet::new();
        let push =
            |ids: &mut Vec<String>, seen: &mut std::collections::HashSet<String>, rows: &[(Entry, Option<bool>)]| {
                for e in rows.iter().filter(|e| e.1 == Some(true) && (e.0.kind == "lua") == lua) {
                    if seen.insert(e.0.id.clone()) {
                        ids.push(e.0.id.clone());
                    }
                }
            };
        match server_only {
            Some(true) => push(&mut ids, &mut seen, &self.server_entries),
            Some(false) => push(&mut ids, &mut seen, &self.entries),
            None => {
                push(&mut ids, &mut seen, &self.entries);
                push(&mut ids, &mut seen, &self.server_entries);
            }
        }
        ids.into_iter().filter(|id| self.update(id)).count()
    }

    /// Catalogue entry `at` installed off the UI thread; false while another install runs.
    fn install_entry(&mut self, at: usize, server: bool) -> bool {
        let vec = if server { &self.server_entries } else { &self.entries };
        let Some((e, _)) = vec.get(at).cloned() else { return false };
        if self.installing.is_some() {
            return false;
        }
        let progress = Arc::new(AtomicU32::new(0));
        let (tx, rx) = channel();
        let pr = progress.clone();
        let id = e.id.clone();
        let src = if server { catalogue::Source::Server } else { catalogue::Source::Standard };
        let keys = if server { self.server_keys.clone() } else { Vec::new() };
        std::thread::spawn(move || {
            let _ = tx.send(catalogue::install(&e, &catalogue::root_of(&e), &pr, src, &keys));
        });
        self.installing = Some((id, progress, rx));
        true
    }

    /// Per frame: the scan's, the catalogue's and an install's results. A new install goes on top of `mods`, on (an
    /// update keeps its place); true when `mods` changed.
    pub fn tick(&mut self, mods: &mut Vec<ModRef>) -> bool {
        if let Some(Ok(p)) = self.scan.as_ref().map(|r| r.try_recv()) {
            self.packs = p.into_iter().filter(|p| !mods.iter().any(|m| m.name == p.slug)).collect();
            self.scan = None;
        }
        if let Some(Ok(l)) = self.list.as_ref().map(|r| r.try_recv()) {
            self.list = None;
            self.take_list(l, false);
        }
        if let Some(Ok(l)) = self.dat_list.as_ref().map(|r| r.try_recv()) {
            self.dat_list = None;
            self.take_list(l, true);
        }
        if let Some(Ok(l)) = self.server_list.as_ref().map(|r| r.try_recv()) {
            self.server_list = None;
            self.ingest_server_list(l, false);
        }
        if let Some(Ok(l)) = self.server_dat_list.as_ref().map(|r| r.try_recv()) {
            self.server_dat_list = None;
            self.ingest_server_list(l, true);
        }
        let Some((_, _, rx)) = &self.installing else { return false };
        let Ok(res) = rx.try_recv() else { return false };
        self.installing = None;
        // The next queued update starts (an error ends none of them).
        while !self.queue.is_empty() {
            let id = self.queue.remove(0);
            let server = matches!(catalogue::installed_source_for_id(&id), Some(catalogue::Source::Server));
            let hit = if server {
                self.server_entries.iter().position(|e| e.1 == Some(true) && e.0.id == id).map(|at| (at, true))
            } else {
                self.entries.iter().position(|e| e.1 == Some(true) && e.0.id == id).map(|at| (at, false))
            };
            if let Some((at, srv)) = hit
                && self.install_entry(at, srv)
            {
                break;
            }
        }
        match res {
            Ok(slug) => {
                self.packs.retain(|p| p.slug != slug);
                for e in self.entries.iter_mut().chain(self.server_entries.iter_mut()).filter(|e| e.0.id == slug) {
                    if e.1 == Some(true) {
                        self.updated.push(slug.clone());
                    }
                    e.1 = None;
                }
                // The material pack is not a DAT pack: Settings' Material Maps uses it, opened anew.
                if self
                    .entries
                    .iter()
                    .chain(self.server_entries.iter())
                    .any(|e| e.0.id == slug && e.0.kind == "materials")
                {
                    crate::material::reopen();
                } else if !mods.iter().any(|m| m.name == slug) {
                    mods.insert(0, ModRef::new(slug, true));
                }
                self.error = None;
                true
            }
            Err(e) => {
                log::warn!("mods: installing: {e:#}");
                self.error = Some(format!("{e:#}"));
                false
            }
        }
    }

    /// Unpacks pack `i` off the UI thread; false while another one is being installed.
    pub fn install(&mut self, i: usize) -> bool {
        if self.installing.is_some() {
            return false;
        }
        let Some(p) = self.packs.get(i).cloned() else { return false };
        let progress = Arc::new(AtomicU32::new(0));
        let (tx, rx) = channel();
        let pr = progress.clone();
        std::thread::spawn(move || {
            let _ = tx.send(modpack::install(&p, &crate::config::mods_dir(), &pr).map(|_| p.slug));
        });
        self.installing = Some((self.packs[i].slug.clone(), progress, rx));
        true
    }

    /// Reads and unpacks the archive at `path`, or copies the Lua mod folder there, off the UI thread; false while
    /// another one is being installed.
    pub fn install_file(&mut self, path: PathBuf) -> bool {
        if self.installing.is_some() {
            return false;
        }
        let slug = modpack::slug(&path);
        let progress = Arc::new(AtomicU32::new(0));
        let (tx, rx) = channel();
        let pr = progress.clone();
        std::thread::spawn(move || {
            let root = crate::config::mods_dir();
            let r = if path.is_dir() {
                modpack::install_dir(&path, &root)
            } else {
                modpack::pack_of(&path).and_then(|p| modpack::install(&p, &root, &pr).map(|_| p.slug))
            };
            let _ = tx.send(r);
        });
        self.installing = Some((slug, progress, rx));
        true
    }

    /// The catalogue is still being read.
    pub fn loading(&self) -> bool {
        self.list.is_some()
    }

    /// The pack being installed and its per mille done.
    pub fn installing(&self) -> Option<(String, u32)> {
        self.installing.as_ref().map(|i| (i.0.clone(), i.1.load(Ordering::Relaxed)))
    }

    /// The per mille done when pack `slug` is being installed.
    pub fn progress(&self, slug: &str) -> Option<u32> {
        self.installing.as_ref().filter(|i| i.0 == slug).map(|i| i.1.load(Ordering::Relaxed))
    }

    /// Keeps cursor row `row` (1 = the first entry) in view; the page name (0) keeps the list where it is (scrolled
    /// by the wheel or the bar).
    pub fn follow(&mut self, row: usize) {
        if let Some(i) = row.checked_sub(1) {
            if i < self.top {
                self.top = i;
            } else if i >= self.top + VISIBLE {
                self.top = i + 1 - VISIBLE;
            }
        }
    }
}

/// Deletes installed pack `name`'s folder off the UI thread; false when the name is not a folder of the mods folder.
pub fn remove_folder(name: &str) -> bool {
    let root = crate::config::mods_dir();
    let dir = root.join(name);
    if name.is_empty()
        || name.contains(['/', '\\'])
        || name.starts_with('.')
        || dir.parent() != Some(root.as_path())
        || !dir.is_dir()
    {
        return false;
    }
    std::thread::spawn(move || {
        if let Err(e) = std::fs::remove_dir_all(&dir) {
            log::warn!("mods: removing {}: {e}", dir.display());
        } else {
            log::info!("mods: removed {}", dir.display());
        }
    });
    true
}

/// A file picker for an archive or a Lua mod's folder: a folder's sub-folders and archives (zip, 7z, rar), ".." first.
/// For Neural Rendering's DLL (`dll`): .dll and .zip files.
pub struct Browse {
    pub dir: PathBuf,
    pub entries: Vec<(String, Pick)>,
    pub cursor: usize,
    mods: bool,
    dll: bool,
}

/// What a picker entry is.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Pick {
    Folder,
    /// A folder with a mod.toml: picked, not opened.
    Mod,
    Archive,
}

impl Browse {
    /// At the Downloads folder (else home); `mods`: a Lua mod's folder is a pick too.
    pub fn open(mods: bool) -> Self {
        let dir = dirs::download_dir().or_else(dirs::home_dir).unwrap_or_else(|| PathBuf::from("/"));
        let mut b = Self { dir, entries: Vec::new(), cursor: 0, mods, dll: false };
        b.read();
        b
    }

    /// For NVIDIA's nvngx_dlssnr.dll or a zip holding it (Neural Rendering), at the Downloads folder.
    pub fn open_dll() -> Self {
        let dir = dirs::download_dir().or_else(dirs::home_dir).unwrap_or_else(|| PathBuf::from("/"));
        let mut b = Self { dir, entries: Vec::new(), cursor: 0, mods: false, dll: true };
        b.read();
        b
    }

    fn read(&mut self) {
        let mut dirs = Vec::new();
        let mut files = Vec::new();
        if let Ok(rd) = std::fs::read_dir(&self.dir) {
            for e in rd.flatten() {
                let name = e.file_name().to_string_lossy().into_owned();
                if name.starts_with('.') {
                    continue;
                }
                let p = e.path();
                if p.is_dir() {
                    dirs.push((name, if self.mods && p.join("mod.toml").is_file() { Pick::Mod } else { Pick::Folder }));
                } else if self.dll {
                    let ext = p.extension().map(|e| e.to_string_lossy().to_ascii_lowercase());
                    if matches!(ext.as_deref(), Some("dll" | "zip")) {
                        files.push((name, Pick::Archive));
                    }
                } else if modpack::is_archive(&p) {
                    files.push((name, Pick::Archive));
                }
            }
        }
        dirs.sort_by_key(|n| n.0.to_lowercase());
        files.sort_by_key(|n| n.0.to_lowercase());
        self.entries =
            self.dir.parent().map(|_| ("..".to_string(), Pick::Folder)).into_iter().chain(dirs).chain(files).collect();
        self.cursor = 0;
    }

    /// Enter on the cursor's entry: a folder is opened, an archive or a mod's folder is the pick.
    pub fn enter(&mut self) -> Option<PathBuf> {
        let (name, pick) = self.entries.get(self.cursor)?.clone();
        if pick != Pick::Folder {
            return Some(self.dir.join(name));
        }
        let from = self.dir.file_name().map(|f| f.to_string_lossy().into_owned());
        self.dir = if name == ".." { self.dir.parent()?.to_path_buf() } else { self.dir.join(&name) };
        self.read();
        // Back up a level onto the folder left.
        if name == ".."
            && let Some(f) = from
        {
            self.cursor = self.entries.iter().position(|e| e.0 == f).unwrap_or(0);
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str, kind: &str) -> Entry {
        serde_json::from_value(serde_json::json!({"id": id, "name": id, "kind": kind, "version": "2.0.0", "files": []}))
            .unwrap()
    }

    /// The updates by kind, the newer version of one, and the Update All row (Lua: one is enough; DATs: two).
    #[test]
    fn updates_and_update_all_row() {
        let mut m = Mods::empty();
        m.entries = vec![
            (entry("a", "lua"), Some(true)),
            (entry("b", "lua"), None),
            (entry("c", "lua"), Some(false)),
            (entry("p", "pack"), Some(true)),
        ];
        assert_eq!((m.updates(true), m.updates(false), m.waiting(true)), (1, 1, 1));
        assert_eq!((m.update_for("A"), m.update_for("b"), m.update_for("c")), (Some("2.0.0"), None, None));
        let all = |m: &Mods, lua: bool| {
            m.offers(lua, false).iter().filter(|o| o.all).map(|o| o.label.clone()).collect::<Vec<_>>()
        };
        assert_eq!(all(&m, true), ["Update all (1)"]);
        assert!(all(&m, false).is_empty());
        m.entries.push((entry("q", "pack"), Some(true)));
        assert_eq!(all(&m, false), ["Update all (2)"]);
        // A queued update is not waiting, and is not queued twice.
        m.queue.push("a".into());
        assert_eq!(m.waiting(true), 0);
        assert!(m.update("a"));
        assert_eq!(m.queue, ["a"]);
        assert!(!m.update("b"));
    }
}
