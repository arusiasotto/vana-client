//! Neural Rendering's setup (ours; the engine is render/upscale/external.rs, its exports docs/upscaler-engine.md): the
//! engine fetched from the release of this client's version when the player turns it on (Linux x86_64 on Vulkan), and the
//! network's model made from the player's copy of NVIDIA's nvngx_dlssnr.dll: one a Steam game has, one picked in the
//! game, or one dropped in `<data>/nr/dll/`. The DLL is only read by the engine, never kept. Settings shows `state`.

use crate::render::upscale::{self, external};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// The release asset and its size as the row tells it.
pub const ASSET: &str = "vana-client-nr-engine-linux-x86_64.so";

/// Where Neural Rendering stands, as the Settings row shows it.
#[derive(Clone, Debug, PartialEq)]
pub enum State {
    /// It can't run here (the engine's or the device's reason).
    Unavailable(String),
    /// No engine (or one of another release): turning it on downloads it.
    Absent,
    /// The engine coming down: bytes so far, of.
    Downloading(u64, u64),
    /// This client's release has no engine.
    NotInRelease,
    /// The engine needs the model, made from NVIDIA's DLL.
    NeedsDll,
    /// The model being made, 0..1.
    Making(f32),
    /// The model is there: the engine's sentence.
    Ready(String),
    /// The engine's sentence for something it can't do (its folder unwritable), or a download that failed.
    Error(String),
}

/// A DLL that can make the model: where it is, the game it came with, the engine's sentence for it.
#[derive(Clone, Debug, PartialEq)]
pub struct Found {
    pub path: PathBuf,
    pub game: String,
    pub note: String,
}

struct Inner {
    state: State,
    found: Vec<Found>,
    scanning: bool,
    /// The engine arrived after the device was made: the device needs a restart to take it.
    restart: bool,
    /// The last make's or check's sentence when it failed (shown under "Needs a file").
    last: Option<String>,
}

static NR: Mutex<Inner> =
    Mutex::new(Inner { state: State::Absent, found: Vec::new(), scanning: false, restart: false, last: None });

/// The row's state, the DLLs found, whether the scan still runs, whether a restart is needed, the last failure.
pub fn view() -> (State, Vec<Found>, bool, bool, Option<String>) {
    let n = NR.lock().unwrap();
    (n.state.clone(), n.found.clone(), n.scanning, n.restart, n.last.clone())
}

fn set(state: State) {
    NR.lock().unwrap().state = state;
}

/// Whether this platform can fetch the engine (Linux x86_64, the Vulkan backend, no VANA_UPSCALE_ENGINE naming the
/// player's engine).
fn fetchable() -> bool {
    cfg!(all(target_os = "linux", target_arch = "x86_64"))
        && upscale::vulkan()
        && std::env::var_os("VANA_UPSCALE_ENGINE").is_none()
}

/// The state worked out again (Settings opening, a job done); `on`: Neural Rendering is turned on, so an engine of
/// another release is fetched again now. Leaves a download or a make running alone.
pub fn refresh(on: bool) {
    if matches!(view().0, State::Downloading(..) | State::Making(_)) {
        return;
    }
    let state = work_out();
    let needs = state == State::NeedsDll;
    set(state.clone());
    if state == State::Absent && on && external::library_path().exists() {
        turn_on();
    }
    if needs {
        scan();
    }
}

fn work_out() -> State {
    let path = external::library_path();
    let device = upscale::neural_status();
    if !path.exists() || upscale::engine_outdated() {
        return if fetchable() {
            State::Absent
        } else {
            State::Unavailable(device.err().unwrap_or_else(|| "no engine".into()))
        };
    }
    // An engine the device was made without (just fetched) still makes its model; the row asks for a restart.
    if let Err(e) = &device
        && !NR.lock().unwrap().restart
    {
        return State::Unavailable(e.clone());
    }
    match external::tools::model_status() {
        Ok((0, msg)) => State::Ready(msg),
        Ok((1, _)) => State::NeedsDll,
        Ok((_, msg)) => State::Error(msg),
        // An engine without vana_nr_model_status (a player's earlier build) keeps its model itself.
        Err(_) if device.is_ok() => State::Ready(String::new()),
        Err(e) => State::Unavailable(e),
    }
}

/// Turning it on: the engine fetched when it is missing (or of another release). True when it can be on.
pub fn turn_on() -> bool {
    match view().0 {
        State::Absent => {
            set(State::Downloading(0, 0));
            std::thread::spawn(|| {
                let done = fetch();
                if let Err(e) = &done {
                    log::warn!("neural rendering: engine download: {e:#}");
                }
                match done {
                    Ok(true) => {
                        NR.lock().unwrap().restart = upscale::neural_status().is_err();
                        set(State::Absent);
                        refresh(true);
                    }
                    Ok(false) => set(State::NotInRelease),
                    Err(e) => set(State::Error(format!("The engine's download failed: {e:#}."))),
                }
            });
            true
        }
        State::Ready(_) => true,
        _ => false,
    }
}

/// The engine of this client's release (tag v<version>): downloaded beside the old one, its signature checked, then
/// renamed into place (a loaded copy stays mapped; overwriting it in place would corrupt it). False: not in the release.
fn fetch() -> anyhow::Result<bool> {
    let tag = concat!("v", env!("CARGO_PKG_VERSION"));
    let Some((url, size, sig)) = super::updater::tagged_asset(tag, ASSET)? else { return Ok(false) };
    let sig = sig.ok_or_else(|| anyhow::anyhow!("release {tag} has no {ASSET}.sig"))?;
    let dest = external::library_path();
    let part = PathBuf::from(format!("{}.part", dest.display()));
    super::updater::download(&url, &part, &|done, all| set(State::Downloading(done, all.max(size))))?;
    let bytes = std::fs::read(&part)?;
    if !super::updater::signed_asset(tag, ASSET, &bytes, &sig)? {
        let _ = std::fs::remove_file(&part);
        anyhow::bail!("the engine is not signed by the release key");
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&part, std::fs::Permissions::from_mode(0o755))?;
    }
    std::fs::rename(&part, &dest)?;
    log::info!("neural rendering: engine {tag} installed at {}", dest.display());
    Ok(true)
}

/// The drop folder: any .dll or .zip in it is checked like the Steam games' DLLs.
pub fn drop_folder() -> PathBuf {
    crate::config::data_dir().join("nr").join("dll")
}

/// Opens the drop folder in the system's file manager (made first).
pub fn open_drop_folder() {
    let dir = drop_folder();
    let _ = std::fs::create_dir_all(&dir);
    let opener = if cfg!(windows) {
        "explorer"
    } else if cfg!(target_os = "macos") {
        "open"
    } else {
        "xdg-open"
    };
    if let Err(e) = std::process::Command::new(opener).arg(&dir).spawn() {
        log::warn!("neural rendering: opening {}: {e}", dir.display());
    }
}

/// Files already checked, by path, with their size and time then: the engine's answer (Some: usable, its sentence).
type Checked = std::collections::HashMap<PathBuf, (u64, Option<std::time::SystemTime>, Option<String>)>;
static CHECKED: Mutex<Option<Checked>> = Mutex::new(None);
static LAST_SCAN: Mutex<Option<std::time::Instant>> = Mutex::new(None);

/// While the row has the cursor and needs a file: looks again (at most every few seconds), for a DLL dropped in.
pub fn scan_soon() {
    if view().0 != State::NeedsDll {
        return;
    }
    let due = LAST_SCAN.lock().unwrap().is_none_or(|t| t.elapsed().as_secs() >= 4);
    if due {
        scan();
    }
}

/// Looks for usable DLLs in the background: the Steam libraries' games and the drop folder. A file checked before
/// (same size and time) is not checked again.
pub fn scan() {
    {
        let mut n = NR.lock().unwrap();
        if n.scanning {
            return;
        }
        n.scanning = true;
    }
    *LAST_SCAN.lock().unwrap() = Some(std::time::Instant::now());
    std::thread::spawn(|| {
        let mut found = Vec::new();
        for (path, game) in candidates() {
            let meta = std::fs::metadata(&path).ok();
            let key = (meta.as_ref().map_or(0, |m| m.len()), meta.and_then(|m| m.modified().ok()));
            let known = CHECKED.lock().unwrap().get_or_insert_default().get(&path).cloned();
            let note = match known {
                Some((len, time, note)) if (len, time) == key => note,
                _ => {
                    let note = match external::tools::check_dll(&path) {
                        Ok((true, note)) => Some(note),
                        Ok((false, why)) => {
                            log::info!("neural rendering: {}: {why}", path.display());
                            None
                        }
                        Err(e) => {
                            log::info!("neural rendering: {}: {e}", path.display());
                            None
                        }
                    };
                    CHECKED.lock().unwrap().get_or_insert_default().insert(path.clone(), (key.0, key.1, note.clone()));
                    note
                }
            };
            if let Some(note) = note {
                found.push(Found { path, game, note });
            }
        }
        let mut n = NR.lock().unwrap();
        n.found = found;
        n.scanning = false;
    });
}

/// Every nvngx_dlssnr.dll in the Steam libraries (with its game's name) and every .dll / .zip in the drop folder.
fn candidates() -> Vec<(PathBuf, String)> {
    let mut out = Vec::new();
    for lib in steam_libraries() {
        let names = app_names(&lib.join("steamapps"));
        let Ok(rd) = std::fs::read_dir(lib.join("steamapps").join("common")) else { continue };
        for game in rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()) {
            let dir = game.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default();
            let name = names.iter().find(|n| n.0.eq_ignore_ascii_case(&dir)).map_or(dir.clone(), |n| n.1.clone());
            find_dll(&game, 4, &mut |p| out.push((p, name.clone())));
        }
    }
    if let Ok(rd) = std::fs::read_dir(drop_folder()) {
        for p in rd.flatten().map(|e| e.path()) {
            let ext = p.extension().map(|e| e.to_string_lossy().to_ascii_lowercase());
            if matches!(ext.as_deref(), Some("dll" | "zip")) {
                let name = p.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default();
                out.push((p, name));
            }
        }
    }
    out
}

/// nvngx_dlssnr.dll (any case) under `dir`, at most `depth` folders down.
fn find_dll(dir: &Path, depth: u32, hit: &mut dyn FnMut(PathBuf)) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        let Ok(t) = e.file_type() else { continue };
        if t.is_dir() && depth > 0 {
            find_dll(&p, depth - 1, hit);
        } else if t.is_file() && e.file_name().to_string_lossy().eq_ignore_ascii_case("nvngx_dlssnr.dll") {
            hit(p);
        }
    }
}

/// The Steam library folders: each Steam root and the folders its libraryfolders.vdf names (native, ~/.steam and
/// Flatpak Steam), once each.
fn steam_libraries() -> Vec<PathBuf> {
    let home = dirs::home_dir().unwrap_or_default();
    let roots = [
        home.join(".local/share/Steam"),
        home.join(".steam/steam"),
        home.join(".var/app/com.valvesoftware.Steam/.local/share/Steam"),
        PathBuf::from(r"C:\Program Files (x86)\Steam"),
    ];
    let mut out: Vec<PathBuf> = Vec::new();
    let mut add = |p: PathBuf| {
        let c = std::fs::canonicalize(&p).unwrap_or(p);
        if c.join("steamapps").is_dir() && !out.contains(&c) {
            out.push(c);
        }
    };
    for root in roots {
        add(root.clone());
        if let Ok(text) = std::fs::read_to_string(root.join("steamapps").join("libraryfolders.vdf")) {
            for p in vdf_values(&text, "path") {
                add(PathBuf::from(p));
            }
        }
    }
    out
}

/// Every value of `key` in a Valve KeyValues text ("key" "value" lines), backslash escapes undone.
fn vdf_values(text: &str, key: &str) -> Vec<String> {
    let mut out = Vec::new();
    for line in text.lines() {
        let quoted: Vec<&str> = line.split('"').collect();
        // `"key"  "value"` splits into ["", key, ws, value, ""].
        if quoted.len() >= 5 && quoted[1].eq_ignore_ascii_case(key) {
            out.push(quoted[3].replace("\\\\", "\\"));
        }
    }
    out
}

/// Each appmanifest's (installdir, name) in a library's steamapps folder.
fn app_names(steamapps: &Path) -> Vec<(String, String)> {
    let Ok(rd) = std::fs::read_dir(steamapps) else { return Vec::new() };
    rd.flatten()
        .map(|e| e.path())
        .filter(|p| p.file_name().is_some_and(|f| f.to_string_lossy().starts_with("appmanifest_")))
        .filter_map(|p| {
            let text = std::fs::read_to_string(&p).ok()?;
            let dir = vdf_values(&text, "installdir").into_iter().next()?;
            let name = vdf_values(&text, "name").into_iter().next().unwrap_or_else(|| dir.clone());
            Some((dir, name))
        })
        .collect()
}

/// Makes the model from `path` in the background, the row showing the progress; the engine takes the model up by
/// itself when it is done.
pub fn make_model(path: PathBuf) {
    {
        let mut n = NR.lock().unwrap();
        if matches!(n.state, State::Making(_) | State::Downloading(..)) {
            return;
        }
        n.state = State::Making(0.0);
        n.last = None;
    }
    std::thread::spawn(move || {
        let done = external::tools::make_model(&path, &mut |f| set(State::Making(f.clamp(0.0, 1.0))));
        let mut n = NR.lock().unwrap();
        match done {
            Ok((true, msg)) => {
                log::info!("neural rendering: model made from {}: {msg}", path.display());
                n.state = State::Absent;
            }
            Ok((false, msg)) => {
                n.last = Some(msg);
                n.state = State::Absent;
            }
            Err(e) => {
                n.last = Some(e);
                n.state = State::Absent;
            }
        }
        drop(n);
        refresh(false);
    });
}

/// Puts the row in `state` with `found` (the Settings row's tests and `modern-shot`).
pub fn set_for_test(state: State, found: Vec<Found>) {
    let mut n = NR.lock().unwrap();
    (n.state, n.found, n.scanning, n.restart, n.last) = (state, found, false, false, None);
    *LAST_SCAN.lock().unwrap() = Some(std::time::Instant::now());
}

#[cfg(test)]
mod tests {
    use super::*;

    /// libraryfolders.vdf's paths (escaped backslashes undone) and an appmanifest's installdir and name.
    #[test]
    fn steam_files() {
        let lf = r#""libraryfolders"
{
	"0"
	{
		"path"		"/home/a/.local/share/Steam"
		"label"		""
	}
	"1"
	{
		"path"		"D:\\SteamLibrary"
	}
}"#;
        assert_eq!(vdf_values(lf, "path"), ["/home/a/.local/share/Steam", r"D:\SteamLibrary"]);
        let acf = "\"AppState\"\n{\n\t\"appid\"\t\t\"100\"\n\t\"name\"\t\t\"Example Game\"\n\t\"installdir\"\t\t\"ExampleGame\"\n}";
        assert_eq!(vdf_values(acf, "installdir"), ["ExampleGame"]);
        assert_eq!(vdf_values(acf, "name"), ["Example Game"]);
    }

    /// This client's release looked up on GitHub (VANA_NR_TEST_NET set): an existing tag without the engine is None, the
    /// client binary's asset is there.
    #[test]
    fn release_lookup() {
        if std::env::var_os("VANA_NR_TEST_NET").is_none() {
            return;
        }
        assert_eq!(crate::client::updater::tagged_asset("v1.0.15", ASSET).unwrap(), None);
        let own = crate::client::updater::tagged_asset("v1.0.15", "vana-client-linux-x86_64").unwrap().unwrap();
        assert!(own.0.ends_with("/vana-client-linux-x86_64") && own.1 > 1_000_000 && own.2.is_some(), "{own:?}");
    }

    /// The DLL is found in any case, within the depth.
    #[test]
    fn dll_search() {
        let root = std::env::temp_dir().join(format!("nr-find-{}", std::process::id()));
        let deep = root.join("a/b/c");
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::write(deep.join("NVNGX_DLSSNR.DLL"), b"x").unwrap();
        let mut hits = Vec::new();
        find_dll(&root, 4, &mut |p| hits.push(p));
        assert_eq!(hits.len(), 1);
        hits.clear();
        find_dll(&root, 2, &mut |p| hits.push(p));
        assert!(hits.is_empty());
        let _ = std::fs::remove_dir_all(&root);
    }
}
