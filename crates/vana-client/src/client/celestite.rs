//! statcom2 row 13 since build 30261102 (MODLOG "Celestite windows"): fe_main (Alter Ego Points and the six
//! celestite sets), and a set's two lists, fe_equip (its ten slots) beside fe_inven (the celestites owned), with
//! bluehelp under them. s2c 0x08F carries the data, c2s 0x0C6 asks for it and c2s 0x0C5 changes a set.

use super::World;
use super::game_ui::GameUi;
use super::merits::{HELP, PointList, PointRow};
use super::net::NetCommand;
use crate::audio::Ui;

pub const MAIN: &str = "menu    fe_main";
const EQUIP: &str = "menu    fe_equip";
const INVEN: &str = "menu    fe_inven";
const WHITE: u32 = 0x8080_8080;
const GREY: u32 = 0x8040_4040;
const GREEN: u32 = 0x8050_9050;
const PICKED: u32 = 0x8080_4020;
/// The lists' rows shown (FUN_101f7d20: 10 in fe_equip's constructor FUN_101170f0, 11 in fe_inven's FUN_10117c30).
const SLOTS: usize = 10;
/// c2s 0x0C6 (FUN_100e5260): asks for the s2c 0x08F block.
const C2S_CELESTITES_ASK: u16 = 0x0C6;
/// c2s 0x0C5 (FUN_100e5200): one set's ten slots.
const C2S_CELESTITES_SET: u16 = 0x0C5;
/// Key item Alter Ego Points (fe_main child 1; before 30261102, statcom2 row 13 itself).
const KI_ALTER_EGO: u16 = 0xd21;
/// Key item for the celestite sets (fe_main children 2..7).
const KI_CELESTITES: u16 = 0xd2f;
/// System message 0xb2: sets change only in the Mog House.
const MSG_NOT_HERE: usize = 0xb2;
/// FUN_10117e60 tints a row white only within this many rows of the cursor (0x10117f1e..0x10117f7c).
const TINT_REACH: usize = 10;
const ROWS: usize = 11;
/// A celestite n is item ITEM + n (FUN_10117580 / FUN_10117e60).
const ITEM: u16 = 0x72f0;
/// Rows 18 px apart (+0x26), fe_equip's from y 0x13 and fe_inven's from 4 (+0x2d); the cursor band (keytops3 428,
/// +0x34) at y 0x15 / 6 (+0x2f).
const PITCH: f32 = 18.0;
/// The cell columns: DAT_1036d18c (fe_equip: the slot's label, the celestite) and DAT_1036d194 (fe_inven: the icon,
/// the name).
const EQUIP_COLS: [f32; 2] = [0.0, 36.0];
const INVEN_COLS: [f32; 2] = [0.0, 18.0];

/// s2c 0x08F (FUN_100e5290): 0x2b dwords to session +0x2d67c. The first eight are the owned bits (FUN_10118110: bit
/// n = celestite n), then seven 0x14-byte records by set number (FUN_10117b10: set 0..5 is record 1..6, record 0
/// is never read): ten slot bytes (FUN_10117a90: 0 a closed slot, else its label) and the ten celestites worn
/// (FUN_10117a30).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CelData {
    pub owned: [u32; 8],
    pub sets: [[u8; 20]; 7],
}

impl CelData {
    /// The packet from its header on (0xb0 bytes).
    pub fn parse(p: &[u8]) -> Option<Self> {
        let b = p.get(4..0xb0)?;
        Some(Self {
            owned: std::array::from_fn(|i| u32::from_le_bytes(b[4 * i..4 * i + 4].try_into().unwrap())),
            sets: std::array::from_fn(|s| b[0x20 + 0x14 * s..0x34 + 0x14 * s].try_into().unwrap()),
        })
    }

    fn owns(&self, n: u8) -> bool {
        self.owned[n as usize >> 5] >> (n & 31) & 1 != 0
    }

    /// FUN_10117e60's walk: the celestites 1..0xff owned, in order.
    fn list(&self) -> Vec<u8> {
        (1..=0xffu8).filter(|&n| self.owns(n)).collect()
    }

    fn label(&self, set: usize, slot: usize) -> u8 {
        self.sets[set + 1][slot]
    }

    fn worn(&self, set: usize, slot: usize) -> u8 {
        self.sets[set + 1][10 + slot]
    }

    /// FUN_10117580: the open slots counted; the list shows that many rows, row k being slot k.
    fn open(&self, set: usize) -> usize {
        (0..SLOTS).filter(|&k| self.label(set, k) != 0).count()
    }

    /// FUN_10117b70: c2s 0x0C5's body. The set's ten celestites with `n` in `slot`; another slot holding `n` is
    /// emptied first (0 takes the celestite off).
    fn change(&self, set: usize, slot: usize, n: u8) -> Vec<u8> {
        let mut ids: [u8; 10] = self.sets[set + 1][10..].try_into().unwrap();
        if n != 0
            && let Some(at) = ids.iter().position(|&i| i == n)
        {
            ids[at] = 0;
        }
        ids[slot] = n;
        let mut body = vec![set as u8 + 1];
        body.extend(ids);
        body.push(0);
        body
    }
}

/// fe_main: the cursor and the disabled children.
pub struct MainUi {
    pub sel: u16,
    pub off: Vec<u16>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Focus {
    Equip,
    Inven,
}

/// fe_equip (+0x58 the set, +0x50 whether sets may change, +0x54 the slot picked) and fe_inven (+0x50 the row
/// picked) with their cursors.
#[derive(Clone, Debug, PartialEq)]
pub struct CelUi {
    set: usize,
    focus: Focus,
    can_edit: bool,
    slot: usize,
    slot_pick: Option<usize>,
    cursor: usize,
    top: usize,
    pick: Option<usize>,
}

/// What a key did besides moving the cursors.
#[derive(Debug, Default, PartialEq)]
struct Out {
    sound: Option<Ui>,
    /// c2s 0x0C5's body.
    send: Option<Vec<u8>>,
    /// System message 0xb2 (FUN_1012b2c0).
    refuse: bool,
    close: bool,
}

fn sound(s: Ui) -> Out {
    Out { sound: Some(s), ..Default::default() }
}

/// FUN_10117e60's name colour of row `k` (celestite `n`): the row picked; one worn in this set; white when sets may
/// change, the row is within TINT_REACH of the cursor, the item's record is loaded, the main job's level reaches the
/// item's (the first byte of its record's +0x14 block, FUN_101181a0) and the block's second byte has the set's bit
/// (FUN_101181d0: bit set + 1); else grey. The classic list shows 11 rows, so the reach only shows in the modern
/// panel, which lists every row.
fn tint(u: &CelUi, d: &CelData, k: usize, n: u8, level: u8, item: &dyn Fn(u8) -> Option<[u8; 2]>) -> u32 {
    if u.pick == Some(k) {
        PICKED
    } else if (0..SLOTS).any(|s| d.worn(u.set, s) == n) {
        GREEN
    } else if u.can_edit
        && k.abs_diff(u.cursor) <= TINT_REACH
        && item(n).is_some_and(|b| b[0] <= level && b[1] >> (u.set + 1) & 1 != 0)
    {
        WHITE
    } else {
        GREY
    }
}

/// The cursors back inside the lists after the data changed (FUN_101f8630 and the list handler's tail).
fn clamp(u: &mut CelUi, d: Option<&CelData>) {
    let (open, n) = d.map_or((0, 0), |d| (d.open(u.set), d.list().len()));
    u.slot = u.slot.min(open.saturating_sub(1));
    u.cursor = u.cursor.min(n.saturating_sub(1));
    u.top = u.top.min(n.saturating_sub(ROWS));
    super::scrollbar::keep_in_view(&mut u.top, u.cursor, ROWS);
}

/// The lists' keys. fe_equip (FUN_10117750 under the list handler FUN_101f8280; +0x47 = 0, so Left / Right page
/// only with Ctrl): Alt+Right / Alt+Left (key functions 0xb5 / 0xb6) the next / previous set; Down wraps from the
/// tenth slot (its child's link). fe_inven (FUN_10118260; +0x47 = 1): Left / Right page. `Plus` is message 8.
fn step(
    u: &mut CelUi,
    d: Option<&CelData>,
    key: egui::Key,
    ctrl: bool,
    alt: bool,
    level: u8,
    item: &dyn Fn(u8) -> Option<[u8; 2]>,
) -> Out {
    use super::scrollbar::{Msg, rows_abs};
    use egui::Key as K;
    let list = d.map_or(Vec::new(), |d| d.list());
    let open = d.map_or(0, |d| d.open(u.set));
    let moved = |m: bool| if m { sound(Ui::Cursor) } else { Out::default() };
    match (u.focus, key) {
        (Focus::Equip, K::ArrowRight | K::ArrowLeft) if alt => {
            u.set = (u.set + if key == K::ArrowRight { 1 } else { 5 }) % 6;
            clamp(u, d);
            Out::default()
        }
        (Focus::Equip, K::ArrowRight | K::ArrowLeft) if ctrl => {
            let m = if key == K::ArrowRight { Msg::PageDown } else { Msg::PageUp };
            moved(rows_abs(m, &mut 0, &mut u.slot, open, SLOTS))
        }
        (Focus::Equip, K::ArrowDown) if u.slot + 1 == SLOTS && open == SLOTS => {
            u.slot = 0;
            sound(Ui::Cursor)
        }
        (Focus::Equip, K::ArrowDown) if u.slot + 1 < open => {
            u.slot += 1;
            sound(Ui::Cursor)
        }
        (Focus::Equip, K::ArrowUp) if u.slot > 0 => {
            u.slot -= 1;
            sound(Ui::Cursor)
        }
        (Focus::Equip, K::Enter) => {
            // A closed slot: the buzzer (FUN_10117a70).
            let Some(d) = d.filter(|d| d.label(u.set, u.slot) != 0) else { return sound(Ui::Error) };
            let worn = if u.slot < open { d.worn(u.set, u.slot) } else { 0 };
            match u.pick {
                // The slot first: fe_inven takes the keys on the slot's celestite.
                None => {
                    if u.slot_pick.is_none() {
                        u.slot_pick = Some(u.slot);
                        if let Some(at) = list.iter().position(|&n| n == worn).filter(|_| worn != 0) {
                            u.top = at.min(list.len().saturating_sub(ROWS));
                            u.cursor = at;
                        }
                        u.focus = Focus::Inven;
                    }
                    sound(Ui::Select)
                }
                Some(_) if !u.can_edit => Out { refuse: true, ..sound(Ui::Error) },
                // A celestite was picked first: it goes in this slot, or comes off when the slot holds it.
                Some(k) => {
                    let n = list.get(k).copied().unwrap_or(0);
                    u.pick = None;
                    u.focus = Focus::Inven;
                    Out { send: Some(d.change(u.set, u.slot, if n == worn { 0 } else { n })), ..sound(Ui::Select) }
                }
            }
        }
        (Focus::Equip, K::Escape) => match u.pick.take() {
            Some(_) => {
                u.focus = Focus::Inven;
                sound(Ui::Cancel)
            }
            None => Out { close: true, ..sound(Ui::Cancel) },
        },
        (Focus::Equip, K::Plus) if u.slot_pick.is_none() && u.pick.is_none() => {
            u.focus = Focus::Inven;
            sound(Ui::Close)
        }
        (Focus::Equip, K::Plus) => sound(Ui::Error),
        (Focus::Inven, K::ArrowUp | K::ArrowDown) => {
            let mut c = (u.cursor, u.top);
            let m = super::scrollbar::step(&mut c, list.len(), ROWS, key);
            (u.cursor, u.top) = c;
            moved(m)
        }
        (Focus::Inven, K::ArrowRight | K::ArrowLeft) => {
            let m = if key == K::ArrowRight { Msg::PageDown } else { Msg::PageUp };
            moved(rows_abs(m, &mut u.top, &mut u.cursor, list.len(), ROWS))
        }
        (Focus::Inven, K::Enter) => {
            let (Some(d), Some(&n)) = (d, list.get(u.cursor)) else { return Out::default() };
            if !u.can_edit {
                return Out { refuse: true, ..sound(Ui::Error) };
            }
            if tint(u, d, u.cursor, n, level, item) == GREY {
                return sound(Ui::Error);
            }
            match u.slot_pick {
                // The celestite first: fe_equip takes the keys on the slot that wears it.
                None => {
                    if u.pick.is_some() {
                        return Out::default();
                    }
                    u.pick = Some(u.cursor);
                    if let Some(at) = (0..SLOTS).position(|s| d.worn(u.set, s) == n) {
                        u.slot = at.min(open.saturating_sub(1));
                    }
                    u.focus = Focus::Equip;
                    sound(Ui::Select)
                }
                // A slot was picked first: the celestite goes in it, or comes off when the slot holds it.
                Some(slot) => {
                    u.slot_pick = None;
                    u.focus = Focus::Equip;
                    let n = if d.worn(u.set, slot) == n { 0 } else { n };
                    Out { send: Some(d.change(u.set, slot, n)), ..sound(Ui::Select) }
                }
            }
        }
        (Focus::Inven, K::Escape) => match (u.pick, u.slot_pick) {
            (None, None) => Out { close: true, ..sound(Ui::Cancel) },
            (Some(_), None) => Out::default(),
            _ => {
                u.slot_pick = None;
                u.focus = Focus::Equip;
                sound(Ui::Cancel)
            }
        },
        (Focus::Inven, K::Plus) if u.slot_pick.is_none() && u.pick.is_none() => {
            u.focus = Focus::Equip;
            sound(Ui::Close)
        }
        _ => Out::default(),
    }
}

/// s2c 0x08F: the block and session +0x40e65 bit 5.
pub fn on_data(w: &mut World, d: CelData) {
    w.cel_data = Some(d);
    if let Some(u) = w.cel_ui.as_mut() {
        clamp(u, Some(&d));
    }
}

fn level(w: &World) -> u8 {
    w.stats.as_ref().map_or(0, |s| s.main.1)
}

/// statcom2 child 13 (FUN_1014a0b0) and fe_main's children (FUN_1014caa0): the main job at 99 or more with key item
/// 0xd21 (Alter Ego Points) or 0xd2f (the celestite sets).
pub fn keys(w: &World) -> (bool, bool) {
    let high = level(w) > 0x62;
    (high && w.has_key_item(KI_ALTER_EGO), high && w.has_key_item(KI_CELESTITES))
}

/// statcom2 Enter on row 13 (FUN_1014a1e0 k 12): fe_main with every child disabled, then child 1 with key item 0xd21
/// and children 2..7 with 0xd2f. Game files older than 30261102 have no fe_main: the row opens fp_cat as it did.
pub fn open_main(w: &mut World) {
    if !w.fe_menu {
        super::aepoints::open(w);
        return;
    }
    let (ae, sets) = keys(w);
    let off = (1..=7u16).filter(|&c| if c == 1 { !ae } else { !sets }).collect();
    w.fe_main = Some(MainUi { sel: w.cursor_recall(MAIN), off });
}

/// FUN_10117360 and fe_equip's open FUN_101173d0: the set, bluehelp, fe_inven, then fe_equip with the keys; c2s
/// 0x0C6 while no 0x08F came. Sets change only in the Mog House and not in Monstrosity (+0x50).
fn open_set(w: &mut World, set: usize) {
    if w.cel_data.is_none() {
        let _ = w.net.commands.send(NetCommand::Packet { id: C2S_CELESTITES_ASK, body: Vec::new() });
    }
    let can_edit = w.myroom.is_some() && !super::monstrosity::active(w);
    w.cel_ui =
        Some(CelUi { set, focus: Focus::Equip, can_edit, slot: 0, slot_pick: None, cursor: 0, top: 0, pick: None });
}

/// fe_main (FUN_1014cb50): Up / Down along the links; Enter on a disabled child the buzzer, else child 1 opens
/// fp_cat and children 2..7 a set; Escape closes it.
pub fn main_key(w: &mut World, gu: &GameUi, key: egui::Key) {
    use egui::Key as K;
    let Some(m) = w.fe_main.as_ref() else { return };
    let sel = m.sel;
    match key {
        K::ArrowUp | K::ArrowDown => {
            let to = gu.menu_links(MAIN, sel).map_or(sel, |l| l[if key == K::ArrowUp { 2 } else { 3 }] as u16);
            if to != sel
                && to != 0
                && to != 0xff
                && let Some(m) = w.fe_main.as_mut()
            {
                m.sel = to;
                w.sounds.push(Ui::Cursor as u32);
            }
        }
        K::Enter if m.off.contains(&sel) => w.sounds.push(Ui::Error as u32),
        K::Enter => {
            w.sounds.push(Ui::Select as u32);
            match sel {
                1 => super::aepoints::open(w),
                2..=7 => open_set(w, sel as usize - 2),
                _ => {}
            }
        }
        K::Escape => {
            w.sounds.push(Ui::Cancel as u32);
            w.fe_main = None;
        }
        _ => {}
    }
}

fn item_bytes(w: &World) -> impl Fn(u8) -> Option<[u8; 2]> + '_ {
    |n| w.item_info.as_ref()?.item(ITEM + n as u16)?.maze.map(|m| [m[0], m[1]])
}

/// Whether the egui key event is the lists' to take: Num+ (message 8) comes through key function 0x11 (and the pointer),
/// so its egui event would transfer the focus a second time.
pub fn event_key(key: egui::Key) -> bool {
    key != egui::Key::Plus
}

/// The lists' keys; `Plus` is Num+ (message 8).
pub fn key(w: &mut World, key: egui::Key, ctrl: bool, alt: bool) {
    let Some(mut u) = w.cel_ui.clone() else { return };
    let out = step(&mut u, w.cel_data.as_ref(), key, ctrl, alt, level(w), &item_bytes(w));
    w.cel_ui = (!out.close).then_some(u);
    if out.refuse {
        super::textcmd::refuse(w, MSG_NOT_HERE);
    }
    if let Some(body) = out.send {
        let _ = w.net.commands.send(NetCommand::Packet { id: C2S_CELESTITES_SET, body });
    }
    if let Some(s) = out.sound {
        w.sounds.push(s as u32);
    }
}

/// The focused list's bar (FUN_101f6c70).
pub(super) fn bar(w: &mut World, m: super::scrollbar::Msg) -> bool {
    let n = w.cel_data.map_or(0, |d| d.list().len());
    let Some(u) = w.cel_ui.as_mut().filter(|u| u.focus == Focus::Inven) else { return false };
    super::scrollbar::rows_abs(m, &mut u.top, &mut u.cursor, n, ROWS)
}

fn item(w: &World, n: u8) -> Option<std::sync::Arc<crate::dat::items::Item>> {
    w.item_info.as_ref()?.item(ITEM + n as u16).filter(|_| n != 0)
}

fn name(w: &World, n: u8) -> String {
    item(w, n).map(|i| i.name.clone()).unwrap_or_default()
}

/// The celestite under the focused list's cursor (bluehelp's item, FUN_101174b0 / FUN_10117d90).
fn cursor_item(w: &World, u: &CelUi) -> u8 {
    let Some(d) = w.cel_data else { return 0 };
    match u.focus {
        Focus::Equip if u.slot < d.open(u.set) && d.label(u.set, u.slot) != 0 => d.worn(u.set, u.slot),
        Focus::Equip => 0,
        Focus::Inven => d.list().get(u.cursor).copied().unwrap_or(0),
    }
}

/// The windows as the modern layer draws them: fe_main's cursor and disabled rows; a set's slots (the celestite in
/// `level`; `labels` their keytops3 sprites) and the celestites owned in retail's colours.
pub(super) struct Look {
    pub menu: (u16, Vec<u16>),
    pub lists: Option<Lists>,
}

pub(super) struct Lists {
    pub set: usize,
    pub slots: PointList,
    pub owned: PointList,
    pub labels: Vec<usize>,
    /// Num+ would hand the keys over (nothing picked).
    pub free: bool,
}

pub(super) fn look(w: &World) -> Option<Look> {
    let m = w.fe_main.as_ref()?;
    let lists = w.cel_ui.as_ref().map(|u| {
        let d = w.cel_data;
        let help =
            item(w, cursor_item(w, u)).map_or_else(Default::default, |i| (i.name.clone(), i.description.clone()));
        let open = d.map_or(0, |d| d.open(u.set));
        let slots = (0..open)
            .map(|k| PointRow {
                tint: if u.slot_pick == Some(k) { PICKED } else { WHITE },
                level: Some((name(w, d.map_or(0, |d| d.worn(u.set, k))), WHITE)),
                ..Default::default()
            })
            .collect();
        let labels = (0..open).map(|k| 565 + d.map_or(0, |d| d.label(u.set, k)) as usize).collect();
        let list = d.map_or(Vec::new(), |d| d.list());
        let bytes = item_bytes(w);
        let owned = list
            .iter()
            .enumerate()
            .map(|(k, &n)| PointRow {
                name: name(w, n),
                tint: d.map_or(GREY, |d| tint(u, &d, k, n, level(w), &bytes)),
                ..Default::default()
            })
            .collect();
        Lists {
            set: u.set,
            slots: PointList { rows: slots, cursor: u.slot, focused: u.focus == Focus::Equip, help: help.clone() },
            owned: PointList { rows: owned, cursor: u.cursor, focused: u.focus == Focus::Inven, help },
            labels,
            free: u.pick.is_none() && u.slot_pick.is_none(),
        }
    });
    Some(Look { menu: (m.sel, m.off.clone()), lists })
}

/// The mouse's cursor moves: fe_main's child, a slot, a celestite. True when it moved.
pub(super) fn set_menu(w: &mut World, k: u16) -> bool {
    let Some(m) = w.fe_main.as_mut().filter(|m| m.sel != k) else { return false };
    m.sel = k;
    true
}

pub(super) fn set_slot(w: &mut World, k: usize) -> bool {
    let open = w.cel_data.map_or(0, |d| w.cel_ui.as_ref().map_or(0, |u| d.open(u.set)));
    let Some(u) = w.cel_ui.as_mut().filter(|u| u.slot != k && k < open) else { return false };
    u.slot = k;
    true
}

pub(super) fn set_row(w: &mut World, k: usize) -> bool {
    let n = w.cel_data.map_or(0, |d| d.list().len());
    let Some(u) = w.cel_ui.as_mut().filter(|u| u.cursor != k && k < n) else { return false };
    u.cursor = k;
    super::scrollbar::keep_in_view(&mut u.top, k, ROWS);
    true
}

/// The mouse: fe_main as the generic window; the focused list's rows the same. Every frame the focused list's update
/// (FUN_101174b0 for fe_equip, FUN_10117d90 for fe_inven) sends itself message 8, as Num+, while the mouse drives the
/// menus and is not busy (FUN_10127770: +0x4d == 2, FUN_10087070(0) clear) and the pointer is anywhere inside the
/// other list (FUN_1011a0a0, a plain rectangle test). A resting pointer counts: after Num+ the keys come straight back,
/// and with a pick held the refusal buzzes each frame, as retail does.
pub fn pointer(w: &mut World, gu: &GameUi, p: (f32, f32), moved: bool, clicked: bool, right: bool) {
    // The modern layer draws them and takes their mouse.
    if w.modern {
        return;
    }
    let Some(u) = w.cel_ui.clone() else {
        let Some(sel) = w.fe_main.as_ref().map(|m| m.sel) else { return };
        super::winhits::generic(
            w,
            gu,
            MAIN,
            sel,
            1..=7,
            p,
            moved,
            clicked,
            right,
            |w, id| {
                set_menu(w, id);
            },
            main_key,
        );
        return;
    };
    let keys = |w: &mut World, _: &GameUi, k: egui::Key| key(w, k, false, false);
    let (here, other, cursor, rows) = match u.focus {
        Focus::Equip => (EQUIP, INVEN, u.slot, w.cel_data.map_or(0, |d| d.open(u.set))),
        Focus::Inven => {
            let n = w.cel_data.map_or(0, |d| d.list().len());
            (INVEN, EQUIP, u.cursor.saturating_sub(u.top), n.saturating_sub(u.top).min(ROWS))
        }
    };
    if !super::textcmd::busy(w) && super::winhits::over(w, other, p) {
        gu.hover.set(true);
        key(w, egui::Key::Plus, false, false);
        return;
    }
    super::winhits::generic(
        w,
        gu,
        here,
        cursor as u16 + 1,
        1..=rows as u16,
        p,
        moved,
        clicked,
        right,
        |w, id| {
            if let Some(u) = w.cel_ui.as_mut() {
                match u.focus {
                    Focus::Equip => u.slot = id as usize - 1,
                    Focus::Inven => u.cursor = u.top + id as usize - 1,
                }
            }
        },
        keys,
    );
}

/// fe_main: its cursor child's help. The lists: their layout's help (0xe 1106) and title (0xd 201), and in slot 2
/// the cursor row's line, 0xe 0x452 + set (FUN_101179d0).
pub fn bars(gu: &GameUi, w: &World, bars: &mut super::hudtop::BarText) {
    if w.ae_ui.is_some() {
        return;
    }
    let Some(m) = &w.fe_main else { return };
    let Some(u) = &w.cel_ui else {
        bars.help[1] = gu.focus_text(MAIN, m.sel)[0].clone().unwrap_or_default();
        return;
    };
    let rows = w.cel_data.map_or(0, |d| match u.focus {
        Focus::Equip => d.open(u.set),
        Focus::Inven => d.list().len(),
    });
    bars.help[1] = gu.menu_msg(1106, "");
    bars.help[2] = if rows > 0 { gu.menu_msg(0x452 + u.set, "") } else { String::new() };
    bars.title[2] = gu.title_msg(201).unwrap_or_default();
}

/// An item's icon at half scale (cell kind 0x4d, FUN_101f6180's last case: FUN_1015d340 at (x, y + 2), 0.5).
fn icon(gu: &mut GameUi, w: &World, id: u16, x: f32, y: f32) {
    let Some(cache) = w.item_info.as_ref() else { return };
    super::items::upload_icons(gu, cache, std::iter::once(id));
    let icon = crate::render::invwin::icon_texture(id);
    if gu.has_image(&icon) {
        gu.image_rect(&icon, x, y, 16.0, 16.0, [1.0; 4]);
    }
}

/// The visible rows' hit rectangles (children 1..=n, their layout's x 3 and 18 high), `first` the first row's top below
/// the window's top: the lists hide the layout's rows, so the generic handler's hits are these.
fn row_hits(x: f32, y: f32, fw: f32, first: f32, n: usize) -> Vec<(u16, [f32; 4])> {
    (0..n).map(|k| (k as u16 + 1, [x + 3.0, y + first + PITCH * k as f32, fw - 6.0, PITCH])).collect()
}

pub fn draw(gu: &mut GameUi, w: &World, sw: f32, sh: f32) -> Vec<[f32; 4]> {
    let mut rects = Vec::new();
    if w.modern {
        return rects;
    }
    let Some(m) = &w.fe_main else { return rects };
    let free = w.confirm.is_none() && w.ae_ui.is_none();
    let hand = free && w.cel_ui.is_none();
    if let Some(win) = gu.lobby_window_off(MAIN, sw, sh, (0.0, 0.0), Some(m.sel), hand, &m.off) {
        super::winhits::record(w, MAIN, &win);
        gu.disabled_children(MAIN, win.frame[0], win.frame[1], &m.off, hand.then_some(m.sel));
        rects.push(win.frame);
    }
    let Some(u) = &w.cel_ui else { return rects };
    let d = w.cel_data;
    let text = |gu: &mut GameUi, s: &str, x: f32, y: f32, tint: u32| gu.text(s, x, y, 0, tint.to_le_bytes());
    // fe_inven opens first, under fe_equip.
    let list = d.map_or(Vec::new(), |d| d.list());
    let hide: Vec<u16> = (1..=ROWS as u16).collect();
    if let Some(win) = gu.lobby_window_off(INVEN, sw, sh, (0.0, 0.0), None, false, &hide) {
        let [x, y, fw, fh] = win.frame;
        let shown = list.len().saturating_sub(u.top).min(ROWS);
        super::winhits::record_rects(w, INVEN, win.frame, row_hits(x, y, fw, 6.0, shown));
        let bytes = item_bytes(w);
        for (k, &n) in list.iter().enumerate().skip(u.top).take(ROWS) {
            let ry = y + 4.0 + PITCH * (k - u.top) as f32;
            icon(gu, w, ITEM + n as u16, x + INVEN_COLS[0], ry + 2.0);
            let c = d.map_or(GREY, |d| tint(u, &d, k, n, level(w), &bytes));
            text(gu, &name(w, n), x + INVEN_COLS[1], ry + 2.0, c);
        }
        let focused = free && u.focus == Focus::Inven;
        if focused && !list.is_empty() {
            let cy = y + 6.0 + PITCH * (u.cursor - u.top) as f32;
            gu.sprite("menu    keytops3", 428, x, cy, WHITE);
            gu.cursor(x + 3.0, cy);
        }
        if list.len() > ROWS {
            gu.scroll_bar(x + fw - 8.0, y, fh, list.len(), ROWS, u.top);
            if focused {
                gu.bar_site(super::scrollbar::Owner::Points, x + fw - 8.0, y, fh, list.len(), ROWS, u.top);
            }
        }
        rects.push(win.frame);
    }
    let hide: Vec<u16> = (1..=SLOTS as u16).collect();
    let Some(win) = gu.lobby_window_off(EQUIP, sw, sh, (0.0, 0.0), None, false, &hide) else { return rects };
    let [x, y, fw, fh] = win.frame;
    let open = d.map_or(0, |d| d.open(u.set));
    super::winhits::record_rects(w, EQUIP, win.frame, row_hits(x, y, fw, 24.0, open));
    for k in 0..open {
        let ry = y + 19.0 + PITCH * k as f32;
        let (label, worn) = d.map_or((0, 0), |d| (d.label(u.set, k), d.worn(u.set, k)));
        if label == 0 {
            continue;
        }
        // Cell kind 0xe: keytops3 565 + the slot byte (FUN_101ca200(2) + 0x8d4) at (x, y + 2).
        gu.sprite("menu    keytops3", 565 + label as usize, x + EQUIP_COLS[0], ry + 2.0, WHITE);
        if worn != 0 {
            text(gu, &name(w, worn), x + EQUIP_COLS[1], ry + 2.0, WHITE);
        }
    }
    // The band shows without the keys too (+0x49 = 0).
    if open > 0 {
        gu.sprite("menu    keytops3", 428, x, y + 21.0 + PITCH * u.slot as f32, WHITE);
    }
    if free && u.focus == Focus::Equip {
        gu.cursor(x + 3.0, y + 24.0 + PITCH * u.slot as f32);
    }
    // FUN_101176e0: the set's caption, frames 211 + set, at (5, 2).
    gu.sprite("menu    framesus", 211 + u.set, x + 5.0, y + 2.0, WHITE);
    rects.push(win.frame);
    // bluehelp at (16, 256), under fe_equip at (16, 48), with the cursor's item (FUN_101edad0: its description's
    // lines from (4, 4), 16 px apart; the frame 16 a line + 8 high, at least its layout's).
    if let Some([_, _, hw, hh]) = gu.window_rect(HELP, sw, sh) {
        let desc = item(w, cursor_item(w, u)).map(|i| i.description.clone()).unwrap_or_default();
        let lines: Vec<&str> = if desc.is_empty() { Vec::new() } else { desc.split('\n').collect() };
        let (hx, hy, h) = (x, y + fh + 2.0, (16.0 * lines.len() as f32 + 8.0).max(hh));
        if gu.window_sized(HELP, hx, hy, hw, h) {
            for (i, l) in lines.iter().enumerate() {
                text(gu, l, hx + 4.0, hy + 4.0 + 16.0 * i as f32, WHITE);
            }
            rects.push([hx, hy, hw, h]);
        }
    }
    rects
}

#[cfg(test)]
mod tests {
    use super::*;
    use egui::Key as K;

    fn data() -> CelData {
        let mut p = vec![0u8; 0xb0];
        // Celestites 1, 2, 3 and 40 owned.
        p[4] = 0b1110;
        p[4 + 5] = 1;
        // Set 0 (record 1): slots 0..3 open with labels 1, 1, 2; slot 1 wears celestite 2.
        p[0x24 + 0x14..0x24 + 0x14 + 3].copy_from_slice(&[1, 1, 2]);
        p[0x24 + 0x14 + 10 + 1] = 2;
        CelData::parse(&p).unwrap()
    }

    fn ui() -> CelUi {
        CelUi { set: 0, focus: Focus::Equip, can_edit: true, slot: 0, slot_pick: None, cursor: 0, top: 0, pick: None }
    }

    /// Level 99 celestites usable in sets 0 and 1 (bits 1 and 2).
    fn bytes(_: u8) -> Option<[u8; 2]> {
        Some([99, 0b110])
    }

    fn press(u: &mut CelUi, d: &CelData, key: K) -> Out {
        step(u, Some(d), key, false, false, 99, &bytes)
    }

    /// The layouts and sprites the windows are drawn from (real game files; skipped without them or with files older
    /// than 30261102): fe_main's seven children, the lists' rows at the places the list class gives them, the set
    /// captions frames 211..216 and the slot labels from keytops3 566.
    #[test]
    fn layouts() {
        use crate::dat::ui::{LOBBY_US, UiFile, companions};
        let Ok(index) = crate::dat::DatIndex::open(&crate::config::Config::load().ffxi_dir()) else { return };
        let Ok(file) = index.read(LOBBY_US) else { return };
        let mut f = UiFile::parse(&file).unwrap();
        for &c in companions(LOBBY_US) {
            f.absorb(UiFile::parse(&index.read(c).unwrap()).unwrap(), true);
        }
        let Some(main) = f.menu(MAIN) else { return };
        let help: Vec<&str> = main.elements[1..].iter().map(|e| e.strings[0].as_str()).collect();
        assert_eq!(help, ["1096", "1100", "1101", "1102", "1103", "1104", "1105"]);
        let rows = |name: &str| -> Vec<(i16, i16)> {
            f.menu(name).unwrap().elements[1..].iter().map(|e| (e.x, e.y)).collect()
        };
        assert_eq!(rows(EQUIP), (0..SLOTS as i16).map(|k| (3, 24 + 18 * k)).collect::<Vec<_>>());
        assert_eq!(rows(INVEN), (0..ROWS as i16).map(|k| (3, 6 + 18 * k)).collect::<Vec<_>>());
        let (equip, inven) = (&f.menu(EQUIP).unwrap().elements[0], &f.menu(INVEN).unwrap().elements[0]);
        assert_eq!(
            [(equip.x, equip.y, equip.w, equip.h), (inven.x, inven.y, inven.w, inven.h)],
            [(16, 48, 182, 206), (200, 48, 182, 206)]
        );
        for e in [equip, inven] {
            assert_eq!(e.strings, ["1106", "201"]);
        }
        assert!(f.lib("menu    framesus").is_some_and(|l| l.sprites.len() > 216));
        assert!(f.lib("menu    keytops3").is_some_and(|l| l.sprites.len() > 580));
    }

    #[test]
    fn block_layout() {
        let d = data();
        assert_eq!(d.list(), [1, 2, 3, 40]);
        assert_eq!((d.open(0), d.open(1)), (3, 0));
        assert_eq!((d.label(0, 2), d.worn(0, 1), d.worn(0, 0)), (2, 2, 0));
        assert!(CelData::parse(&[0; 0xaf]).is_none());
    }

    #[test]
    fn change_body() {
        let d = data();
        // Celestite 2 moves from slot 1 to slot 0; 0 takes one off.
        assert_eq!(d.change(0, 0, 2), [1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        assert_eq!(d.change(0, 1, 0), [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        assert_eq!(d.change(0, 2, 40), [1, 0, 2, 40, 0, 0, 0, 0, 0, 0, 0, 0]);
    }

    #[test]
    fn rows_are_hit() {
        let r = row_hits(200.0, 48.0, 182.0, 24.0, 3);
        assert_eq!(r.iter().map(|h| h.0).collect::<Vec<_>>(), [1, 2, 3]);
        assert_eq!(r[1].1, [203.0, 90.0, 176.0, 18.0]);
        assert!(row_hits(0.0, 0.0, 100.0, 6.0, 0).is_empty());
    }

    #[test]
    fn num_plus_once() {
        assert!(!event_key(K::Plus));
        assert!(event_key(K::Enter));
    }

    #[test]
    fn name_colours() {
        let (d, mut u) = (data(), ui());
        let t = |u: &CelUi, k: usize, n: u8, level: u8| tint(u, &d, k, n, level, &bytes);
        assert_eq!([t(&u, 0, 1, 99), t(&u, 1, 2, 99), t(&u, 0, 1, 98)], [WHITE, GREEN, GREY]);
        u.pick = Some(1);
        assert_eq!(t(&u, 1, 2, 99), PICKED);
        u = CelUi { set: 2, ..ui() };
        assert_eq!(t(&u, 0, 1, 99), GREY);
        u = CelUi { can_edit: false, ..ui() };
        assert_eq!([t(&u, 0, 1, 99), t(&u, 1, 2, 99)], [GREY, GREEN]);
        assert_eq!(tint(&ui(), &d, 0, 1, 99, &|_| None), GREY);
    }

    #[test]
    fn slot_then_celestite() {
        let (d, mut u) = (data(), ui());
        u.slot = 1;
        // Enter on the slot wearing celestite 2: fe_inven with the cursor on it.
        assert_eq!(press(&mut u, &d, K::Enter), sound(Ui::Select));
        assert_eq!((u.focus, u.slot_pick, u.cursor), (Focus::Inven, Some(1), 1));
        // Enter on the same celestite takes it off; on another puts that one in.
        assert_eq!(press(&mut u.clone(), &d, K::Enter).send, Some(d.change(0, 1, 0)));
        u.cursor = 3;
        let out = press(&mut u, &d, K::Enter);
        assert_eq!(out.send, Some(vec![1, 0, 40, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
        assert_eq!((u.focus, u.slot_pick, out.sound), (Focus::Equip, None, Some(Ui::Select)));
    }

    #[test]
    fn celestite_then_slot() {
        let (d, mut u) = (data(), CelUi { focus: Focus::Inven, cursor: 1, ..ui() });
        // Enter on celestite 2: fe_equip with the cursor on the slot that wears it.
        assert_eq!(press(&mut u, &d, K::Enter), sound(Ui::Select));
        assert_eq!((u.focus, u.pick, u.slot), (Focus::Equip, Some(1), 1));
        // Num+ with a celestite picked buzzes; Escape drops the pick and hands the keys back.
        assert_eq!(press(&mut u, &d, K::Plus), sound(Ui::Error));
        assert_eq!(press(&mut u, &d, K::Escape), sound(Ui::Cancel));
        assert_eq!((u.focus, u.pick), (Focus::Inven, None));
        // Picked again and put in slot 3.
        assert_eq!(press(&mut u, &d, K::Enter), sound(Ui::Select));
        u.slot = 2;
        let out = press(&mut u, &d, K::Enter);
        assert_eq!(out.send, Some(vec![1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0]));
        assert_eq!((u.focus, u.pick), (Focus::Inven, None));
    }

    /// A 0x08F that shrinks the list under a held pick: the pick names no celestite, so the slot is cleared
    /// (FUN_10118220 returns 0), as retail does.
    #[test]
    fn shrunk_list_clears_the_slot() {
        let mut u = CelUi { focus: Focus::Equip, pick: Some(3), slot: 1, ..ui() };
        let mut p = vec![0u8; 0xb0];
        p[4] = 0b0010;
        p[0x24 + 0x14..0x24 + 0x14 + 3].copy_from_slice(&[1, 1, 2]);
        p[0x24 + 0x14 + 10 + 1] = 2;
        let d = CelData::parse(&p).unwrap();
        let out = press(&mut u, &d, K::Enter);
        // Set 1 (record 1), slot 1's celestite 2 taken off: every slot empty.
        assert_eq!(out.send, Some(vec![1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
        assert_eq!((u.focus, u.pick), (Focus::Inven, None));
    }

    /// The pointer resting over the other list is message 8 every frame (FUN_101174b0 / FUN_10117d90): with nothing
    /// picked the keys go over at once, with a pick held each frame buzzes.
    #[test]
    fn message_8_each_frame() {
        let d = data();
        let mut u = ui();
        assert_eq!((press(&mut u, &d, K::Plus), u.focus), (sound(Ui::Close), Focus::Inven));
        let mut u = CelUi { pick: Some(0), ..ui() };
        for _ in 0..3 {
            assert_eq!((press(&mut u, &d, K::Plus), u.focus), (sound(Ui::Error), Focus::Equip));
        }
    }

    /// White reaches only TINT_REACH rows from the cursor.
    #[test]
    fn white_only_near_the_cursor() {
        let d = data();
        let u = CelUi { focus: Focus::Inven, cursor: 0, ..ui() };
        assert_eq!(tint(&u, &d, 2, 1, 99, &bytes), WHITE);
        assert_eq!(tint(&u, &d, TINT_REACH + 1, 1, 99, &bytes), GREY);
    }

    #[test]
    fn refusals() {
        let d = data();
        // Outside the Mog House: the picks still move, the change is refused with message 0xb2.
        let mut u = CelUi { can_edit: false, focus: Focus::Inven, ..ui() };
        assert_eq!(press(&mut u, &d, K::Enter), Out { refuse: true, ..sound(Ui::Error) });
        let mut u = CelUi { can_edit: false, pick: Some(0), ..ui() };
        assert_eq!(press(&mut u, &d, K::Enter), Out { refuse: true, ..sound(Ui::Error) });
        // A grey celestite, a closed slot, no data.
        let mut u = CelUi { focus: Focus::Inven, ..ui() };
        assert_eq!(step(&mut u, Some(&d), K::Enter, false, false, 98, &bytes), sound(Ui::Error));
        let mut u = CelUi { set: 1, ..ui() };
        assert_eq!(press(&mut u, &d, K::Enter), sound(Ui::Error));
        assert_eq!(step(&mut ui(), None, K::Enter, false, false, 99, &bytes), sound(Ui::Error));
    }

    #[test]
    fn cursors_and_sets() {
        let (d, mut u) = (data(), ui());
        // Three open slots: Down stops at the third, silent.
        assert_eq!(press(&mut u, &d, K::ArrowDown).sound, Some(Ui::Cursor));
        press(&mut u, &d, K::ArrowDown);
        assert_eq!((press(&mut u, &d, K::ArrowDown), u.slot), (Out::default(), 2));
        // Alt+Right / Alt+Left: the next / previous set, the cursor back inside it.
        assert_eq!(step(&mut u, Some(&d), K::ArrowRight, true, true, 99, &bytes), Out::default());
        assert_eq!((u.set, u.slot), (1, 0));
        step(&mut u, Some(&d), K::ArrowLeft, true, true, 99, &bytes);
        step(&mut u, Some(&d), K::ArrowLeft, true, true, 99, &bytes);
        assert_eq!(u.set, 5);
        // Plain Left / Right do nothing in fe_equip; Num+ hands the keys over with SE 0013, Escape closes.
        assert_eq!(press(&mut u, &d, K::ArrowRight), Out::default());
        assert_eq!((press(&mut u, &d, K::Plus), u.focus), (sound(Ui::Close), Focus::Inven));
        assert_eq!(press(&mut u, &d, K::ArrowDown).sound, Some(Ui::Cursor));
        assert_eq!(press(&mut u, &d, K::Escape), Out { close: true, ..sound(Ui::Cancel) });
    }

    #[test]
    fn tenth_slot_wraps() {
        let mut d = data();
        d.sets[1][..10].fill(1);
        let mut u = CelUi { slot: 9, ..ui() };
        assert_eq!((press(&mut u, &d, K::ArrowDown).sound, u.slot), (Some(Ui::Cursor), 0));
        assert_eq!((press(&mut u, &d, K::ArrowUp), u.slot), (Out::default(), 0));
    }
}
