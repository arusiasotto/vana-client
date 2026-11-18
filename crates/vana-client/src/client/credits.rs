//! The ending credits roll (event op 0x71 subs 0x50..0x55; DAT_10621944, FUN_10163090..): a text file scrolled up
//! over a panel, drawn first in the UI pass (FUN_101630e0 from FUN_1015f6a0), so under every window. Its one user is
//! zone 291's event 9 (npc 0x01123304).

use super::World;
use super::game_ui::GameUi;

/// Lines 14 virtual pixels apart; at most 37 drawn (FUN_101630e0).
const LINE: f32 = 14.0;
const SHOWN: usize = 37;
/// The text file of sub 0x50 val (0x18892 + val) and the font texture file the window loads (0x18891).
pub const TEXT_FILE: u32 = 0x18892;

pub struct Credits {
    /// The lines as FFXI Shift-JIS, after FUN_1019e150's glyph map and the '+' name.
    lines: Vec<Vec<u8>>,
    /// Sub 0x54's percentages (x0, y0, x1, y1; None = the default panel) and sub 0x55's ARGB.
    rect: Option<[i32; 4]>,
    colour: u32,
    /// Ticks per virtual pixel (+0x48; below 0 not started), the tick count (+0x44), the top line, its offset.
    speed: f32,
    acc: f32,
    top: usize,
    off: f32,
    pub done: bool,
}

/// FUN_1019e150: letters, digits, `/ & . , - '` and space kept; `{` and `@` as spaces; 0xa9 and `] [ ^ } ~ | \ #` to
/// the font's (c) and accented codes; anything else dropped (no advance).
fn glyphs(line: &[u8], name: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    for &c in line {
        let code: u16 = match c {
            b'0'..=b'9' | b'a'..=b'z' | b'A'..=b'Z' | b'/' | b'&' | b'.' | b',' | b'-' | b'\'' | b' ' => c as u16,
            b'{' | b'@' => 0x20,
            0xa9 => 0xc887,
            b']' => 0xc785,
            b'[' => 0xc885,
            b'^' => 0xcd85,
            b'}' => 0xd385,
            b'~' => 0xd585,
            b'|' => 0xdb85,
            b'\\' => 0xca85,
            b'#' => 0xce85,
            // FUN_1019eac0(-2, ...): the player's name, at most 31 characters.
            b'+' => {
                out.extend(name.iter().take(31));
                continue;
            }
            _ => continue,
        };
        if code > 0xff {
            out.extend([(code & 0xff) as u8, (code >> 8) as u8]);
        } else {
            out.push(code as u8);
        }
    }
    out
}

impl Credits {
    /// Sub 0x50 (FUN_10163130): 20 empty lines, then the file split at CR, LF or CRLF (FUN_1019ed70).
    pub fn open(data: &[u8], name: &str) -> Self {
        let name = crate::dat::font::encode_sjis(name);
        let mut lines: Vec<Vec<u8>> = vec![Vec::new(); 20];
        let mut cur = Vec::new();
        let mut k = 0;
        while k < data.len() {
            match data[k] {
                b'\r' => {
                    lines.push(glyphs(&std::mem::take(&mut cur), &name));
                    if data.get(k + 1) == Some(&b'\n') {
                        k += 1;
                    }
                }
                b'\n' => lines.push(glyphs(&std::mem::take(&mut cur), &name)),
                c => cur.push(c),
            }
            k += 1;
        }
        if !cur.is_empty() {
            lines.push(glyphs(&cur, &name));
        }
        Self { lines, rect: None, colour: 0xff00_0000, speed: -1.0, acc: 0.0, top: 0, off: 0.0, done: false }
    }

    /// Sub 0x52 (FUN_1019ec00(val, 1)): a roll of `secs` seconds in all, once.
    pub fn start(&mut self, secs: i32) {
        if self.speed < 0.0 {
            self.speed = (secs as f32 * 60.0 / (self.lines.len() as f32 * LINE)).max(1e-3);
        }
    }

    pub fn set_rect(&mut self, v: [i32; 4]) {
        self.rect = Some(v);
    }

    pub fn set_colour(&mut self, argb: u32) {
        self.colour = argb;
    }

    /// FUN_1019ead0: the ticks run on; each 14 pixels the top line goes, and past the last line the roll is done.
    /// Ours counts real 60 Hz ticks (retail adds at least one a frame, which a 300 fps frame limit would run 5x fast).
    pub fn tick(&mut self, ticks: f32) {
        if self.speed < 0.0 || self.done {
            return;
        }
        self.acc += ticks;
        self.off = self.acc / self.speed;
        while self.off >= LINE {
            self.top += 1;
            self.off -= LINE;
            self.acc -= LINE * self.speed;
            if self.top >= self.lines.len() {
                self.done = true;
                break;
            }
        }
    }
}

/// FUN_101630e0: the panel (no blending: opaque), then the lines from the top at x 310, y 14 i - off, colour
/// 0x80808080, all scaled by (W / 640, H / 480). Sub 0x54's panel: x0 = W v2 %, or 0 (v2 <= 0); y0 = H v4 %, or 0; x1 =
/// W v6 %, or W; y1 = H v8 %, but H when v4 <= 0 (retail tests v4 there). The default panel: x 294..746, y 0..H.
pub fn draw(gu: &mut GameUi, w: &World, sw: f32, sh: f32) {
    let Some(c) = w.credits.as_ref() else { return };
    let (sx, sy) = (sw / 640.0, sh / 480.0);
    let (x0, y0, x1, y1) = match c.rect {
        None => (294.0 * sx, 0.0, 746.0 * sx, sh),
        Some([v2, v4, v6, v8]) => (
            if v2 <= 0 { 0.0 } else { sw * v2 as f32 / 100.0 },
            if v4 <= 0 { 0.0 } else { sh * v4 as f32 / 100.0 },
            if v6 <= 0 { sw } else { sw * v6 as f32 / 100.0 },
            if v4 <= 0 { sh } else { sh * v8 as f32 / 100.0 },
        ),
    };
    // Its own quads and colours: op 0x51's level, which the windows take, does not dim it.
    gu.unleveled();
    let [b, g, r, _] = c.colour.to_le_bytes();
    gu.rect(x0, y0, x1 - x0, y1 - y0, [r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0, 1.0]);
    for (i, line) in c.lines.iter().skip(c.top).take(SHOWN).enumerate() {
        if line.is_empty() {
            continue;
        }
        let y = (LINE * i as f32 - c.off) * sy;
        gu.text_xy(line, 310.0 * sx, y, [0x80; 4], [sx, sy]);
    }
    gu.level_back();
}
