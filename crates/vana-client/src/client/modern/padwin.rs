//! Ours: the Controller window (client/padcfg.rs), opened from the Settings window's Controller entry. Retail's
//! Config > Gamepad starts the external FFXiPadConfig.exe instead (FUN_101bccb0); this is that tool's XInput page in the
//! client: each function's button (Button Settings) and its button while Button Combination is held (Button
//! Combination Settings), assigned by pressing it on the pad, with the tool's controller list and options at the
//! right. Up / Down pick a
//! function, Tab turns the page, Enter assigns (then press the button, or push a stick on a direction), Delete clears,
//! Escape stops waiting, then closes.

use super::super::World;
use super::super::gamepad::Source;
use super::super::padcfg::{self, Kind, LISTEN, PadCfg};
use super::kit::{self, Btn};
use super::{Panels, Title};
use crate::audio::Ui as Se;
use egui::{Align2, Color32, FontFamily, FontId, Sense, Ui, pos2, vec2};

const LIST_W: f32 = 430.0;
const SIDE_W: f32 = 320.0;
const ROW_H: f32 = 26.0;
const TABS: [&str; 2] = ["Button Settings", "Button Combination Settings"];

pub fn shown(w: &World) -> bool {
    w.modern && w.padcfg.open
}

/// The window takes the keys (no prompt or event over it).
pub fn takes_keys(w: &World) -> bool {
    shown(w) && w.prompt.is_none() && w.confirm.is_none() && !super::super::event::active(w)
}

/// Opens it (the Settings window's Controller entry).
pub fn open(w: &mut World) {
    let p = &mut w.padcfg;
    (p.open, p.listening, p.note, p.list_devices) = (true, None, String::new(), true);
    p.follow.set(true);
    p.raise = true;
    w.sounds.push(Se::Select as u32);
}

/// The keys while it is open. True when it took them.
pub fn events(w: &mut World, events: &[egui::Event]) -> bool {
    if !takes_keys(w) {
        return false;
    }
    let n = padcfg::row_count();
    for e in events {
        let egui::Event::Key { key, pressed: true, modifiers, .. } = e else { continue };
        let p = &mut w.padcfg;
        let sound = match key {
            egui::Key::Escape if p.listening.is_some() => {
                (p.listening, p.note) = (None, "Left as it was.".into());
                Se::Cancel
            }
            egui::Key::Escape => {
                p.open = false;
                Se::Cancel
            }
            _ if p.listening.is_some() => continue,
            egui::Key::ArrowUp => {
                p.row = (p.row + n - 1) % n;
                p.follow.set(true);
                Se::Cursor
            }
            egui::Key::ArrowDown => {
                p.row = (p.row + 1) % n;
                p.follow.set(true);
                Se::Cursor
            }
            egui::Key::Tab | egui::Key::ArrowLeft | egui::Key::ArrowRight => {
                let back = modifiers.shift || *key == egui::Key::ArrowLeft;
                p.tab = if back { p.tab.saturating_sub(1) } else { (p.tab + 1).min(1) };
                Se::Cursor
            }
            egui::Key::Enter => {
                listen(p);
                Se::Select
            }
            egui::Key::Delete | egui::Key::Backspace => {
                p.clear();
                Se::Select
            }
            _ => continue,
        };
        w.sounds.push(sound as u32);
    }
    true
}

fn listen(p: &mut PadCfg) {
    (p.listening, p.note) = (Some(LISTEN), String::new());
}

enum Click {
    Row(usize),
    Tab(usize),
    Assign,
    Clear,
    Options(bool, bool, u32),
    Rumble(bool),
    /// padguid000.
    Device(String),
    /// One of padmode000's XInput, sliders and hat options (0..3), on or off.
    Flag(usize, bool),
    Defaults,
    Copy,
    Retail,
    Reread,
    Close,
}

fn heading(ui: &mut Ui, m: &super::Modern, s: &str, first: bool) {
    if !first {
        ui.add_space(8.0);
    }
    ui.label(
        egui::RichText::new(s.to_uppercase())
            .size(m.theme.small - 2.0)
            .color(m.theme.color("bronze"))
            .family(FontFamily::Name(super::STRONG.into())),
    );
    ui.add_space(2.0);
}

fn note(ui: &mut Ui, m: &super::Modern, s: &str, colour: &str) {
    ui.label(egui::RichText::new(s).size(m.theme.small).color(m.theme.color(colour)));
}

/// The functions of the open page, grouped, with what each has.
fn list(ui: &mut Ui, m: &super::Modern, p: &PadCfg, click: &mut Option<Click>) {
    ui.vertical(|ui| {
        ui.set_width(LIST_W);
        if let Some(k) = kit::tab_strip(ui, m, "controller tabs", &TABS, p.tab.min(1), true) {
            *click = Some(Click::Tab(k));
        }
        let maps = p.maps();
        let map = &maps[p.tab.min(1)];
        let font = FontId::proportional(m.theme.small);
        kit::scroll(ui, "controller rows", 440.0, |ui| {
            let mut group = "";
            for (i, (g, r)) in padcfg::rows().enumerate() {
                if g != group {
                    heading(ui, m, g, group.is_empty());
                    group = g;
                }
                let (rect, resp) = ui.allocate_exact_size(vec2(LIST_W - 12.0, ROW_H), Sense::click());
                let on = i == p.row;
                let face = match () {
                    _ if on => "controls/list_row_selected",
                    _ if resp.hovered() => "controls/list_row_hover",
                    _ => "controls/list_row_normal",
                };
                super::rows::face(ui.painter(), m, rect, face, Color32::WHITE);
                let ink = if on { m.theme.color("gold") } else { m.theme.color("text") };
                let label = kit::elide(ui, r.label, &font, LIST_W * 0.55);
                ui.painter().text(
                    pos2(rect.min.x + 10.0, rect.center().y),
                    Align2::LEFT_CENTER,
                    label,
                    font.clone(),
                    ink,
                );
                let (value, c) = match (on, p.listening) {
                    (true, Some(_)) if matches!(r.kind, Kind::Dir(..)) && p.tab == 0 => {
                        ("Press a button or push a stick…".to_string(), "gold")
                    }
                    (true, Some(_)) => ("Press a button…".to_string(), "gold"),
                    _ if map[r.pos] == -1 => (padcfg::name_of(-1, p.di), "muted"),
                    _ => (padcfg::name_of(map[r.pos], p.di), "text"),
                };
                ui.painter().text(
                    pos2(rect.max.x - 10.0, rect.center().y),
                    Align2::RIGHT_CENTER,
                    value,
                    font.clone(),
                    m.theme.color(c),
                );
                if on && p.follow.take() {
                    ui.scroll_to_rect(rect, None);
                }
                if resp.clicked() {
                    *click = Some(Click::Row(i));
                }
                ui.add_space(2.0);
            }
        });
        ui.add_space(4.0);
        let line = match p.listening {
            Some(t) => format!("Waiting for the controller ({:.0} s). Escape leaves it as it was.", t.ceil()),
            None if !p.note.is_empty() => p.note.clone(),
            None => "Enter or a click assigns; Delete unassigns; Tab turns the page.".into(),
        };
        note(ui, m, &line, if p.listening.is_some() { "gold" } else { "muted" });
    });
}

/// The function's help, its buttons, the tool's options and where the settings come from.
fn side(ui: &mut Ui, m: &super::Modern, p: &PadCfg, click: &mut Option<Click>) {
    ui.vertical(|ui| {
        ui.set_width(SIDE_W);
        if let Some((g, r)) = padcfg::row(p.row) {
            let title = if matches!(r.kind, Kind::Dir(..)) { format!("{g}: {}", r.label) } else { r.label.to_string() };
            heading(ui, m, &title, true);
            ui.label(egui::RichText::new(r.help).size(m.theme.small).color(m.theme.color("text")));
            if p.tab == 1 {
                note(ui, m, "Used while the Button Combination button is held. Buttons only.", "muted");
            }
            ui.add_space(4.0);
            ui.horizontal(|ui| {
                let b = Btn { lit: p.listening.is_some(), ..Default::default() };
                if kit::clicked(&kit::button(ui, m, "Assign", 90.0, b), b) {
                    *click = Some(Click::Assign);
                }
                let b = Btn::default();
                if kit::clicked(&kit::button(ui, m, "Unassign", 90.0, b), b) {
                    *click = Some(Click::Clear);
                }
            });
        }
        let set = p.set.clone().unwrap_or_else(|| super::super::gamepad::settings(&Default::default(), None));
        heading(ui, m, "Controller", false);
        let shown = match p.devices.iter().find(|d| d.0.eq_ignore_ascii_case(&set.padguid)) {
            Some(d) => d.1.clone(),
            None if set.padguid.is_empty() => "Not chosen (the first controller)".to_string(),
            None => "The chosen controller (not connected)".to_string(),
        };
        egui::ComboBox::from_id_salt("controller device").selected_text(shown).width(SIDE_W - 20.0).show_ui(ui, |ui| {
            for (guid, name) in &p.devices {
                if ui.selectable_label(guid.eq_ignore_ascii_case(&set.padguid), name).clicked() {
                    *click = Some(Click::Device(guid.clone()));
                }
            }
        });
        if p.devices.is_empty() {
            note(ui, m, "No game controller connected.", "muted");
        }
        let onoff = ["Off".to_string(), "On".to_string()];
        for (k, label) in ["Use XInput", "Use sliders", "Use hat switch"].into_iter().enumerate() {
            ui.label(egui::RichText::new(label).size(m.theme.small).color(m.theme.color("text")));
            let at = [set.xinput, set.sliders, set.hat][k];
            if let Some(v) = kit::choice(ui, m, &onoff, at as usize, 0) {
                *click = Some(Click::Flag(k, v == 1));
            }
            // Retail keeps the XInput DLL's pad (+0xc9a) once it loaded, until the game starts again.
            if k == 0 && !set.xinput {
                note(ui, m, "Turning XInput off takes effect at the next start.", "muted");
            }
        }
        heading(ui, m, "Gamepad Options", false);
        ui.label(egui::RichText::new("Enable Gamepad").size(m.theme.small).color(m.theme.color("text")));
        if let Some(k) = kit::choice(ui, m, &onoff, set.on as usize, 0) {
            *click = Some(Click::Options(k == 1, set.background, p.dead));
        }
        ui.label(
            egui::RichText::new("Enable gamepad when game is inactive")
                .size(m.theme.small)
                .color(m.theme.color("text")),
        );
        if let Some(k) = kit::choice(ui, m, &onoff, set.background as usize, 0) {
            *click = Some(Click::Options(set.on, k == 1, p.dead));
        }
        ui.label(egui::RichText::new("Enable Force Feedback").size(m.theme.small).color(m.theme.color("text")));
        if let Some(k) = kit::choice(ui, m, &onoff, set.rumble as usize, 0) {
            *click = Some(Click::Rumble(k == 1));
        }
        let at = (p.dead / 5).min(12) as usize;
        let shown = format!("{}%", p.dead);
        if let (Some(k), _) = kit::slider_setting(ui, m, "Stick Dead Zone (Vana Client)", false, false, 13, at, &shown)
        {
            *click = Some(Click::Options(set.on, set.background, k as u32 * 5));
        }
        heading(ui, m, "Settings in Use", false);
        let (from, colour) = match set.source {
            Source::Config => ("Saved by Vana Client in config.json.".to_string(), "text"),
            Source::Retail => (
                format!(
                    "The retail Gamepad Config tool's, read from {}.",
                    p.retail.as_deref().unwrap_or("the registry")
                ),
                "gold",
            ),
            Source::Default if set.padsin == super::super::gamepad::DINPUT_PADSIN => {
                ("The tool's Pattern A, for a DirectInput controller (no saved settings).".to_string(), "muted")
            }
            Source::Default => ("The XInput setup (no saved settings).".to_string(), "muted"),
        };
        note(ui, m, &from, colour);
        if set.saved && p.retail.is_some() {
            note(ui, m, "Retail settings were found too; Use Retail Settings switches to them.", "muted");
        }
        let pads = if p.pads.is_empty() {
            "No controller connected.".to_string()
        } else {
            format!(
                "Playing: {}{}",
                p.pads[0],
                if p.pads.len() > 1 { format!(" (+{} more)", p.pads.len() - 1) } else { String::new() }
            )
        };
        note(ui, m, &pads, "muted");
        ui.add_space(6.0);
        let labels = ["XInput Setup", "Copy Assignment", "Use Retail Settings", "Look Again"];
        let off = if p.retail.is_none() || !set.saved { 1 << 2 } else { 0 };
        match kit::buttons(ui, m, &labels, None, 0, off) {
            Some(0) => *click = Some(Click::Defaults),
            Some(1) => *click = Some(Click::Copy),
            Some(2) => *click = Some(Click::Retail),
            Some(3) => *click = Some(Click::Reread),
            _ => {}
        }
    });
}

fn apply(w: &mut World, c: Click) {
    let p = &mut w.padcfg;
    let sound = match c {
        Click::Row(i) => {
            // A click on the cursor's row assigns it, as Enter does.
            if p.row == i && p.listening.is_none() {
                listen(p);
                Se::Select
            } else {
                (p.row, p.listening) = (i, None);
                Se::Cursor
            }
        }
        Click::Tab(k) => {
            (p.tab, p.listening) = (k, None);
            Se::Cursor
        }
        Click::Assign => {
            listen(p);
            Se::Select
        }
        Click::Clear => {
            p.clear();
            Se::Select
        }
        Click::Options(on, bg, dead) => {
            p.set_options(on, bg, dead);
            Se::Cursor
        }
        Click::Rumble(on) => {
            p.set_rumble(on);
            Se::Cursor
        }
        Click::Device(guid) => {
            p.set_device(guid);
            Se::Cursor
        }
        Click::Flag(k, on) => {
            p.set_flag(k, on);
            Se::Cursor
        }
        Click::Defaults => {
            p.defaults();
            Se::Select
        }
        Click::Copy => {
            p.copy();
            Se::Select
        }
        Click::Retail => {
            p.use_retail = true;
            p.note = "Using the retail Gamepad Config tool's settings.".into();
            Se::Select
        }
        Click::Reread => {
            (p.reread, p.list_devices) = (true, true);
            p.note = "Looking for the retail settings again.".into();
            Se::Select
        }
        Click::Close => {
            p.open = false;
            Se::Cancel
        }
    };
    w.sounds.push(sound as u32);
}

pub fn draw(p: &mut Panels, w: &mut World) {
    if !shown(w) {
        return;
    }
    // Over the Settings window it is opened from: when it opens (a click on Settings' Controller button put that one
    // in front), and while a menu column window is shown, since those are raised every frame (Panels::show). Otherwise
    // the order is the clicks', so a prompt can still come in front of it.
    let column = super::COLUMN.iter().any(|c| p.this.contains_key(*c));
    if std::mem::take(&mut w.padcfg.raise) || column {
        p.ctx.move_to_top(egui::LayerId::new(egui::Order::Middle, egui::Id::unique(("modern panel", "controller"))));
    }
    if let Some(c) = window(p, &w.padcfg) {
        apply(w, c);
    }
}

/// The modern-shot sample: the default layout, waiting on Movement Up.
pub(super) fn sample(p: &mut Panels) {
    let mut s = PadCfg { open: true, dead: 33, ..Default::default() };
    s.set = Some(super::super::gamepad::settings(&Default::default(), None));
    s.pads = vec!["Xbox Wireless Controller".into()];
    s.devices = vec![("{6F1D2B61-D5A0-11CF-BFC7-444553540000}".into(), "Xbox Wireless Controller".into())];
    s.row = padcfg::rows().position(|r| r.0 == "Movement").unwrap_or(0);
    s.listening = Some(LISTEN);
    s.follow.set(true);
    window(p, &s);
}

fn window(p: &mut Panels, s: &PadCfg) -> Option<Click> {
    let m = p.m;
    let mut click = None;
    p.panel(
        "controller",
        Some(Title { icon: Some("icons/config"), text: "Controller", note: None, name: false }),
        LIST_W + SIDE_W + 40.0,
        |ui| {
            ui.horizontal_top(|ui| {
                list(ui, m, s, &mut click);
                ui.add_space(16.0);
                side(ui, m, s, &mut click);
            });
            ui.add_space(6.0);
            ui.horizontal(|ui| {
                let b = Btn::default();
                if kit::clicked(&kit::button(ui, m, "Close", 90.0, b), b) {
                    click = Some(Click::Close);
                }
                note(
                    ui,
                    m,
                    "Vana Client's copy of the retail Gamepad Config tool (Config > Gamepad). Changes apply at once.",
                    "muted",
                );
            });
        },
    );
    click
}
