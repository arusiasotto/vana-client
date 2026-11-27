//! Outstanding player actions (c2s 0x01A / 0x037) until the server answers — the same rules as the Pending Actions mod.

use crate::net::action::Action;
use std::time::{Duration, Instant};

const SHOW_AFTER: Duration = Duration::from_millis(150);
const TIMEOUT: Duration = Duration::from_secs(5);
const REFUSED_WITHIN: Duration = Duration::from_secs(2);
const KEEP: Duration = Duration::from_secs(4);
const BLOCKING_MSG: u16 = 225;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    Spell,
    Ws,
    Ability,
    Item,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AskState {
    Waiting,
    Refused,
    Quiet,
}

/// How the last ask ended (for `actions.when_done` after the ask is gone).
#[derive(Clone, Debug)]
pub enum LastResult {
    Answered { kind: Kind, id: u32, target: u32 },
    Refused { kind: Kind, id: u32, target: u32, why: String },
    Quiet { kind: Kind, id: u32, target: u32 },
}

#[derive(Clone, Debug)]
struct Ask {
    kind: Kind,
    id: u32,
    target: u32,
    at: Instant,
    state: AskState,
    since: Instant,
    why: String,
}

#[derive(Default)]
pub struct Tracker {
    ask: Option<Ask>,
    last: Option<LastResult>,
    /// Set when an ask leaves `Waiting` (answered, refused, timed out); cleared when waiters run.
    pub resolve: bool,
}

impl Tracker {
    pub fn is_waiting(&self) -> bool {
        self.ask.as_ref().is_some_and(|a| a.state == AskState::Waiting)
    }

    /// For `game.action_ready`: no cast or event timer blocking command input.
    pub fn action_ready(w: &super::World) -> bool {
        if w.cast_bar.is_some() || w.event_timer.is_some() {
            return false;
        }
        if w.event.is_some() || super::event::active(w) {
            return false;
        }
        true
    }

    pub fn start(&mut self, kind: Kind, id: u32, target: u32) {
        let now = Instant::now();
        self.ask = Some(Ask { kind, id, target, at: now, state: AskState::Waiting, since: now, why: String::new() });
        self.last = None;
        self.resolve = false;
    }

    pub fn tick(&mut self, now: Instant) {
        let Some(a) = &mut self.ask else { return };
        if a.state == AskState::Waiting && now.duration_since(a.at) > TIMEOUT {
            let snap = a.clone();
            a.state = AskState::Quiet;
            a.since = now;
            self.last = Some(LastResult::Quiet { kind: snap.kind, id: snap.id, target: snap.target });
            self.resolve = true;
        } else if a.state != AskState::Waiting && now.duration_since(a.since) > KEEP {
            self.ask = None;
        }
    }

    pub fn on_action(&mut self, my_id: u32, a: &Action) {
        let Some(ask) = &self.ask else { return };
        if ask.state != AskState::Waiting || a.actor != my_id || !answers(ask, a) {
            return;
        }
        let snap = ask.clone();
        self.ask = None;
        self.last = Some(LastResult::Answered { kind: snap.kind, id: snap.id, target: snap.target });
        self.resolve = true;
    }

    pub fn on_battle_message(&mut self, my_id: u32, msg: u16, p1: u32, actor: u32) {
        let Some(ask) = &mut self.ask else { return };
        if ask.state != AskState::Waiting
            || actor != my_id
            || Instant::now().duration_since(ask.at) >= REFUSED_WITHIN
            || !refusal(ask, msg, p1)
        {
            return;
        }
        ask.state = AskState::Refused;
        ask.since = Instant::now();
        ask.why.clear();
        self.last = Some(LastResult::Refused {
            kind: ask.kind,
            id: ask.id,
            target: ask.target,
            why: ask.why.clone(),
        });
        self.resolve = true;
    }

    pub fn on_system_message(&mut self, id: u16) {
        let Some(ask) = &mut self.ask else { return };
        if ask.state != AskState::Waiting
            || ask.kind == Kind::Ws
            || id != BLOCKING_MSG
            || Instant::now().duration_since(ask.at) >= REFUSED_WITHIN
        {
            return;
        }
        ask.state = AskState::Refused;
        ask.since = Instant::now();
        ask.why.clear();
        self.last = Some(LastResult::Refused {
            kind: ask.kind,
            id: ask.id,
            target: ask.target,
            why: String::new(),
        });
        self.resolve = true;
    }

    /// Snapshot for `game.pending()` (nil while waiting inside SHOW_AFTER, like the chip).
    pub fn view(&self, now: Instant) -> Option<PendingView<'_>> {
        let a = self.ask.as_ref()?;
        if a.state == AskState::Waiting && now.duration_since(a.at) < SHOW_AFTER {
            return None;
        }
        Some(PendingView {
            kind: a.kind,
            id: a.id,
            target: a.target,
            state: a.state,
            why: a.why.as_str(),
            waiting: a.state == AskState::Waiting,
            age: now.duration_since(a.at).as_secs_f64(),
        })
    }

    pub fn result_table(&self, lua: &mlua::Lua) -> mlua::Result<mlua::Table> {
        let t = lua.create_table()?;
        if let Some(a) = &self.ask {
            fill_pending(lua, &t, a)?;
            return Ok(t);
        }
        let Some(r) = &self.last else {
            t.set("state", "idle")?;
            return Ok(t);
        };
        match r {
            LastResult::Answered { kind, id, target } => {
                t.set("state", "answered")?;
                t.set("kind", kind_str(*kind))?;
                t.set("id", *id)?;
                t.set("target", *target)?;
            }
            LastResult::Refused { kind, id, target, why } => {
                t.set("state", "refused")?;
                t.set("kind", kind_str(*kind))?;
                t.set("id", *id)?;
                t.set("target", *target)?;
                if !why.is_empty() {
                    t.set("why", why.as_str())?;
                }
            }
            LastResult::Quiet { kind, id, target } => {
                t.set("state", "quiet")?;
                t.set("kind", kind_str(*kind))?;
                t.set("id", *id)?;
                t.set("target", *target)?;
            }
        }
        Ok(t)
    }

    pub fn clear_resolve(&mut self) {
        self.resolve = false;
    }
}

pub struct PendingView<'a> {
    pub kind: Kind,
    pub id: u32,
    pub target: u32,
    pub state: AskState,
    pub why: &'a str,
    pub waiting: bool,
    pub age: f64,
}

pub fn kind_str(k: Kind) -> &'static str {
    match k {
        Kind::Spell => "spell",
        Kind::Ws => "ws",
        Kind::Ability => "ability",
        Kind::Item => "item",
    }
}

pub fn state_str(s: AskState) -> &'static str {
    match s {
        AskState::Waiting => "waiting",
        AskState::Refused => "refused",
        AskState::Quiet => "quiet",
    }
}

pub fn on_out_01a(w: &mut super::World, target: u32, category: u16, param: u32) {
    let kind = match category {
        3 => Some(Kind::Spell),
        7 => Some(Kind::Ws),
        9 => Some(Kind::Ability),
        _ => None,
    };
    let Some(kind) = kind else { return };
    let id = if kind == Kind::Ability { param.wrapping_add(0x200) } else { param };
    w.pending_action.start(kind, id, target);
}

pub fn on_out_item(w: &mut super::World, item_id: u32, target: u32) {
    w.pending_action.start(Kind::Item, item_id, target);
}

fn packet_id(ask: &Ask) -> u32 {
    if ask.kind == Kind::Ability { ask.id.wrapping_sub(0x200) } else { ask.id }
}

fn action_id(a: &Action) -> Option<u16> {
    const FINISH: &[u8] = &[3, 4, 5, 6, 11, 13, 14, 15];
    const START: &[u8] = &[7, 8, 9, 10, 12];
    if FINISH.contains(&a.category) {
        return Some((a.arg & 0xffff) as u16);
    }
    if START.contains(&a.category) && (a.arg & 0xffff) == 0x6163 {
        let t = a.targets.first()?;
        let r = t.results.first()?;
        return Some((r.value & 0xffff) as u16);
    }
    None
}

fn answers(ask: &Ask, a: &Action) -> bool {
    const ANSWERS: [(Kind, &[u8]); 4] = [
        (Kind::Spell, &[4, 8]),
        (Kind::Ws, &[3, 7, 11]),
        (Kind::Ability, &[6, 14, 15]),
        (Kind::Item, &[5, 9]),
    ];
    let Some(cats) = ANSWERS.iter().find(|(k, _)| *k == ask.kind).map(|(_, c)| *c) else {
        return false;
    };
    if !cats.contains(&a.category) {
        return false;
    }
    if ask.kind == Kind::Item || (ask.kind == Kind::Ws && a.category == 11) {
        return true;
    }
    action_id(a).is_some_and(|id| u32::from(id) == packet_id(ask))
}

fn refusal(ask: &Ask, id: u16, param: u32) -> bool {
    let named = param == packet_id(ask);
    match ask.kind {
        Kind::Spell => spell_refusal(id, param, named),
        Kind::Ws => ws_refusal(id, param),
        Kind::Ability => ability_refusal(id, param, named),
        Kind::Item => item_refusal(id, param, named),
    }
}

macro_rules! ids {
    ($n:ident, $($v:expr),+ $(,)?) => {
        matches!($n, $($v)|+)
    };
}

fn spell_refusal(id: u16, param: u32, named: bool) -> bool {
    if ids!(id, 12, 16, 18, 155, 446) && param == 0 {
        return true;
    }
    if ids!(id, 34, 35, 40, 47, 48, 49, 71, 72, 78, 155, 235, 313, 315, 316, 569, 581, 661, 700, 717) && named {
        return true;
    }
    false
}

fn ws_refusal(id: u16, param: u32) -> bool {
    ids!(id, 12, 71, 89, 155, 190, 191, 192, 216, 217, 446) && param == 0
}

fn ability_refusal(id: u16, param: u32, named: bool) -> bool {
    ids!(id, 4, 5, 12, 71, 72, 78, 87, 88, 94, 154, 155, 192, 199, 215, 216, 235, 307, 315, 316, 328, 336, 337, 347, 356, 428, 429, 446, 523, 524, 525, 561, 574, 662, 666, 745)
        && (param == 0 || named)
}

fn item_refusal(id: u16, param: u32, named: bool) -> bool {
    if ids!(id, 95, 96) {
        return true;
    }
    if id == 0 && named {
        return true;
    }
    ids!(id, 12, 55, 56, 62, 78, 92, 111, 155, 215, 246, 247, 308, 316, 356, 410, 443, 444, 445, 446, 514, 517, 518, 523, 580, 759)
        && (param == 0 || named)
}

fn fill_pending(_lua: &mlua::Lua, t: &mlua::Table, a: &Ask) -> mlua::Result<()> {
    t.set("kind", kind_str(a.kind))?;
    t.set("id", a.id)?;
    t.set("target", a.target)?;
    t.set("state", state_str(a.state))?;
    if !a.why.is_empty() {
        t.set("why", a.why.as_str())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::net::action::{Action, ActionResult, ActionTarget};

    #[test]
    fn magic_finish_answers_spell_ask() {
        let mut t = Tracker::default();
        t.start(Kind::Spell, 247, 1);
        let a = Action {
            actor: 1,
            category: 4,
            arg: 247,
            ..Action::default()
        };
        t.on_action(1, &a);
        assert!(!t.is_waiting());
        assert!(matches!(t.last, Some(LastResult::Answered { id: 247, .. })));
    }

    #[test]
    fn wrong_spell_id_does_not_answer() {
        let mut t = Tracker::default();
        t.start(Kind::Spell, 247, 1);
        let a = Action { actor: 1, category: 4, arg: 100, ..Action::default() };
        t.on_action(1, &a);
        assert!(t.is_waiting());
    }

    #[test]
    fn magic_start_ca_parses_id() {
        let mut t = Tracker::default();
        t.start(Kind::Spell, 100, 1);
        let a = Action {
            actor: 1,
            category: 8,
            arg: 0x6163,
            targets: vec![ActionTarget {
                id: 1,
                results: vec![ActionResult { value: 100, ..ActionResult::default() }],
            }],
            ..Action::default()
        };
        t.on_action(1, &a);
        assert!(!t.is_waiting());
    }
}

pub(super) fn pending_to_lua(lua: &mlua::Lua, v: &PendingView<'_>) -> mlua::Result<mlua::Table> {
    let t = lua.create_table()?;
    t.set("kind", kind_str(v.kind))?;
    t.set("id", v.id)?;
    t.set("target", v.target)?;
    t.set("state", state_str(v.state))?;
    if !v.why.is_empty() {
        t.set("why", v.why)?;
    }
    t.set("waiting", v.waiting)?;
    t.set("age", v.age)?;
    Ok(t)
}