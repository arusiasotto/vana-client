//! One logger on Android: logcat and an optional client log file. `env_logger::init` must not run after
//! another logger is already installed.

use android_log_sys::{__android_log_write, c_int, LogPriority};
use anyhow::Context;
use log::{Level, LevelFilter, Log, Metadata, Record};
use std::ffi::CString;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

struct Tee {
    file: Option<Mutex<std::fs::File>>,
}

fn priority(level: Level) -> LogPriority {
    match level {
        Level::Error => LogPriority::ERROR,
        Level::Warn => LogPriority::WARN,
        Level::Info => LogPriority::INFO,
        Level::Debug => LogPriority::DEBUG,
        Level::Trace => LogPriority::VERBOSE,
    }
}

impl Log for Tee {
    fn enabled(&self, metadata: &Metadata<'_>) -> bool {
        metadata.level() <= log::max_level()
    }

    fn log(&self, record: &Record<'_>) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let line = format!(
            "[{}] {}:{} {}",
            record.level(),
            record.module_path().unwrap_or("?"),
            record.line().unwrap_or(0),
            record.args()
        );
        if let (Ok(tag), Ok(msg)) = (CString::new("vana_client"), CString::new(line.clone())) {
            // SAFETY: tag and msg are NUL-terminated; no format string.
            unsafe {
                __android_log_write(priority(record.level()) as c_int, tag.as_ptr(), msg.as_ptr());
            }
        }
        if let Some(f) = &self.file {
            let _ = writeln!(f.lock().unwrap(), "{line}");
        }
    }

    fn flush(&self) {
        if let Some(f) = &self.file {
            let _ = f.lock().unwrap().flush();
        }
    }
}

fn open_log(client: bool) -> anyhow::Result<Option<Mutex<std::fs::File>>> {
    if !client {
        return Ok(None);
    }
    let path: PathBuf = crate::config::log_path();
    path.parent().map_or(Ok(()), std::fs::create_dir_all).context("creating the log directory")?;
    let _ = std::fs::rename(&path, path.with_extension("prev.log"));
    Ok(Some(Mutex::new(std::fs::File::create(&path).with_context(|| format!("creating {}", path.display()))?)))
}

/// Installs the process logger before any other logging init (`entry()` only).
pub fn init(client: bool) -> anyhow::Result<()> {
    log::set_boxed_logger(Box::new(Tee { file: open_log(client)? }))
        .map_err(|_| anyhow::anyhow!("logger already set"))?;
    log::set_max_level(LevelFilter::Debug);
    Ok(())
}
