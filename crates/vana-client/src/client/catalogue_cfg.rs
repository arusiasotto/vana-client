//! Per-server catalogue repository: login overlay and Modmgr inline field.

use crate::config::{self, ServerCatalogues};

/// Saved `owner/repo` for the first key that has one.
pub fn repo_for_keys(keys: &[String]) -> String {
    let store = ServerCatalogues::load();
    for key in keys {
        if let Some(e) = store.get(key)
            && !e.repo.is_empty()
        {
            return e.repo.clone();
        }
    }
    String::new()
}

/// Login host-port plus search IP-port keys explicitly paired with this login (not every `rest_models` server).
pub fn catalogue_keys_for_cfg(cfg: &config::Config) -> Vec<String> {
    let login = config::server_catalogue_key_login(&cfg.server, cfg.auth_port);
    let mut keys = vec![login.clone()];
    let store = ServerCatalogues::load();
    for (k, e) in store.list() {
        if is_search_key(k) && !keys.contains(k) && e.paired_login == login {
            keys.push(k.clone());
        }
    }
    keys
}

fn is_search_key(key: &str) -> bool {
    let Some((host, port)) = key.rsplit_once('-') else {
        return false;
    };
    host.parse::<std::net::Ipv4Addr>().is_ok() && port.parse::<u16>().is_ok()
}

fn login_key_in(keys: &[String]) -> Option<&str> {
    keys.iter().find(|k| !is_search_key(k)).map(String::as_str)
}

/// Remember which login row a search key belongs to (Get mods save, lobby save, or after login).
pub fn pair_search_to_login(keys: &[String]) {
    let Some(login) = login_key_in(keys) else { return };
    let mut store = ServerCatalogues::load();
    let mut dirty = false;
    for key in keys {
        if !is_search_key(key) {
            continue;
        }
        let mut entry = store.get(key).cloned().unwrap_or_default();
        if entry.paired_login == login {
            continue;
        }
        entry.paired_login = login.to_string();
        store.set(key, entry);
        dirty = true;
    }
    if dirty && let Err(e) = store.save() {
        log::warn!("server catalogues: {e:#}");
    }
}

/// Clears the saved catalogue repo for `keys` only (search + login for this server); returns keys touched for refetch.
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
        let mut entry = keys.iter().find_map(|key| store.get(key).cloned()).unwrap_or_default();
        entry.repo = repo.clone();
        for key in keys {
            let mut e = entry.clone();
            if is_search_key(key)
                && let Some(login) = login_key_in(keys)
            {
                e.paired_login = login.to_string();
            }
            store.set(key, e);
        }
    }
    if let Err(e) = store.save() {
        log::warn!("server catalogues: {e:#}");
        return None;
    }
    pair_search_to_login(keys);
    Some(keys.to_vec())
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
