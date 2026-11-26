//! Ours: once a login, a red log line when installed Lua mods or DAT packs have updates in the catalogue.

use super::World;
use super::catalogue::{self, List};
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
            let _ = tx.send((updates(List::Mods, &keys), updates(List::Dats, &keys)));
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

/// How many of the list's entries are installed here at an older version.
fn updates(list: List, server_keys: &[String]) -> usize {
    let mut ids = std::collections::HashSet::new();
    for source in [catalogue::Source::Standard, catalogue::Source::Server] {
        let keys = if source == catalogue::Source::Server { server_keys } else { &[] as &[String] };
        let Ok(entries) = catalogue::fetch_from(source, list, keys) else { continue };
        for e in entries {
            let have = catalogue::installed(&catalogue::root_of(&e), &e.id);
            if catalogue::offer(&e, have.as_deref()) == Some(true) {
                ids.insert(e.id);
            }
        }
    }
    ids.len()
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
