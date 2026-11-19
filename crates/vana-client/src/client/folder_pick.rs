//! Android's system folder picker (`VanaClientNativeActivity.requestFolderPicker`). The activity answers with a
//! plain path, read directly under All files access.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

static RESULT: Mutex<Option<Option<PathBuf>>> = Mutex::new(None);

/// Clears any earlier answer and opens the picker near `start`.
pub fn start(start: &Path) {
    *RESULT.lock().unwrap() = None;
    let start = start.to_string_lossy().into_owned();
    // The picker is an activity: started from the Java main thread, never the event loop's (they deadlock).
    super::android_run_on_ui_thread(move || {
        let r = crate::android_fs::with_activity(|env, activity| {
            let hint = env.new_string(&start)?;
            env.call_method(activity, "requestFolderPicker", "(Ljava/lang/String;)V", &[(&hint).into()])?;
            Ok(())
        });
        if let Err(e) = r {
            log::warn!("folder picker: {e:#}");
            complete(None);
        }
    });
}

/// `Some(None)` when the user cancelled, `Some(Some(dir))` with a folder, `None` while the picker is open.
pub fn poll() -> Option<Option<PathBuf>> {
    RESULT.lock().unwrap().clone()
}

fn complete(path: Option<PathBuf>) {
    *RESULT.lock().unwrap() = Some(path);
    super::android_resume_after_activity();
}

#[allow(non_snake_case)]
#[unsafe(no_mangle)]
pub extern "system" fn Java_org_vanaclient_VanaClientNativeActivity_onFolderPicked(
    mut env: jni::JNIEnv<'_>,
    _class: jni::objects::JClass<'_>,
    path: jni::objects::JString<'_>,
) {
    let path = env.get_string(&path).ok().map(|s| PathBuf::from(s.to_string_lossy().into_owned()));
    let _ = std::panic::catch_unwind(|| complete(path));
}

#[allow(non_snake_case)]
#[unsafe(no_mangle)]
pub extern "system" fn Java_org_vanaclient_VanaClientNativeActivity_onFolderCancelled(
    _env: jni::JNIEnv<'_>,
    _class: jni::objects::JClass<'_>,
) {
    let _ = std::panic::catch_unwind(|| complete(None));
}

#[allow(non_snake_case)]
#[unsafe(no_mangle)]
pub extern "system" fn Java_org_vanaclient_VanaClientNativeActivity_nativeAfterUiActivity(
    _env: jni::JNIEnv<'_>,
    _class: jni::objects::JClass<'_>,
) {
    let _ = std::panic::catch_unwind(super::android_resume_after_activity);
}
