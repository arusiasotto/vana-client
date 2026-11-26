//! Server catalogue repository on the login screen (private servers): one GitHub repo for mods.json and dats.json.

use super::catalogue_cfg;
use super::game_ui::{GREY, GameUi, WHITE, YELLOW};
use super::twofa::View;
use super::{UiInput, inside};

const TITLE: &str = "Server catalogue";
const LABEL: &str = "Repository";
const HINT: &str = "owner/repo or GitHub URL";
const LINE: f32 = 16.0;

pub struct LoginCatalogue {
    login_key: String,
    keys: Vec<String>,
    pub text: String,
    pub focus: usize,
}

pub enum Act {
    Save,
    Clear,
    Close,
}

impl LoginCatalogue {
    pub fn new(login_key: String, keys: Vec<String>) -> Self {
        let text = catalogue_cfg::repo_for_keys(&keys);
        Self { login_key, keys, text, focus: 0 }
    }

    pub fn save(&self) -> Option<Vec<String>> {
        catalogue_cfg::save_repo(&self.login_key, &self.keys, &self.text)
    }

    pub fn clear(&self) -> Option<Vec<String>> {
        catalogue_cfg::clear_repo(&self.keys)
    }

    pub fn help(&self) -> &'static str {
        "Paste the GitHub repo with catalogue/mods.json and catalogue/dats.json. Save or Enter stores it; Clear \
         removes the saved repo for this server."
    }

    fn type_in(&mut self, t: &str) {
        self.text.extend(t.chars().filter(|c| !c.is_control()));
        if self.text.chars().count() > 200 {
            self.text = self.text.chars().take(200).collect();
        }
    }
}

struct Lay {
    frame: [f32; 4],
    lines: Vec<([f32; 4], String, [u8; 4], bool)>,
    fields: Vec<[f32; 4]>,
    buttons: Vec<[f32; 4]>,
}

fn layout(lu: &GameUi, size: [u32; 2], text: &str, f: f32) -> Lay {
    let (sw, sh) = (size[0] as f32, size[1] as f32);
    let ww = 440.0 * f;
    let cw = ww - 32.0 * f;
    let mut y = 12.0 * f;
    let mut lines = Vec::new();
    let push = |lines: &mut Vec<_>, y: &mut f32, text: String, colour: [u8; 4], centre: bool| {
        lines.push(([16.0 * f, *y, cw, LINE * f], text, colour, centre));
        *y += LINE * f;
    };
    push(&mut lines, &mut y, TITLE.into(), YELLOW, true);
    y += 4.0 * f;
    for l in lu.wrap("The mods and DAT packs offered for this server are listed in that repository.", cw / f) {
        push(&mut lines, &mut y, l, WHITE, false);
    }
    y += 8.0 * f;
    let lw = lu.text_width(LABEL) + 4.0;
    lines.push(([16.0 * f, y + 1.0 * f, lw * f, LINE * f], LABEL.into(), WHITE, false));
    let field = [(20.0 + lw) * f, y, cw - (4.0 + lw) * f, 18.0 * f];
    y += 22.0 * f;
    if text.is_empty() {
        push(&mut lines, &mut y, HINT.into(), GREY, false);
    }
    y += 8.0 * f;
    const NAMES: [&str; 3] = ["Save", "Clear", "Cancel"];
    let widths: Vec<f32> = NAMES.iter().map(|n| ((lu.label_width(n) + 14.0).max(88.0) * f).round()).collect();
    let mut x = (ww - widths.iter().sum::<f32>() - 24.0 * f) / 2.0;
    let buttons: Vec<_> = widths
        .iter()
        .map(|w| {
            let r = [x, y, *w, 16.0 * f];
            x += w + 24.0 * f;
            r
        })
        .collect();
    let wh = y + 30.0 * f;
    let (wx, wy) = (((sw - ww) / 2.0).round(), ((sh - wh) / 2.0).round());
    let at = |r: [f32; 4]| [wx + r[0], wy + r[1], r[2], r[3]];
    Lay {
        frame: [wx, wy, ww, wh],
        lines: lines.into_iter().map(|(r, t, c, centre)| (at(r), t, c, centre)).collect(),
        fields: vec![at(field)],
        buttons: buttons.into_iter().map(at).collect(),
    }
}

/// The window over the login form; `modern` receives a view for the modern layer.
pub fn window(
    lu: &mut GameUi,
    input: &UiInput,
    size: [u32; 2],
    st: &mut LoginCatalogue,
    sounds: &mut Vec<crate::audio::Ui>,
    modern: Option<&mut Option<View>>,
) -> Option<Act> {
    let f = if modern.is_some() { 1.5 } else { 1.0 };
    let hover_moves = modern.is_none();
    let lay = layout(lu, size, &st.text, f);
    const FIELD: usize = 1;
    const CLEAR_BTN: usize = 2;
    let items = FIELD + lay.buttons.len();
    let was = st.focus;
    let mut press = None;
    if let Some(k) = input.pointer.and_then(|p| lay.buttons.iter().position(|r| inside(r, p))) {
        lu.hover.set(true);
        if input.moved && hover_moves {
            st.focus = FIELD + k;
        }
        if input.clicked {
            press = Some(FIELD + k);
        }
    }
    if input.pointer.is_some_and(|p| input.clicked && inside(&lay.fields[0], p)) {
        st.focus = 0;
    }
    for ev in &input.events {
        match ev {
            egui::Event::Text(t) | egui::Event::Paste(t) if st.focus == 0 => st.type_in(t),
            egui::Event::Key { key, pressed: true, modifiers, .. } => match key {
                egui::Key::Tab if modifiers.shift => st.focus = (st.focus + items - 1) % items,
                egui::Key::Tab => st.focus = (st.focus + 1) % items,
                egui::Key::ArrowDown | egui::Key::ArrowRight => st.focus = (st.focus + 1) % items,
                egui::Key::ArrowUp | egui::Key::ArrowLeft => st.focus = (st.focus + items - 1) % items,
                egui::Key::Backspace if st.focus == 0 => {
                    let n = st.text.chars().count();
                    if n > 0 {
                        st.text = st.text.chars().take(n - 1).collect();
                    }
                }
                egui::Key::Enter => press = Some(if st.focus == 0 { FIELD } else { st.focus }),
                egui::Key::Escape => press = Some(items - 1),
                _ => {}
            },
            _ => {}
        }
    }
    let mut act = None;
    if let Some(i) = press {
        st.focus = i;
        sounds.push(if i == items - 1 { crate::audio::Ui::Cancel } else { crate::audio::Ui::Select });
        match i {
            FIELD => act = Some(Act::Save),
            CLEAR_BTN => act = Some(Act::Clear),
            _ => act = Some(Act::Close),
        }
    } else if st.focus != was {
        sounds.push(crate::audio::Ui::Cursor);
    }
    let lay = layout(lu, size, &st.text, f);
    let names: [&str; 3] = ["Save", "Clear", "Cancel"];
    if let Some(out) = modern {
        *out = Some(View {
            frame: lay.frame,
            lines: lay.lines,
            qr: None,
            fields: lay.fields.iter().map(|r| (*r, st.text.clone())).collect(),
            buttons: lay.buttons.iter().zip(names.iter()).map(|(r, &n)| (*r, n)).collect(),
            focus: st.focus,
            busy: false,
        });
        return act;
    }
    let [wx, wy, ww, wh] = lay.frame;
    lu.rect(wx + 2.0, wy + 2.0, ww - 4.0, wh - 4.0, [0.02, 0.02, 0.06, 0.9]);
    lu.frame(wx, wy, ww, wh);
    for (r, text, colour, centre) in &lay.lines {
        let x = if *centre { r[0] + ((r[2] - lu.text_width(text)) / 2.0).round() } else { r[0] };
        lu.text(text, x, r[1], 0, *colour);
    }
    let r = lay.fields[0];
    let on = st.focus == 0;
    lu.rect(r[0], r[1], r[2], r[3], if on { [0.16, 0.2, 0.45, 0.6] } else { [0.0, 0.0, 0.0, 0.35] });
    let shown = if st.text.is_empty() && !on { HINT } else { &st.text };
    lu.text(shown, r[0] + 4.0, r[1] + 1.0, 0, if st.text.is_empty() && !on { GREY } else { WHITE });
    if on && lu.blink() {
        lu.rect(r[0] + 4.0 + lu.text_width(shown), r[1] + 2.0, 2.0, 14.0, [1.0, 1.0, 1.0, 0.9]);
    }
    let first = 1usize;
    for (k, r) in lay.buttons.iter().enumerate() {
        let on = st.focus == first + k;
        super::settings::button(lu, *r, if on { 0x8080_5020 } else { 0x8080_8080 });
        let lx = r[0] + ((r[2] - lu.label_width(names[k])) / 2.0).round();
        lu.label(
            names[k],
            lx + if on { -1.0 } else { 0.0 },
            r[1] + 1.0 + if on { -1.0 } else { 0.0 },
            0xffffffff,
            true,
        );
    }
    act
}
