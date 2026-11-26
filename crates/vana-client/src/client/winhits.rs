//! Windows as drawn this frame (name, frame, children), for the mouse on windows drawn at a runtime place (stacked on
//! the log, beside a row): the generic window handler's hit tests on what was really drawn.

use super::World;
use super::game_ui::{GameUi, LobbyWin};
use crate::audio::Ui;

/// Forgets last frame's windows (before the windows draw).
pub fn clear(w: &World) {
    w.win_hits.borrow_mut().clear();
}

pub fn record(w: &World, name: &str, win: &LobbyWin) {
    record_rects(w, name, win.frame, win.children.clone());
}

pub fn record_rects(w: &World, name: &str, frame: [f32; 4], children: Vec<(u16, [f32; 4])>) {
    w.win_hits.borrow_mut().push((name.to_string(), frame, children));
}

/// Both ends of a box take the mouse (FUN_1011a140: `jg` / `jl` around each bound).
fn inside(r: [f32; 4], p: (f32, f32)) -> bool {
    p.0 >= r[0] && p.0 <= r[0] + r[2] && p.1 >= r[1] && p.1 <= r[1] + r[3]
}

/// The child of a window drawn this frame under the pointer (`ids` only), and whether the pointer is on the window.
/// Retail's hit test (FUN_1011a140) takes the first child whose box holds the mouse and whose state is not 0x10. The
/// box is the child's place moved by its header offset (+0xe, +0x10); `part` gives that offset, or None for a child in
/// state 0x10. The frame is not asked (only the hover while the button is held, FUN_1015f360, wants the mouse inside
/// it).
pub fn child_under(
    w: &World,
    name: &str,
    p: (f32, f32),
    ids: std::ops::RangeInclusive<u16>,
    part: impl Fn(u16) -> Option<(f32, f32)>,
) -> (Option<u16>, bool) {
    let hits = w.win_hits.borrow();
    let Some((_, frame, children)) = hits.iter().find(|h| h.0 == name) else { return (None, false) };
    (pick(children, p, ids, part), inside(*frame, p))
}

fn pick(
    children: &[(u16, [f32; 4])],
    p: (f32, f32),
    ids: std::ops::RangeInclusive<u16>,
    part: impl Fn(u16) -> Option<(f32, f32)>,
) -> Option<u16> {
    let under = |&&(id, r): &&(u16, [f32; 4])| {
        ids.contains(&id) && part(id).is_some_and(|(ox, oy)| inside([r[0] + ox, r[1] + oy, r[2], r[3]], p))
    };
    children.iter().find(under).map(|c| c.0)
}

/// Window `name`'s children for `child_under`: each one's header offset, None for the caption retail puts in state
/// 0x10 (`GameUi::caption`).
pub fn parts<'a>(gu: &'a GameUi, name: &'a str) -> impl Fn(u16) -> Option<(f32, f32)> + 'a {
    let caption = gu.caption(name);
    move |id| {
        if caption == Some(id) {
            return None;
        }
        let e = gu.layout(name).and_then(|m| m.elements.iter().skip(1).find(|e| e.id == id));
        Some(e.map_or((0.0, 0.0), |e| (e.offset().0 as f32, e.offset().1 as f32)))
    }
}

/// The pointer on a recorded window.
pub fn over(w: &World, name: &str, p: (f32, f32)) -> bool {
    child_under(w, name, p, 0..=0, |_| None).1
}

/// The generic handler on the focused window: a child under the pointer takes the cursor (SE 0001), a click on the
/// cursor's child is Enter, a right click on the window Escape (ours only over it; retail's message 6 takes any right
/// click, FUN_1015def0). `key` is the window's key handler.
pub fn generic(
    w: &mut World,
    gu: &GameUi,
    name: &str,
    cursor: u16,
    ids: std::ops::RangeInclusive<u16>,
    p: (f32, f32),
    moved: bool,
    clicked: bool,
    right: bool,
    set: impl FnOnce(&mut World, u16),
    key: impl FnOnce(&mut World, &GameUi, egui::Key),
) {
    let (child, on) = child_under(w, name, p, ids, parts(gu, name));
    if right && on {
        key(w, gu, egui::Key::Escape);
        return;
    }
    let Some(id) = child else { return };
    gu.hover.set(true);
    if id != cursor && (moved || clicked) {
        set(w, id);
        w.sounds.push(Ui::Cursor as u32);
    } else if clicked {
        key(w, gu, egui::Key::Enter);
    }
}

/// What a click on an itemctrl / moneyctr child re-sends (message 5, FUN_1013a6c0 / FUN_10140bc0's tables): 1 the
/// confirm (Enter), 2 message 4 (Left: all, or ten times the step), 3 message 3 (Right: 1, or a tenth of the step),
/// 4 message 1 (Down: one step less), 5 message 2 (Up: one step more). The windows' keys do the rest.
pub fn ctr_key(child: u16) -> Option<egui::Key> {
    use egui::Key as K;
    Some(match child {
        1 => K::Enter,
        2 => K::ArrowLeft,
        3 => K::ArrowRight,
        4 => K::ArrowDown,
        5 => K::ArrowUp,
        _ => return None,
    })
}

/// A held - / + repeats (retail's message 0x1d re-sends 1 / 2 for children 4 / 5; how often it comes is not traced,
/// ours: after 400 ms, every 60 ms).
const HOLD: std::time::Duration = std::time::Duration::from_millis(400);
const REPEAT: std::time::Duration = std::time::Duration::from_millis(60);

/// The mouse on itemctrl / moneyctr (`name`, as drawn this frame): a click on a child is its message (ctr_key), - / +
/// step on the press and repeat while held, a right click on the window is Escape. `key` is the window's key handler.
pub fn ctr(
    w: &mut World,
    gu: &GameUi,
    name: &str,
    p: (f32, f32),
    clicked: bool,
    right: bool,
    mut key: impl FnMut(&mut World, &GameUi, egui::Key),
) {
    let (pressed, down) = w.ptr_button;
    let (child, on) = child_under(w, name, p, 1..=5, parts(gu, name));
    if !down || w.ctr_hold.is_some_and(|(c, _)| Some(c) != child) {
        w.ctr_hold = None;
    }
    if right && on {
        key(w, gu, egui::Key::Escape);
        return;
    }
    let Some(id) = child else { return };
    gu.hover.set(true);
    let Some(k) = ctr_key(id) else { return };
    if matches!(id, 4 | 5) {
        let now = std::time::Instant::now();
        if pressed {
            w.ctr_hold = Some((id, now + HOLD));
            key(w, gu, k);
        } else if w.ctr_hold.is_some_and(|(_, next)| now >= next) {
            w.ctr_hold = Some((id, now + REPEAT));
            key(w, gu, k);
        }
    } else if clicked {
        key(w, gu, k);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use egui::Key as K;

    /// FUN_1011a140: the first child in order whose box (moved by its header offset, both ends in) holds the mouse;
    /// a child in state 0x10 (the caption of a window with registry flag 0x200000) is passed over.
    #[test]
    fn hit_test_skips_the_caption() {
        // Three rows 16 apart and a caption drawn across the top edge (place (0, 0), offset (19, -3)).
        let kids = [(1, [16.0, 6.0, 88.0, 16.0]), (2, [16.0, 22.0, 88.0, 16.0]), (3, [0.0, 0.0, 73.0, 9.0])];
        let live = |id: u16| Some(if id == 3 { (19.0, -3.0) } else { (0.0, 0.0) });
        let dead = |id: u16| if id == 3 { None } else { Some((0.0, 0.0)) };
        // A row's bottom edge is still the row; where two boxes meet the first child wins.
        assert_eq!(pick(&kids, (16.0, 6.0), 1..=3, live), Some(1));
        assert_eq!(pick(&kids, (104.0, 22.0), 1..=3, live), Some(1));
        assert_eq!(pick(&kids, (50.0, 23.0), 1..=3, live), Some(2));
        assert_eq!(pick(&kids, (105.0, 23.0), 1..=3, live), None);
        // A live caption is hit where it is drawn, above the frame too, not at its place.
        assert_eq!(pick(&kids, (20.0, -3.0), 1..=3, live), Some(3));
        assert_eq!(pick(&kids, (5.0, 2.0), 1..=3, live), None);
        // In state 0x10 it is not hit at all; nor is a child outside `ids`.
        assert_eq!(pick(&kids, (20.0, -3.0), 1..=3, dead), None);
        assert_eq!(pick(&kids, (30.0, 4.0), 1..=2, live), None);
        assert_eq!(pick(&kids, (30.0, 6.0), 1..=3, dead), Some(1));
    }

    #[test]
    fn ctr_children_send_retails_messages() {
        let keys: Vec<_> = (0..=6).map(ctr_key).collect();
        assert_eq!(
            keys,
            [None, Some(K::Enter), Some(K::ArrowLeft), Some(K::ArrowRight), Some(K::ArrowDown), Some(K::ArrowUp), None]
        );
    }
}
