//! Calls into `VanaClientNativeActivity` (Java) for storage access and the browser.

use jni::JNIEnv;
use jni::objects::JObject;
use std::path::Path;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

/// App-private marker that setup finished (wiped with **Clear data**; not on shared storage).
#[cfg(target_os = "android")]
fn setup_done_path() -> std::path::PathBuf {
    crate::config::data_dir().join("files").join("setup_done")
}

/// Whether this app install has finished game setup at least once (survives config edits; cleared with the app).
#[cfg(target_os = "android")]
pub fn setup_done() -> bool {
    setup_done_path().is_file()
}

/// Records successful setup. `game_dir` is stored for logging only.
#[cfg(target_os = "android")]
pub fn mark_setup_done(game_dir: &Path) {
    let path = setup_done_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let body = format!("game_dir={}\n", game_dir.display());
    if let Err(e) = std::fs::write(&path, body) {
        log::warn!("writing {}: {e:#}", path.display());
    }
}

/// Clears the setup marker when the install is incomplete or wiped.
#[cfg(target_os = "android")]
pub fn clear_setup_done() {
    let path = setup_done_path();
    if path.is_file() {
        let _ = std::fs::remove_file(path);
    }
}

enum AllFilesPoll {
    Unknown,
    Loading,
    Ready(bool),
}

static ALL_FILES: Mutex<AllFilesPoll> = Mutex::new(AllFilesPoll::Unknown);
static ALL_FILES_STALE: AtomicBool = AtomicBool::new(true);

/// Runs `f` with this thread attached to the JVM and the activity object.
pub fn with_activity<R>(f: impl FnOnce(&mut JNIEnv<'_>, &JObject<'_>) -> anyhow::Result<R>) -> anyhow::Result<R> {
    let act = crate::client::android_activity_ptr().ok_or_else(|| anyhow::anyhow!("no Android activity"))?;
    let vm = ndk_context::android_context().vm();
    anyhow::ensure!(!vm.is_null(), "no JVM");
    // SAFETY: ndk_context holds the process's JavaVM and NativeActivity's global activity reference.
    let vm = unsafe { jni::JavaVM::from_raw(vm.cast())? };
    let mut env = vm.attach_current_thread()?;
    // The pointer is a process-wide global ref. Dropping JObject would DeleteLocalRef it.
    let activity = unsafe { JObject::from_raw(act.as_ptr().cast()) };
    let result = f(&mut env, &activity);
    std::mem::forget(activity);
    result
}

/// Android 11+'s All files access (`MANAGE_EXTERNAL_STORAGE`): the game files and installer volumes are read and
/// written as plain paths on shared storage.
pub fn has_all_files_access() -> bool {
    with_activity(|env, activity| Ok(env.call_method(activity, "hasAllFilesAccess", "()Z", &[])?.z()?)).unwrap_or(false)
}

/// Back from Settings or another activity: the next [`poll_all_files_access`] refresh runs off the UI thread.
pub fn stale_all_files_access() {
    ALL_FILES_STALE.store(true, Ordering::Release);
    let mut g = ALL_FILES.lock().unwrap();
    if !matches!(*g, AllFilesPoll::Loading) {
        *g = AllFilesPoll::Unknown;
    }
}

/// Last known All files access, if any. Kicks a JNI refresh on the stale flag (see [`stale_all_files_access`]).
pub fn poll_all_files_access() -> Option<bool> {
    if ALL_FILES_STALE.swap(false, Ordering::AcqRel) {
        let mut g = ALL_FILES.lock().unwrap();
        if !matches!(*g, AllFilesPoll::Loading) {
            *g = AllFilesPoll::Loading;
            std::thread::spawn(|| {
                let ok = has_all_files_access();
                *ALL_FILES.lock().unwrap() = AllFilesPoll::Ready(ok);
            });
        }
    }
    match &*ALL_FILES.lock().unwrap() {
        AllFilesPoll::Ready(ok) => Some(*ok),
        _ => None,
    }
}

/// Opens the system Settings page for All files access.
pub fn request_all_files_access() {
    if let Err(e) = with_activity(|env, activity| {
        env.call_method(activity, "requestAllFilesAccess", "()V", &[])?;
        Ok(())
    }) {
        log::warn!("All files access settings: {e:#}");
    }
    stale_all_files_access();
}

/// Installed APK `versionName` (for example `1.0.14-rc4`).
pub fn app_version_name() -> Option<String> {
    with_activity(|env, activity| {
        let v = env.call_method(activity, "appVersionName", "()Ljava/lang/String;", &[])?.l()?;
        let j = jni::objects::JString::from(v);
        Ok(env.get_string(&j)?.to_string_lossy().into_owned())
    })
    .ok()
}

/// Cache path for a downloaded update APK (`updateApkPath` in Java).
pub fn update_apk_path() -> anyhow::Result<std::path::PathBuf> {
    with_activity(|env, activity| {
        let v = env.call_method(activity, "updateApkPath", "()Ljava/lang/String;", &[])?.l()?;
        let j = jni::objects::JString::from(v);
        Ok(std::path::PathBuf::from(env.get_string(&j)?.to_string_lossy().into_owned()))
    })
}

/// Opens the system installer for an APK at `path`.
pub fn install_apk(path: &std::path::Path) -> anyhow::Result<()> {
    let path = path.to_string_lossy().into_owned();
    with_activity(|env, activity| {
        let j = env.new_string(&path)?;
        env.call_method(activity, "installApk", "(Ljava/lang/String;)V", &[(&j).into()])?;
        Ok(())
    })
}

/// Opens `url` in the system browser.
pub fn open_url(url: &str) {
    if let Err(e) = with_activity(|env, activity| {
        let url = env.new_string(url)?;
        env.call_method(activity, "openBrowser", "(Ljava/lang/String;)V", &[(&url).into()])?;
        Ok(())
    }) {
        log::warn!("opening {url}: {e:#}");
    }
}
