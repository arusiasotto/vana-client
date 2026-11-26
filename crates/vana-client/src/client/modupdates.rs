//! Ours: once a login, a red log line when installed Lua mods or DAT packs have updates in the catalogue.

use super::World;
use super::catalogue::{self, Entry, List, Source};
use std::sync::mpsc::{Receiver, TryRecvError, channel};

/// The login's check: started once in the world with the message tables in; its counts read when they land.
#[derive(Default)]
pub struct Check {
    started: bool,
    rx: Option<Receiver<(usize, usize)>>,
}

pub(super) fn frame(w: &mut World) {
    if !w.mod_updates.started {
        if w.battle.is_none() || !super::event::zone_ready(w) {
            return;
        }
        w.mod_updates.started = true;
        let keys = w.catalogue_keys.clone();
        let (tx, rx) = channel();
        std::thread::spawn(move || {
            let hide = standard_ids_for_server_hide();
            let _ = tx.send((updates(List::Mods, &keys, hide.as_ref()), updates(List::Dats, &keys, hide.as_ref())));
        });
        w.mod_updates.rx = Some(rx);
        return;
    }
    let Some(rx) = &w.mod_updates.rx else { return };
    match rx.try_recv() {
        Ok((mods, packs)) => {
            w.mod_updates.rx = None;
            if let Some(line) = line(mods, packs) {
                w.chat.push_colour(line, super::lua::ERROR);
            }
        }
        Err(TryRecvError::Disconnected) => w.mod_updates.rx = None,
        Err(TryRecvError::Empty) => {}
    }
}

/// Standard mod and DAT ids: fetched once; None when either list could not be read (server rows fail closed).
fn standard_ids_for_server_hide() -> Option<std::collections::HashSet<String>> {
    let mods = catalogue::fetch_from(Source::Standard, List::Mods, &[]).ok()?;
    let dats = catalogue::fetch_from(Source::Standard, List::Dats, &[]).ok()?;
    Some(mods.iter().chain(&dats).map(|e| e.id.clone()).collect())
}

fn counts_as_update(e: &Entry, source: Source, hide: Option<&std::collections::HashSet<String>>) -> bool {
    if source == Source::Server && hide.is_none_or(|ids| ids.contains(&e.id)) {
        return false;
    }
    let root = catalogue::root_of(e);
    let have = catalogue::installed(&root, &e.id);
    let inst_src = catalogue::installed_source(&root, &e.id);
    let offer = match (have.as_deref(), inst_src) {
        (None, _) => catalogue::offer(e, None),
        (Some(v), Some(s)) if s == source => catalogue::offer(e, Some(v)),
        (Some(v), None) if source == Source::Standard => catalogue::offer(e, Some(v)),
        (Some(_), _) => None,
    };
    offer == Some(true)
}

/// How many of the list's entries are installed here at an older version (Modmgr's source rules).
fn updates(list: List, server_keys: &[String], hide: Option<&std::collections::HashSet<String>>) -> usize {
    let mut n = 0;
    for source in [Source::Standard, Source::Server] {
        let keys = if source == Source::Server { server_keys } else { &[] as &[String] };
        if source == Source::Server && hide.is_none() {
            continue;
        }
        let Ok(entries) = catalogue::fetch_from(source, list, keys) else {
            continue;
        };
        n += entries.iter().filter(|e| counts_as_update(e, source, hide)).count();
    }
    n
}

/// The line for `mods` Lua mod and `packs` DAT pack updates; none when there are none.
fn line(mods: usize, packs: usize) -> Option<String> {
    let many = |n: usize, one: &str, more: &str| if n == 1 { format!("1 {one}") } else { format!("{n} {more}") };
    match (mods, packs) {
        (0, 0) => None,
        (m, 0) => Some(format!("Updates are available for {} (Settings > Mods).", many(m, "mod", "mods"))),
        (0, p) => {
            Some(format!("Updates are available for {} (Settings > DAT Packs).", many(p, "DAT pack", "DAT packs")))
        }
        (m, p) => Some(format!(
            "Updates are available for {} and {} (Settings > Mods, DAT Packs).",
            many(m, "mod", "mods"),
            many(p, "DAT pack", "DAT packs")
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::line;

    #[test]
    fn update_lines() {
        assert_eq!(line(0, 0), None);
        assert_eq!(line(1, 0).as_deref(), Some("Updates are available for 1 mod (Settings > Mods)."));
        assert_eq!(line(3, 0).as_deref(), Some("Updates are available for 3 mods (Settings > Mods)."));
        assert_eq!(line(0, 2).as_deref(), Some("Updates are available for 2 DAT packs (Settings > DAT Packs)."));
        assert_eq!(
            line(2, 1).as_deref(),
            Some("Updates are available for 2 mods and 1 DAT pack (Settings > Mods, DAT Packs).")
        );
    }
}
