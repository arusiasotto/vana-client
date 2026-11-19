#[cfg_attr(any(target_os = "linux", target_os = "netbsd", target_os = "android"), path = "linux.rs")]
#[cfg_attr(not(any(target_os = "linux", target_os = "netbsd", target_os = "android")), path = "all.rs")]
mod os;

pub(crate) use os::*;
