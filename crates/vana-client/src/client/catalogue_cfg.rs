//! Per-server catalogue repository: one dialog for the login lobby and ModMgr.

use crate::config::{self, ServerCatalogues};

/// Saved `owner/repo` for the first key that has one.
pub fn repo_for_keys(keys: &[String]) -> String {
    let store = ServerCatalogues::load();
    for key in keys {
        if let Some(e) = store.get(key) && !e.repo.is_empty() {
            return e.repo.clone();
        }
    }
    String::new()
}

/// Stores `text` as the catalogue repo for `keys` (clears when empty); returns keys for refetch.
pub fn save_repo(keys: &[String], text: &str) -> Option<Vec<String>> {
    let trimmed = text.trim();
    let repo = normalize_repo(text);
    let mut store = ServerCatalogues::load();
    if repo.is_empty() {
        if !trimmed.is_empty() {
            return None;
        }
        for key in keys {
            store.clear(key);
        }
    } else {
        for key in keys {
            let mut entry = store.get(key).cloned().unwrap_or_default();
            entry.repo = repo.clone();
            store.set(key, entry);
        }
        copy_login_to_search(&mut store, keys);
    }
    if let Err(e) = store.save() {
        log::warn!("server catalogues: {e:#}");
        return None;
    }
    Some(keys.to_vec())
}

pub fn clear_repo(keys: &[String]) -> Option<Vec<String>> {
    let mut store = ServerCatalogues::load();
    for key in keys {
        store.clear(key);
    }
    if let Err(e) = store.save() {
        log::warn!("server catalogues: {e:#}");
        return None;
    }
    Some(keys.to_vec())
}

/// Text field state for the catalogue repo dialog.
pub struct CatalogueDialog {
    pub keys: Vec<String>,
    pub text: String,
    pub label: String,
    open: bool,
}

impl CatalogueDialog {
    pub fn open(keys: Vec<String>) -> Self {
        let store = ServerCatalogues::load();
        let mut text = String::new();
        let mut label = String::new();
        for key in &keys {
            if let Some(e) = store.get(key) {
                if !e.repo.is_empty() {
                    text = e.repo.clone();
                }
                if !e.label.is_empty() {
                    label = e.label.clone();
                }
                if !text.is_empty() {
                    break;
                }
            }
        }
        Self { keys, text, label, open: true }
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    pub fn close(&mut self) {
        self.open = false;
    }

    /// Stores the repo for every active key (clears when text empty); returns keys for refetch.
    pub fn save(&self) -> Option<Vec<String>> {
        save_repo(&self.keys, &self.text)
    }

    pub fn clear(&self) -> Option<Vec<String>> {
        clear_repo(&self.keys)
    }
}

/// GitHub web URL or `owner/repo` → stored `owner/repo`.
pub fn normalize_repo(text: &str) -> String {
    let mut s = text.trim().trim_end_matches('/').trim_end_matches(".git").to_string();
    if let Some(rest) = s.strip_prefix("https://github.com/") {
        s = rest.to_string();
    }
    if let Some(rest) = s.strip_prefix("https://raw.githubusercontent.com/") {
        let parts: Vec<&str> = rest.split('/').collect();
        if parts.len() >= 2 {
            return format!("{}/{}", parts[0], parts[1]);
        }
    }
  if s.contains("://") || s.is_empty() {
        return String::new();
    }
    if s.contains('/') && !s.starts_with('/') {
        return s;
    }
    String::new()
}

/// On first login success: copy login-key entry to search key when missing.
fn copy_login_to_search(store: &mut ServerCatalogues, keys: &[String]) {
    if keys.len() < 2 {
        return;
    }
    let search = &keys[0];
    let login = &keys[1];
    if store.get(search).is_some() {
        return;
    }
    let Some(entry) = store.get(login).cloned() else { return };
    if entry.repo.is_empty() && entry.mods.is_none() && entry.dats.is_none() {
        return;
    }
    store.set(search, entry);
}

pub fn active_keys_cfg(cfg: &config::Config, search: Option<(std::net::Ipv4Addr, u16)>) -> Vec<String> {
    config::active_server_keys(cfg, search)
}

pub fn parse_host_port(host_port: &str) -> Option<(String, u16)> {
    let (host, port) = host_port.rsplit_once(':')?;
    let port: u16 = port.parse().ok()?;
    Some((host.trim().to_ascii_lowercase(), port))
}

pub fn key_from_host_port(host: &str, port: u16) -> String {
    if host.parse::<std::net::Ipv4Addr>().is_ok() {
        config::server_catalogue_key_search(host.parse().unwrap(), port)
    } else {
        config::server_catalogue_key_login(host, port)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_github_url() {
        assert_eq!(normalize_repo("https://github.com/my-org/vana-server-mods"), "my-org/vana-server-mods");
        assert_eq!(normalize_repo("https://github.com/my-org/vana-server-mods.git/"), "my-org/vana-server-mods");
        assert_eq!(normalize_repo("org/repo"), "org/repo");
        assert!(normalize_repo("").is_empty());
        assert!(normalize_repo("https://gitlab.com/foo/bar").is_empty());
        assert!(normalize_repo("not-a-repo").is_empty());
    }
}