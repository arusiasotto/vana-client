//! The catalogues (not retail), kept on GitHub in the client's repository, each version pinned by its files' SHA-256:
//! catalogue/dats.json the DAT packs as archives (the DATs page's Available tab), catalogue/mods.json our standard
//! Lua mods as their files in the repository (assets/mods; Settings > Mods, Download Standard Mods). No mod comes
//! with the client.

use crate::modpack;
use anyhow::{Context, Result, bail};
use serde::Deserialize;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};

/// The list's format this client reads.
const FORMAT: u32 = 1;

/// Version the catalogue installed (one line; older clients read only this).
const MARK: &str = ".catalogue";
const MARK_SOURCE: &str = ".catalogue-source";
const MARK_LIST: &str = ".catalogue-list";

fn parse_source_tag(tag: &str) -> Option<Source> {
    match tag.trim() {
        "standard" => Some(Source::Standard),
        "server" => Some(Source::Server),
        _ => None,
    }
}

/// Saved `owner/repo` for `keys`, or the first key when no repo is set.
pub fn server_list_identity(keys: &[String]) -> String {
    let repo = super::catalogue_cfg::repo_for_keys(keys);
    if !repo.is_empty() {
        return repo;
    }
    keys.first().cloned().unwrap_or_default()
}

fn write_mark(work: &Path, version: &str, source: Source, list_id: Option<&str>) -> std::io::Result<()> {
    std::fs::write(work.join(MARK), version)?;
    let tag = match source {
        Source::Standard => "standard",
        Source::Server => "server",
    };
    std::fs::write(work.join(MARK_SOURCE), tag)?;
    if source == Source::Server {
        if let Some(id) = list_id.filter(|s| !s.is_empty()) {
            std::fs::write(work.join(MARK_LIST), id)?;
        }
    } else {
        let _ = std::fs::remove_file(work.join(MARK_LIST));
    }
    Ok(())
}

fn cache_url_path(cache_file: &Path) -> PathBuf {
    let name = format!("{}.url", cache_file.file_name().and_then(|n| n.to_str()).unwrap_or("list.json"));
    cache_file.with_file_name(name)
}

/// Hosts an archive may come from (VANA_MOD_CATALOGUE lifts this for test lists).
const HOSTS: [&str; 3] = ["https://github.com/", "https://raw.githubusercontent.com/", "https://codeload.github.com/"];

#[derive(Clone, Debug, Deserialize)]
pub struct Entry {
    /// Its folder in the mods folder (a Lua mod's id).
    pub id: String,
    pub name: String,
    /// "lua" (a Lua mod), "pack" (game files) or "materials" (the material pack, material.rs; listed with the DAT packs,
    /// installed as `<data>/materials`; older clients leave it out).
    #[serde(default = "lua")]
    pub kind: String,
    pub version: String,
    #[serde(default)]
    pub authors: Vec<String>,
    #[serde(default)]
    pub description: String,
    /// A Lua mod's `[commands]`, as its mod.toml declares them.
    #[serde(default)]
    pub commands: indexmap::IndexMap<String, crate::modpack::LuaCommand>,
    /// Archives unpacked in order into the one folder (a later one's files replace an earlier one's), or a mod's files
    /// each put at its `path`.
    pub files: Vec<File>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct File {
    pub url: String,
    pub sha256: String,
    #[serde(default)]
    pub size: u64,
    /// A file of the mod (not an archive): where it goes in the mod's folder.
    #[serde(default)]
    pub path: Option<String>,
}

/// A mod file's place in its folder: relative, no "..", no drive or backslash.
fn safe_path(p: &str) -> bool {
    !p.is_empty()
        && !p.starts_with('/')
        && !p.contains(['\\', ':'])
        && p.split('/').all(|c| !c.is_empty() && c != "." && c != "..")
}

fn lua() -> String {
    "lua".into()
}

#[derive(Deserialize)]
struct Listed {
    #[serde(default)]
    format: u32,
    mods: Vec<Entry>,
}

impl Entry {
    /// The archives' bytes in all (0 when the list gives no sizes).
    pub fn size(&self) -> u64 {
        self.files.iter().map(|f| f.size).sum()
    }
}

/// Which list: the DAT packs' or the standard mods'.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum List {
    Dats,
    Mods,
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Source {
    Standard,
    Server,
}

impl Source {
    fn cache_name(self, list: List) -> &'static str {
        match (self, list) {
            (Source::Standard, List::Mods) => "standard/mods.json",
            (Source::Standard, List::Dats) => "standard/dats.json",
            (Source::Server, List::Mods) => "server/mods.json",
            (Source::Server, List::Dats) => "server/dats.json",
        }
    }

    fn cache_path(self, list: List, server_keys: &[String]) -> PathBuf {
        if self == Source::Standard {
            return crate::config::catalogue_dir().join(self.cache_name(list));
        }
        let key = server_keys.first().map(String::as_str).unwrap_or("default");
        let safe: String =
            key.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' }).collect();
        crate::config::catalogue_dir().join(format!("server/{safe}/{}", list.file()))
    }
}

impl List {
    /// Its file in catalogue/ (and the copy kept from the last fetch).
    pub fn file(self) -> &'static str {
        match self {
            List::Dats => "dats.json",
            List::Mods => "mods.json",
        }
    }

    /// The test runs' stand-in list (a URL or a file).
    fn env(self) -> &'static str {
        match self {
            List::Dats => "VANA_DAT_CATALOGUE",
            List::Mods => "VANA_MOD_CATALOGUE",
        }
    }

    fn server_env(self) -> &'static str {
        match self {
            List::Dats => "VANA_SERVER_DAT_CATALOGUE",
            List::Mods => "VANA_SERVER_MOD_CATALOGUE",
        }
    }
}

/// Where a list is read from.
pub fn url(list: List) -> String {
    format!("https://raw.githubusercontent.com/{}/master/catalogue/{}", super::updater::RELEASE_REPO, list.file())
}

fn check(e: &Entry, any_host: bool) -> Result<()> {
    if e.id.is_empty() || !e.id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') {
        bail!("id: letters, digits, _ and - only");
    }
    if !matches!(e.kind.as_str(), "lua" | "pack" | "materials") {
        bail!("kind is \"lua\", \"pack\" or \"materials\" ({:?} given)", e.kind);
    }
    if e.kind == "materials" && e.id != MATERIALS {
        bail!("the material pack's id is {MATERIALS:?}");
    }
    if e.files.is_empty() {
        bail!("no files");
    }
    for f in &e.files {
        if !any_host && !HOSTS.iter().any(|h| f.url.starts_with(h)) {
            bail!("{}: not a GitHub address", f.url);
        }
        if f.sha256.len() != 64 || !f.sha256.bytes().all(|b| b.is_ascii_hexdigit()) {
            bail!("{}: sha256 is 64 hex digits", f.url);
        }
        if f.path.as_deref().is_some_and(|p| !safe_path(p)) {
            bail!("{}: a path inside the mod's folder", f.url);
        }
    }
    if e.files.iter().any(|f| f.path.is_some()) && (e.kind != "lua" || e.files.iter().any(|f| f.path.is_none())) {
        bail!("a Lua mod's files each with a path, or archives only");
    }
    Ok(())
}

/// The list's entries; bad ones are left out (and logged). `any_host`: archives may come from anywhere (test lists).
pub fn parse(text: &str, any_host: bool) -> Result<Vec<Entry>> {
    let l: Listed = serde_json::from_str(text).context("reading the mod catalogue")?;
    if l.format > FORMAT {
        bail!("the mod catalogue's format {} is newer than this client's ({FORMAT})", l.format);
    }
    Ok(l.mods
        .into_iter()
        .filter(|e| match check(e, any_host) {
            Ok(()) => true,
            Err(err) => {
                log::warn!("mod catalogue: {}: {err:#}", e.id);
                false
            }
        })
        .collect())
}

pub fn fetch_from(source: Source, list: List, server_keys: &[String]) -> Result<Vec<Entry>> {
    let want = |e: &Entry| (e.kind != "lua") == (list == List::Dats);
    fetch_all(source, list, server_keys).map(|v| v.into_iter().filter(want).collect())
}

fn migrate_flat_cache(list: List) {
    let dir = crate::config::catalogue_dir();
    let flat = dir.join(list.file());
    let standard = dir.join("standard").join(list.file());
    if flat.is_file() && !standard.is_file() {
        let _ = std::fs::create_dir_all(standard.parent().unwrap_or(Path::new(".")));
        let _ = std::fs::rename(&flat, &standard);
    }
}

fn resolve_url(source: Source, list: List, server_keys: &[String]) -> (Option<String>, bool) {
    match source {
        Source::Standard => {
            let over = std::env::var(list.env()).ok();
            (over.clone().or_else(|| Some(url(list))), over.is_some())
        }
        Source::Server => {
            if let Ok(over) = std::env::var(list.server_env()) {
                return (Some(over), true);
            }
            let store = crate::config::ServerCatalogues::load();
            let u = store.url_for(server_keys, list.file());
            (u.clone(), u.is_some())
        }
    }
}

fn fetch_all(source: Source, list: List, server_keys: &[String]) -> Result<Vec<Entry>> {
    if source == Source::Standard {
        migrate_flat_cache(list);
    }
    let (resolved, any_host) = resolve_url(source, list, server_keys);
    let Some(fetch_url) = resolved else {
        return Ok(Vec::new());
    };
    let kept = source.cache_path(list, server_keys);
    let got = if !fetch_url.starts_with("http") {
        std::fs::read_to_string(&fetch_url).with_context(|| fetch_url.clone())
    } else {
        match super::updater::get_text(&fetch_url) {
            Ok(t) => Ok(t),
            Err(e) if source == Source::Server && fetch_url.contains("/master/") => {
                super::updater::get_text(&fetch_url.replacen("/master/", "/main/", 1)).map_err(|_| e)
            }
            Err(e) => Err(e),
        }
    };
    let keep = source == Source::Standard && std::env::var(list.env()).is_err()
        || source == Source::Server && std::env::var(list.server_env()).is_err();
    match got {
        Ok(text) => {
            let entries = parse(&text, any_host)?;
            if keep {
                let _ = std::fs::create_dir_all(kept.parent().unwrap_or(Path::new(".")));
                let _ = std::fs::write(&kept, &text);
                if source == Source::Server {
                    let _ = std::fs::write(cache_url_path(&kept), &fetch_url);
                }
            }
            Ok(entries)
        }
        Err(e) if keep => {
            if source == Source::Server {
                let url_file = cache_url_path(&kept);
                let cached_url = std::fs::read_to_string(&url_file).unwrap_or_default();
                if cached_url.trim() != fetch_url {
                    log::info!("mod catalogue ({source:?}): {e:#}; cached list is for another repo");
                    return Err(e);
                }
            }
            log::info!("mod catalogue ({source:?}): {e:#}; using the last copy");
            parse(&std::fs::read_to_string(&kept).map_err(|_| e)?, any_host)
        }
        Err(e) => Err(e),
    }
}

pub fn clear_cache(source: Source, list: List, server_keys: &[String]) {
    let kept = source.cache_path(list, server_keys);
    let _ = std::fs::remove_file(&kept);
    let _ = std::fs::remove_file(cache_url_path(&kept));
}

/// Drops cached server lists for `keys` (after the saved repo URL changes).
pub fn clear_server_cache_for_keys(keys: &[String]) {
    for list in [List::Mods, List::Dats] {
        clear_cache(Source::Server, list, keys);
    }
}

/// The material pack's id: its folder in the data folder (material::dir).
pub const MATERIALS: &str = "materials";

/// Where an entry installs: the data folder for the material pack, else the mods folder.
pub fn root_of(e: &Entry) -> std::path::PathBuf {
    if e.kind == "materials" { crate::config::data_dir() } else { crate::config::mods_dir() }
}

pub fn installed_source(root: &Path, id: &str) -> Option<Source> {
    let dir = root.join(id);
    if !dir.is_dir() {
        return None;
    }
    if let Ok(tag) = std::fs::read_to_string(dir.join(MARK_SOURCE)) {
        return parse_source_tag(&tag);
    }
    let Ok(mark) = std::fs::read_to_string(dir.join(MARK)) else {
        return None;
    };
    mark.lines().nth(1).and_then(parse_source_tag)
}

pub fn installed_server_list_id(root: &Path, id: &str) -> Option<String> {
    let dir = root.join(id);
    if !dir.is_dir() {
        return None;
    }
    std::fs::read_to_string(dir.join(MARK_LIST)).ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}

pub fn installed_source_for_id(id: &str) -> Option<Source> {
    installed_source(&crate::config::mods_dir(), id).or_else(|| installed_source(&crate::config::data_dir(), id))
}

/// Install, update or installed-as-is for one catalogue row (Settings, Modmgr, login update count).
pub fn entry_status(e: &Entry, source: Source, server_keys: &[String]) -> Option<bool> {
    let root = root_of(e);
    let have = installed(&root, &e.id);
    let inst_src = installed_source(&root, &e.id);
    match (have.as_deref(), inst_src) {
        (None, _) => offer(e, None),
        (Some(v), Some(s)) if s == source => {
            if source == Source::Server {
                let cur = server_list_identity(server_keys);
                match installed_server_list_id(&root, &e.id) {
                    Some(inst) if inst != cur => None,
                    _ => offer(e, Some(v)),
                }
            } else {
                offer(e, Some(v))
            }
        }
        (Some(v), None) if source == Source::Standard => offer(e, Some(v)),
        (Some(v), Some(Source::Server)) if source == Source::Standard => offer(e, Some(v)).or(Some(false)),
        (Some(_), _) => None,
    }
}

/// The version installed in `root/id`: the catalogue's mark, else its mod.toml's; "" for a folder with neither.
pub fn installed(root: &Path, id: &str) -> Option<String> {
    let dir = root.join(id);
    if !dir.is_dir() {
        return None;
    }
    if let Ok(v) = std::fs::read_to_string(dir.join(MARK)) {
        return v.lines().next().map(|s| s.trim().to_string());
    }
    let text = std::fs::read_to_string(dir.join("mod.toml")).ok();
    Some(text.and_then(|t| modpack::lua_manifest(&t, id).ok()).map_or_else(String::new, |m| m.1))
}

/// Whether to offer the entry: Some(false) to install, Some(true) to update (a newer version than `have`).
pub fn offer(e: &Entry, have: Option<&str>) -> Option<bool> {
    match have {
        None => Some(false),
        Some(v) if !v.is_empty() && super::updater::newer(&e.version, v) => Some(true),
        _ => None,
    }
}

fn sha256(path: &Path) -> Result<String> {
    let mut f = std::fs::File::open(path)?;
    let mut ctx = ring::digest::Context::new(&ring::digest::SHA256);
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        ctx.update(&buf[..n]);
    }
    Ok(hex::encode(ctx.finish()))
}

/// The archive kind's extension from its address (a GitHub source zip has none: zip).
fn ext(url: &str) -> &'static str {
    let last = url.rsplit('/').next().unwrap_or("").to_ascii_lowercase();
    ["7z", "rar"].into_iter().find(|x| last.ends_with(&format!(".{x}"))).unwrap_or("zip")
}

/// A standard mod's files downloaded and checked into `work`, each at its path.
fn fetch_files(e: &Entry, work: &Path, progress: &AtomicU32) -> Result<()> {
    let n = e.files.len().max(1) as u64;
    for (k, f) in e.files.iter().enumerate() {
        let rel = f.path.as_deref().unwrap_or_default();
        let file = work.join(rel);
        if let Some(dir) = file.parent() {
            std::fs::create_dir_all(dir)?;
        }
        super::updater::download(&f.url, &file, &|_, _| {})?;
        if sha256(&file)? != f.sha256.to_ascii_lowercase() {
            bail!("{} is not the file the catalogue names (its SHA-256 differs); not installed", f.url);
        }
        progress.store(((k as u64 + 1) * 1000 / n).min(999) as u32, Ordering::Relaxed);
    }
    if !work.join("mod.toml").is_file() {
        bail!("{} has no mod.toml", e.id);
    }
    Ok(())
}

/// Server catalogue entries must name the same mod as mod.toml (otherwise grants keyed by manifest id could apply to
/// the wrong folder).
fn require_manifest_id(work: &Path, catalogue_id: &str, source: Source) -> Result<()> {
    if source != Source::Server || !work.join("mod.toml").is_file() {
        return Ok(());
    }
    let text = std::fs::read_to_string(work.join("mod.toml"))?;
    let (manifest_id, _) = modpack::lua_manifest(&text, catalogue_id)?;
    if manifest_id != catalogue_id {
        bail!("catalogue lists {catalogue_id} but mod.toml names {manifest_id}; not installed");
    }
    Ok(())
}

/// Downloads, checks and unpacks an entry's archives (or puts its files) into `root/<id>` (an older copy replaced).
/// `progress` counts per mille: each archive's download is four fifths of its share, its unpacking the rest. Standard
/// catalogue Lua mods are given the permissions they ask for at install; server mods are not (prompt on first load).
/// Returns the folder's name.
pub fn install(e: &Entry, root: &Path, progress: &AtomicU32, source: Source, server_keys: &[String]) -> Result<String> {
    let list_id = (source == Source::Server).then(|| server_list_identity(server_keys));
    if source == Source::Server {
        super::lua::clear_grants_for_mod(&e.id);
    }
    if e.files.iter().any(|f| f.path.is_some()) {
        std::fs::create_dir_all(root)?;
        let work = modpack::work_dir(root, &e.id)?;
        if let Err(err) = fetch_files(e, &work, progress) {
            let _ = std::fs::remove_dir_all(&work);
            return Err(err);
        }
        if let Err(err) = require_manifest_id(&work, &e.id, source) {
            let _ = std::fs::remove_dir_all(&work);
            return Err(err);
        }
        write_mark(&work, &e.version, source, list_id.as_deref())?;
        modpack::place(&work, &root.join(&e.id))?;
        if source == Source::Standard {
            super::lua::grant_manifest(&root.join(&e.id));
        }
        progress.store(1000, Ordering::Relaxed);
        log::info!("mods: installed {} {} from the {:?}", e.id, e.version, source);
        return Ok(e.id.clone());
    }
    let downloads = crate::config::catalogue_dir().join("downloads");
    std::fs::create_dir_all(&downloads)?;
    std::fs::create_dir_all(root)?;
    let share = |f: &File| if e.size() > 0 { f.size } else { 1 };
    let total: u64 = e.files.iter().map(share).sum::<u64>().max(1);
    let work = modpack::work_dir(root, &e.id)?;
    let mut base = 0u64;
    let mut each = || -> Result<()> {
        for (k, f) in e.files.iter().enumerate() {
            let part = share(f);
            let file = downloads.join(format!("{}-{k}.{}", e.id, ext(&f.url)));
            let at = |x: u64| progress.store((x * 1000 / total).min(999) as u32, Ordering::Relaxed);
            let of =
                |done: u64, all: u64, share: u64| (done.min(all) as u128 * share as u128 / all.max(1) as u128) as u64;
            super::updater::download(&f.url, &file, &|done, all| at(base + of(done, all, part * 4 / 5)))?;
            if sha256(&file)? != f.sha256.to_ascii_lowercase() {
                let _ = std::fs::remove_file(&file);
                bail!("{} is not the file the catalogue names (its SHA-256 differs); not installed", f.url);
            }
            let pack = if e.kind == "materials" {
                modpack::materials_pack(&file)?
            } else {
                modpack::pack_named(&file, Some(&e.id))?
            };
            match (&pack.lua, e.kind == "lua") {
                (Some(_), true) if pack.slug != e.id => bail!("{} holds mod {}, not {}", f.url, pack.slug, e.id),
                (Some(_), false) => bail!("{} holds a Lua mod, not game files", f.url),
                (None, true) => bail!("{} holds no mod.toml", f.url),
                _ => {}
            }
            modpack::unpack(&pack, &work, &mut |done, all| {
                at(base + part * 4 / 5 + of(done, all, part - part * 4 / 5))
            })?;
            let _ = std::fs::remove_file(&file);
            base += part;
        }
        Ok(())
    };
    if let Err(err) = each() {
        let _ = std::fs::remove_dir_all(&work);
        return Err(err);
    }
    if let Err(err) = require_manifest_id(&work, &e.id, source) {
        let _ = std::fs::remove_dir_all(&work);
        return Err(err);
    }
    write_mark(&work, &e.version, source, list_id.as_deref())?;
    modpack::place(&work, &root.join(&e.id))?;
    if source == Source::Standard {
        super::lua::grant_manifest(&root.join(&e.id));
    }
    progress.store(1000, Ordering::Relaxed);
    log::info!("mods: installed {} {} from the {:?}", e.id, e.version, source);
    Ok(e.id.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIST: &str = r#"{"format": 1, "mods": [
        {"id": "good", "name": "Good", "version": "1.2.0", "files": [{"url": "https://github.com/a/b/releases/download/v1.2.0/good.zip", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff", "size": 10}]},
        {"id": "elsewhere", "name": "Elsewhere", "version": "1.0.0", "files": [{"url": "https://example.com/x.zip", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"}]},
        {"id": "bad/id", "name": "Bad", "version": "1.0.0", "files": [{"url": "https://github.com/a/b/x.zip", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"}]},
        {"id": "nohash", "name": "No hash", "version": "1.0.0", "files": [{"url": "https://github.com/a/b/x.zip", "sha256": "abc"}]}
    ]}"#;

    /// The material pack is kept only under its id, with the DAT packs.
    #[test]
    fn material_pack_entry() {
        let list = r#"{"format": 1, "mods": [
            {"id": "materials", "name": "M", "kind": "materials", "version": "1", "files": [{"url": "https://github.com/a/b/m.7z", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"}]},
            {"id": "other", "name": "O", "kind": "materials", "version": "1", "files": [{"url": "https://github.com/a/b/o.7z", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"}]}
        ]}"#;
        let got = parse(list, false).unwrap();
        assert_eq!(got.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(), ["materials"]);
        assert_eq!(root_of(&got[0]), crate::config::data_dir());
    }

    /// Only GitHub archives with a full SHA-256 and a clean id are kept; a test list may name any host.
    #[test]
    fn entries_checked() {
        let ids = |v: Vec<Entry>| v.into_iter().map(|e| e.id).collect::<Vec<_>>();
        assert_eq!(ids(parse(LIST, false).unwrap()), ["good"]);
        assert_eq!(ids(parse(LIST, true).unwrap()), ["good", "elsewhere"]);
        assert!(parse(r#"{"format": 2, "mods": []}"#, false).is_err());
    }

    /// The repository's lists read whole under the GitHub-only rule: DAT packs (and the material pack) in dats.json,
    /// Lua mods in mods.json.
    #[test]
    fn committed_list() {
        for (text, pack) in [
            (include_str!("../../../../catalogue/dats.json"), true),
            (include_str!("../../../../catalogue/mods.json"), false),
        ] {
            let n = serde_json::from_str::<serde_json::Value>(text).unwrap()["mods"].as_array().unwrap().len();
            let got = parse(text, false).unwrap();
            assert_eq!(got.len(), n);
            assert!(got.iter().all(|e| (e.kind != "lua") == pack));
        }
    }

    /// Every standard mod (assets/mods) is listed with each of its files at its SHA-256, as GitHub serves them from
    /// master. VANA_WRITE_CATALOGUE=1 writes the list anew (the DAT packs' entries kept).
    #[test]
    fn standard_mods_listed() {
        let crate_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
        let list_path = crate_dir.join("../../catalogue/mods.json");
        let mut list: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&list_path).unwrap()).unwrap();
        let want = standard_entries(&crate_dir.join("assets/mods"));
        let lua = |l: &serde_json::Value| {
            l["mods"].as_array().unwrap().iter().filter(|e| e["kind"] == "lua").cloned().collect::<Vec<_>>()
        };
        // A mod whose files changed keeps no version: installed copies would never be offered the update.
        let unbumped: Vec<String> = want
            .iter()
            .filter(|w| {
                lua(&list)
                    .iter()
                    .any(|o| o["id"] == w["id"] && o["version"] == w["version"] && o["files"] != w["files"])
            })
            .map(|w| format!("{} {}", w["id"].as_str().unwrap_or(""), w["version"].as_str().unwrap_or("")))
            .collect();
        assert!(unbumped.is_empty(), "files changed without a version bump (raise it in mod.toml): {unbumped:?}");
        if std::env::var_os("VANA_WRITE_CATALOGUE").is_some() {
            let packs: Vec<serde_json::Value> =
                list["mods"].as_array().unwrap().iter().filter(|e| e["kind"] != "lua").cloned().collect();
            list["mods"] = packs.into_iter().chain(want).collect();
            std::fs::write(&list_path, serde_json::to_string_pretty(&list).unwrap() + "\n").unwrap();
            return;
        }
        assert!(
            lua(&list) == want,
            "catalogue/mods.json is out of date: VANA_WRITE_CATALOGUE=1 cargo test standard_mods_listed"
        );
        assert_eq!(
            parse(&serde_json::to_string(&list).unwrap(), false).unwrap().iter().filter(|e| e.kind == "lua").count(),
            want.len()
        );
    }

    fn standard_entries(mods: &Path) -> Vec<serde_json::Value> {
        #[derive(Deserialize)]
        struct M {
            name: String,
            version: String,
            #[serde(default)]
            description: String,
            #[serde(default)]
            authors: Vec<String>,
            #[serde(default)]
            commands: serde_json::Map<String, serde_json::Value>,
        }
        fn walk(root: &Path, dir: &Path, out: &mut Vec<String>) {
            for e in std::fs::read_dir(dir).unwrap().flatten() {
                let p = e.path();
                if e.file_name().to_string_lossy().starts_with('.') {
                    continue;
                }
                // A mod's tests (tests/ beside mod.toml) stay in the repository.
                if p.is_dir() && dir == root && e.file_name() == "tests" {
                    continue;
                }
                if p.is_dir() {
                    walk(root, &p, out);
                } else {
                    out.push(p.strip_prefix(root).unwrap().to_string_lossy().replace('\\', "/"));
                }
            }
        }
        let mut ids: Vec<String> = std::fs::read_dir(mods)
            .unwrap()
            .flatten()
            .filter(|e| e.path().join("mod.toml").is_file())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        ids.sort();
        ids.iter()
            .map(|id| {
                let dir = mods.join(id);
                let m: M = toml::from_str(&std::fs::read_to_string(dir.join("mod.toml")).unwrap()).unwrap();
                let mut rels = Vec::new();
                walk(&dir, &dir, &mut rels);
                rels.sort();
                let files: Vec<serde_json::Value> = rels
                    .iter()
                    .map(|rel| {
                        let p = dir.join(rel);
                        let url = format!("https://raw.githubusercontent.com/{}/master/crates/vana-client/assets/mods/{id}/{rel}", super::super::updater::RELEASE_REPO);
                        serde_json::json!({"path": rel, "url": url, "sha256": sha256(&p).unwrap(), "size": std::fs::metadata(&p).unwrap().len()})
                    })
                    .collect();
                let mut e = serde_json::json!({"id": id, "name": m.name, "kind": "lua", "version": m.version, "authors": m.authors, "description": m.description, "files": files});
                if !m.commands.is_empty() {
                    e["commands"] = serde_json::Value::Object(m.commands);
                }
                e
            })
            .collect()
    }

    /// A standard mod's files: each needs a safe path; archives and files do not mix.
    #[test]
    fn mod_files_checked() {
        let f = |path: &str| {
            format!(
                r#"{{"url": "https://raw.githubusercontent.com/a/b/master/x", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff", "path": "{path}"}}"#
            )
        };
        let list = |files: &str| {
            format!(r#"{{"format": 1, "mods": [{{"id": "m", "name": "M", "version": "1.0.0", "files": [{files}]}}]}}"#)
        };
        assert_eq!(parse(&list(&format!("{}, {}", f("init.lua"), f("src/a.lua"))), false).unwrap().len(), 1);
        for bad in ["../x.lua", "/etc/x", "src/../../x", "c:x"] {
            assert!(parse(&list(&f(bad)), false).unwrap().is_empty(), "{bad}");
        }
        assert!(!safe_path("a\\b") && !safe_path("") && !safe_path("a//b") && safe_path("src/a.lua"));
    }

    #[test]
    fn offers() {
        let e = parse(LIST, false).unwrap().remove(0);
        assert_eq!(offer(&e, None), Some(false));
        assert_eq!(offer(&e, Some("1.1.9")), Some(true));
        assert_eq!(offer(&e, Some("1.2.0")), None);
        assert_eq!(offer(&e, Some("")), None);
        assert_eq!(ext("https://github.com/a/b/releases/download/v1/x.7z"), "7z");
        assert_eq!(ext("https://codeload.github.com/a/b/zip/refs/tags/v1"), "zip");
    }

    #[test]
    fn source_tag_parsed() {
        assert_eq!(parse_source_tag("standard"), Some(Source::Standard));
        assert_eq!(parse_source_tag("server"), Some(Source::Server));
        assert!(parse_source_tag("other").is_none());
    }
}
