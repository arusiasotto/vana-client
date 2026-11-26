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

/// Login host-port row for this config (hostname or IP + auth port).
pub fn login_key(cfg: &config::Config) -> String {
    config::server_catalogue_key_login(&cfg.server, cfg.auth_port)
}

/// Keys for login overlay / lobby settings: login row plus search keys paired to it (and same-IP lobby guess).
pub fn catalogue_keys_for_cfg(cfg: &config::Config) -> Vec<String> {
    let login = login_key(cfg);
    let search_guess = cfg.server.trim().parse::<std::net::Ipv4Addr>().ok().map(|ip| (ip, cfg.auth_port));
    let mut keys = config::active_server_keys(cfg, search_guess);
    if !keys.contains(&login) {
        keys.push(login.clone());
    }
    let store = ServerCatalogues::load();
    for (k, e) in store.list() {
        if k != &login && !keys.contains(k) && e.paired_login == login {
            keys.push(k.clone());
        }
    }
    keys
}

/// Remember which login row each other key in `keys` belongs to (`active_server_keys` puts login last).
pub fn pair_search_to_login(login: &str, keys: &[String]) {
    let mut store = ServerCatalogues::load();
    let mut dirty = false;
    for key in keys {
        if key == login {
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

/// Stores `text` as the catalogue repo for `keys` (clears when empty). `login` is the login host-port row (not inferred
/// from key shape — IP servers use the same shape for search and login).
pub fn save_repo(login: &str, keys: &[String], text: &str) -> Option<Vec<String>> {
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
            if key != login {
                e.paired_login = login.to_string();
            }
            store.set(key, e);
        }
    }
    if let Err(e) = store.save() {
        log::warn!("server catalogues: {e:#}");
        return None;
    }
    pair_search_to_login(login, keys);
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
    fn ip_server_lobby_keys_include_search_shape() {
        let mut cfg = config::Config::default();
        cfg.server = "192.168.1.10".into();
        cfg.auth_port = 54231;
        let keys = catalogue_keys_for_cfg(&cfg);
        assert!(keys.contains(&"192.168.1.10-54231".to_string()));
    }

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
