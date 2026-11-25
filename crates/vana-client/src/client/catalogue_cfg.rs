//! Per-server catalogue repository: one dialog for the login lobby and ModMgr.

use crate::config::{self, ServerCatalogueEntry, ServerCatalogues};

/// Text field state for the catalogue repo dialog.
pub struct CatalogueDialog {
    pub keys: Vec<String>,
    pub text: String,
    pub label: String,
    /// The first frame after open: the repo field takes the keyboard.
    pub focus_field: bool,
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
        Self { keys, text, label, focus_field: true, open: true }
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    pub fn close(&mut self) {
        self.open = false;
    }

    /// Stores the repo for every active key (clears when text empty); returns keys for refetch.
    pub fn save(&self) -> Option<Vec<String>> {
        let repo = normalize_repo(&self.text);
        let mut store = ServerCatalogues::load();
        if repo.is_empty() {
            for key in &self.keys {
                store.clear(key);
            }
        } else {
            let entry = ServerCatalogueEntry {
                repo: repo.clone(),
                label: self.label.trim().to_string(),
                ..Default::default()
            };
            for key in &self.keys {
                store.set(key, entry.clone());
            }
            copy_login_to_search(&mut store, &self.keys);
        }
        if let Err(e) = store.save() {
            log::warn!("server catalogues: {e:#}");
            return None;
        }
        Some(self.keys.clone())
    }

    pub fn clear(&self) -> Option<Vec<String>> {
        let mut store = ServerCatalogues::load();
        for key in &self.keys {
            store.clear(key);
        }
        if let Err(e) = store.save() {
            log::warn!("server catalogues: {e:#}");
            return None;
        }
        Some(self.keys.clone())
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
    }
}