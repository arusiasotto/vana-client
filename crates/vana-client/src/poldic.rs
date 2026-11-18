//! PlayOnline's word dictionaries, as polcore.dll reads them: the packed sections (FUN_10001fd0), the word engine
//! (FUN_10049100, matched by FUN_100491e0) and the name dictionary built from an exact-name table and three engines
//! (FUN_1004a110, tested by FUN_1004a200). FFXiMain's name filter (FUN_101ba240) is the name dictionary over
//! "entryz.dic"; the chat's profanity mask ("vulgar2.dic") is one engine in its mask modes, which are not built here.
//!
//! The dictionaries are the player's own PlayOnline files: nothing of them is in this repository. The installer
//! copies "entryz.dic" out of PlayOnlineViewer.msi (install.rs).

use std::path::{Path, PathBuf};

/// Where the PlayOnline Viewer keeps its dictionaries, from the folder that holds "FINAL FANTASY XI" (the viewer's
/// Windows layout: SquareEnix/PlayOnlineViewer/data/dic).
pub const DIC_DIR: &str = "PlayOnlineViewer/data/dic";
/// The name dictionary's file (FFXiMain FUN_101ba480, PlayOnline file category 0x13).
pub const NAME_DIC: &str = "entryz.dic";

/// The name dictionary's path for a game folder (the one that holds "FINAL FANTASY XI").
pub fn name_dic_path(game_dir: &Path) -> PathBuf {
    game_dir.join(DIC_DIR).join(NAME_DIC)
}

fn u16_at(d: &[u8], o: usize) -> u16 {
    d.get(o..o + 2).map_or(0, |b| u16::from_le_bytes([b[0], b[1]]))
}

fn u32_at(d: &[u8], o: usize) -> u32 {
    d.get(o..o + 4).map_or(0, |b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
}

/// A byte of the text; past its end reads as the terminator the retail buffers carry.
fn at(d: &[u8], o: usize) -> u8 {
    d.get(o).copied().unwrap_or(0)
}

/// The cipher's 32 round keys (FUN_100019b0): the 8 key bytes mixed, then each key 5 times the one before.
fn round_keys(key: [u32; 2]) -> [u64; 32] {
    let mut s = [0u8; 8];
    s[..4].copy_from_slice(&key[1].rotate_right(16).to_le_bytes());
    s[4..].copy_from_slice(&key[0].rotate_left(8).to_le_bytes());
    s[0] = s[0].wrapping_add(0x45);
    for i in 1..8 {
        let b = s[i].wrapping_add(s[i - 1]).wrapping_sub(0x2c);
        s[i] = (s[i - 1] << 2) ^ b ^ 0x45;
    }
    let mut q = [u64::from_le_bytes(s); 32];
    for i in 1..32 {
        q[i] = q[i - 1].wrapping_mul(5);
    }
    q
}

/// The position word both block steps mix in (FUN_10001df0): the byte position repeated at 10-bit steps, plus a
/// constant.
fn position_word(pos: u32) -> u64 {
    let p = pos as u64;
    ((((((p << 10) | p) << 10) | p) << 10) | p).wrapping_add(0xa165_2347)
}

/// A packed section unpacked (FUN_10001fd0 → FUN_10001f20): 8-byte blocks, each chained on the packed bytes before
/// it (FUN_10001eb0: 8 rounds of + 0x78 − key byte, the table at 0x100c5b7c being x + 0x78) and then un-mixed as one
/// 64-bit word (FUN_10001df0). The last block holds the result word and the sum of bytes 0 and 4 of every block
/// before it; None when the size is not a multiple of 8, the sum is wrong or the result word is negative.
pub fn unpack(key: [u32; 2], packed: &[u8]) -> Option<Vec<u8>> {
    if packed.is_empty() || !packed.len().is_multiple_of(8) {
        return None;
    }
    let keys = round_keys(key);
    let mut out = vec![0u8; packed.len()];
    let (mut sum, mut before_last) = (0u32, 0u32);
    for (n, (src, dst)) in packed.as_chunks::<8>().0.iter().zip(out.as_chunks_mut::<8>().0).enumerate() {
        let pos = (n as u32).wrapping_mul(8);
        let key = keys[n & 0x1f];
        let kb = key.to_le_bytes();
        let mut prev = (pos >> 3) as u8 ^ 0x45;
        let mut block = [0u8; 8];
        for i in 0..8 {
            let mut b = src[i] ^ prev;
            prev = src[i];
            for k in kb {
                b = b.wrapping_add(0x78).wrapping_sub(k);
            }
            block[i] = b;
        }
        let v = (u64::from_le_bytes(block).wrapping_sub(key) ^ position_word(pos) ^ key).rotate_left(32);
        *dst = v.to_le_bytes();
        before_last = sum;
        sum = sum.wrapping_add(dst[0] as u32).wrapping_add(dst[4] as u32);
    }
    let n = out.len();
    (u32_at(&out, n - 4) == before_last && (u32_at(&out, n - 8) as i32) >= 0).then_some(out)
}

/// Where a match has to sit in the text (FUN_100491e0's modes 3 / 1 / 2).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Place {
    /// Mode 3 (FUN_10049c50): anywhere.
    Anywhere,
    /// Mode 1 (FUN_10049c70): only skipped characters before it.
    Start,
    /// Mode 2 (FUN_10049c90): only skipped characters after it.
    End,
}

/// One word engine (FUN_10049100), its section unpacked with key (1, 0); layout in MODLOG "Character creator: the
/// name filter".
pub struct Engine {
    data: Vec<u8>,
}

/// A tree of an engine (word or allowed), its table offsets resolved; layout in the same MODLOG entry.
#[derive(Clone, Copy)]
struct Tree {
    at: usize,
    children: usize,
    keys: usize,
    strings: usize,
    nodes: usize,
    fold: bool,
}

impl Engine {
    /// FUN_10049100: the section unpacked; None when it does not unpack.
    pub fn unpack(packed: &[u8]) -> Option<Self> {
        let data = unpack([1, 0], packed)?;
        (data.len() >= 0x4a38).then_some(Self { data })
    }

    fn b(&self, o: usize) -> u8 {
        at(&self.data, o)
    }

    fn tree(&self, slot: usize) -> Tree {
        let at = u32_at(&self.data, slot) as usize;
        let p = |k: usize| at.wrapping_add(u32_at(&self.data, at + k * 4) as usize).wrapping_add(0x48f4);
        Tree { at, children: p(0), keys: p(1), strings: p(2), nodes: p(3), fold: u32_at(&self.data, at + 0x10) != 0 }
    }

    /// The character at `p` is a two-byte one.
    fn wide(&self, t: &[u8], p: usize) -> bool {
        self.b(0x50 + at(t, p) as usize) != 0 && self.b(0x150 + at(t, p + 1) as usize) != 0
    }

    fn bit(&self, set: usize, c: u8) -> bool {
        self.b(set + (c >> 3) as usize) >> (c & 7) & 1 != 0
    }

    /// FUN_100493f0: the byte length of the character at `p` when it is a skipped one, else 0.
    fn skipped(&self, t: &[u8], p: usize) -> usize {
        let c = at(t, p);
        if self.wide(t, p) {
            if self.bit(0x10, c) && self.bit(0x30, at(t, p + 1)) { 2 } else { 0 }
        } else {
            self.bit(0x10, c) as usize
        }
    }

    /// FUN_10049560: the character at `p` as the trees compare it. A single byte goes through the fold table; a
    /// two-byte one through its own when the tree folds, else as it is (second byte high).
    fn folded(&self, t: &[u8], p: usize, fold: bool) -> u16 {
        let (c, d) = (at(t, p), at(t, p + 1));
        if self.wide(t, p) {
            if fold {
                let i = self.b(0x50 + c as usize) as usize + self.b(0x150 + d as usize) as usize * 0x30;
                u16_at(&self.data, 0x250 + i * 2)
            } else {
                u16::from_le_bytes([c, d])
            }
        } else {
            self.b(0x4930 + c as usize) as u16
        }
    }

    /// FUN_10049910: the key's place among a node's `count` sorted keys. With no keys polcore still compares key 0
    /// (its caller passes count − 1 as the signed upper bound).
    fn key_index(&self, key: u16, keys: usize, count: usize) -> Option<usize> {
        let k = |i: usize| u16_at(&self.data, keys + i * 2).wrapping_neg();
        let (mut lo, mut hi) = (0usize, count.saturating_sub(1));
        while lo < hi {
            let mid = (lo + hi) / 2;
            if k(mid) < key { lo = mid + 1 } else { hi = mid }
        }
        (k(lo) == key).then_some(lo)
    }

    /// FUN_100495f0: the tree walked from `node` over the text at `p` (`len` bytes left). Some(bytes used) when a
    /// word ends, skipped characters inside it included.
    fn walk(&self, tree: Tree, t: &[u8], mut p: usize, mut len: isize, mut node: usize) -> Option<usize> {
        let (mut used, mut idle) = (0usize, 0usize);
        // An empty run uses no byte: more of them in a row than the section can hold nodes is a cycle, on which
        // retail recurses without end.
        while p <= t.len() {
            let kind = self.b(node);
            let child_base = u16_at(&self.data, node + 2) as usize;
            let offset = u32_at(&self.data, node + 4) as usize;
            let mut k = 0usize;
            match kind {
                // A branch: the next character picks the child.
                1 => {
                    loop {
                        let n = self.skipped(t, p + k);
                        if n == 0 {
                            break;
                        }
                        k += n;
                        if len <= k as isize {
                            return None;
                        }
                    }
                    let code = self.folded(t, p + k, tree.fold);
                    k += if code < 0x100 { 1 } else { 2 };
                    let i = self.key_index(code, tree.keys + offset * 2, self.b(node + 1) as usize)?;
                    used += k;
                    let child = match child_base {
                        0 => 0,
                        base => u16_at(&self.data, tree.children + (base + i) * 2) as usize,
                    };
                    if child == 0 {
                        return Some(used);
                    }
                    node = tree.nodes + child * 8;
                }
                // A run of characters, stored negated.
                2 => {
                    let start = tree.strings + offset;
                    let run: Vec<u8> =
                        (0..).map(|i| self.b(start + i).wrapping_neg()).take_while(|&c| c != 0).take(0x100).collect();
                    if run.len() > 0xfe {
                        return None;
                    }
                    let mut r = 0usize;
                    while r < run.len() {
                        if len <= k as isize {
                            return None;
                        }
                        let n = self.skipped(t, p + k);
                        if n > 0 {
                            k += n;
                            continue;
                        }
                        if self.folded(&run, r, tree.fold) != self.folded(t, p + k, tree.fold) {
                            return None;
                        }
                        r += if self.wide(&run, r) { 2 } else { 1 };
                        k += if self.wide(t, p + k) { 2 } else { 1 };
                    }
                    used += k;
                    let child = match child_base {
                        0 => 0,
                        base => u16_at(&self.data, tree.children + base * 2) as usize,
                    };
                    if child == 0 {
                        return Some(used);
                    }
                    node = tree.nodes + child * 8;
                }
                _ => return None,
            }
            idle = if k == 0 { idle + 1 } else { 0 };
            if idle > self.data.len() / 8 {
                return None;
            }
            p += k;
            len -= k as isize;
        }
        None
    }

    /// FUN_10049470: a word of the tree at `p`. Ok(bytes used after the first character) on a match; Err(1) when
    /// the first character is a two-byte one, else Err(0).
    fn find(&self, tree: Tree, t: &[u8], p: usize, len: isize) -> Result<usize, usize> {
        let code = self.folded(t, p, tree.fold);
        let (first, miss, width) = if len >= 2 && self.wide(t, p) {
            let i =
                self.b(0x50 + (code & 0xff) as usize) as usize + self.b(0x150 + (code >> 8) as usize) as usize * 0x30;
            (u16_at(&self.data, tree.at + 0x14 + i * 2), 1, 2)
        } else {
            (u16_at(&self.data, tree.at + 0x46f4 + code as usize * 2), 0, 1)
        };
        if first == 0 {
            return Err(miss);
        }
        self.walk(tree, t, p + width, len - width as isize, tree.nodes + first as usize * 8).ok_or(miss)
    }

    /// FUN_100491e0 in its test modes: the text holds a word of the dictionary at the asked place. Skipped
    /// characters are stepped over, and a word of the allowed tree is stepped over whole. Like retail, the Start and
    /// End modes answer at the first word found, wherever it is.
    pub fn matches(&self, text: &[u8], place: Place) -> bool {
        let (words, allowed) = (self.tree(0x4a30), self.tree(0x4a34));
        let len = text.len();
        // Retail measures the first character's width at the end of the match, not at its start.
        let end = |i: usize, used: usize| i + used + if self.wide(text, i + used) { 2 } else { 1 };
        let mut i = 0usize;
        while i < len {
            let n = self.skipped(text, i);
            if n > 0 {
                i += n;
                continue;
            }
            let left = (len - i) as isize;
            if let Ok(used) = self.find(allowed, text, i, left) {
                i = end(i, used);
                continue;
            }
            match self.find(words, text, i, left) {
                Err(wide) => i += 1 + wide,
                Ok(used) => {
                    return match place {
                        Place::Anywhere => true,
                        Place::Start => self.only_skipped(text, 0, i),
                        Place::End => self.only_skipped(text, end(i, used), len),
                    };
                }
            }
        }
        false
    }

    /// Only skipped characters from `from` up to `to`.
    fn only_skipped(&self, t: &[u8], mut from: usize, to: usize) -> bool {
        while from < to {
            match self.skipped(t, from) {
                0 => break,
                n => from += n,
            }
        }
        from >= to
    }
}

/// The characters the exact-name table skips (polcore DAT_100f5934, one bit per byte value): NUL, 0x20..0x2f,
/// 0x3a..0x40, 0x5b..0x5f, 0x7b..0x7e, 0x81, 0x84 and 0x87.
const EXACT_SKIP: [u8; 32] = [
    0x01, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0xfc, 0x01, 0x00, 0x00, 0xf8, 0x00, 0x00, 0x00, 0x78, 0x92, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
];

fn exact_skip(c: u8) -> bool {
    EXACT_SKIP[(c >> 3) as usize] >> (c & 7) & 1 != 0
}

/// A byte as the exact-name table reads it: a signed char, A..Z lowered.
fn exact_lower(c: u8) -> i32 {
    let c = c as i8 as i32;
    if (0x41..=0x5a).contains(&c) { c + 0x20 } else { c }
}

/// FUN_10049fa0: a letter or digit as a base-36 digit, anything else 0.
fn base36(c: u8) -> u32 {
    match exact_lower(c) {
        c @ 0x30..=0x39 => (c - 0x30) as u32,
        c @ 0x61..=0x7a => (c - 0x57) as u32,
        _ => 0,
    }
}

/// The exact-name table's bucket for a name (FUN_10049e40's hash): the first two kept characters as base-36 digits
/// (first × 32, xor the second), plus every kept character, low 10 bits.
fn exact_bucket(name: &[u8]) -> usize {
    let mut kept = name.iter().copied().filter(|&c| !exact_skip(c));
    let mut hash = kept.next().map_or(0, |c| base36(c) << 5) ^ kept.next().map_or(0, base36);
    for c in name.iter().copied().filter(|&c| !exact_skip(c)) {
        hash = hash.wrapping_add(exact_lower(c) as u32);
    }
    (hash & 0x3ff) as usize
}

/// A name dictionary (FUN_1004a110): the file is 8 u32 (offset and size of four sections, offsets from 0x20) and the
/// sections. Section 0, unpacked with key (0, 0), is the exact-name table (FUN_10049db0): 0x400 u32 buckets (offset
/// of an entry, −1 none), an entry being the offset of its name and of the next entry (−1 none). Sections 1..3 are
/// word engines.
pub struct NameDic {
    exact: Vec<u8>,
    engines: [Engine; 3],
}

impl NameDic {
    /// None when the sizes do not add up to the file's or a section does not unpack.
    pub fn parse(file: &[u8]) -> Option<Self> {
        if file.len() < 0x20 {
            return None;
        }
        let h: [usize; 8] = std::array::from_fn(|i| u32_at(file, i * 4) as usize);
        if h[1].checked_add(h[3])?.checked_add(h[5])?.checked_add(h[7])?.checked_add(0x20)? != file.len() {
            return None;
        }
        let section = |i: usize| file.get(0x20 + h[i * 2]..)?.get(..h[i * 2 + 1]);
        let exact = unpack([0, 0], section(0)?)?;
        if exact.len() < 0x1000 {
            return None;
        }
        let engines = [Engine::unpack(section(1)?)?, Engine::unpack(section(2)?)?, Engine::unpack(section(3)?)?];
        Some(Self { exact, engines })
    }

    /// FUN_10049e40: the name, skipped characters and letter case aside, is one of the table's.
    fn exact(&self, name: &[u8]) -> bool {
        if name.is_empty() {
            return false;
        }
        let mut entry = u32_at(&self.exact, exact_bucket(name) * 4);
        // A chain cannot be longer than the table holds entries (a damaged one could loop).
        for _ in 0..self.exact.len() / 8 {
            if entry == u32::MAX {
                break;
            }
            let word = u32_at(&self.exact, entry as usize) as usize;
            let (mut w, mut n) = (0usize, 0usize);
            while n < name.len() {
                let c = name[n];
                if !exact_skip(c) {
                    let e = at(&self.exact, word + w);
                    if e == 0 {
                        break;
                    }
                    w += 1;
                    if exact_lower(c) != e as i32 {
                        break;
                    }
                }
                n += 1;
            }
            if at(&self.exact, word + w) == 0 && n == name.len() {
                return true;
            }
            entry = u32_at(&self.exact, entry as usize + 4);
        }
        false
    }

    /// FUN_1004a200: the name is refused. In retail's order: a word of engine 1 anywhere, the exact names, a word of
    /// engine 2 at the start, a word of engine 3 at the end.
    pub fn refuses(&self, name: &[u8]) -> bool {
        self.engines[0].matches(name, Place::Anywhere)
            || self.exact(name)
            || self.engines[1].matches(name, Place::Start)
            || self.engines[2].matches(name, Place::End)
    }
}

/// FFXiMain's name filter object (DAT_10662db8) once loaded (FUN_101ba220 → FUN_101ba480).
pub enum NameFilter {
    /// The dictionary is loaded.
    Loaded(Box<NameDic>),
    /// There is a dictionary file and it does not load (retail: the load fails).
    Damaged,
    /// There is no dictionary file. Retail cannot be in this state with a working PlayOnline; an install made before
    /// the installer copied the dictionary can.
    Absent,
}

impl NameFilter {
    /// The name dictionary of a game folder (the one that holds "FINAL FANTASY XI").
    pub fn load(game_dir: &Path) -> Self {
        let path = name_dic_path(game_dir);
        match std::fs::read(&path) {
            Ok(file) => match NameDic::parse(&file) {
                Some(dic) => Self::Loaded(Box::new(dic)),
                None => {
                    log::warn!("{} is not a name dictionary", path.display());
                    Self::Damaged
                }
            },
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                log::warn!(
                    "no name dictionary at {}: names are not checked here (`vana-client dictionary` copies it from the installer)",
                    path.display()
                );
                Self::Absent
            }
            Err(e) => {
                log::warn!("reading {}: {e}", path.display());
                Self::Damaged
            }
        }
    }

    /// FUN_101ba240 (→ FUN_101ba520): 0 allowed, 1 refused, −1 no dictionary loaded.
    pub fn test(&self, name: &[u8]) -> i32 {
        match self {
            Self::Loaded(dic) => dic.refuses(name) as i32,
            Self::Damaged | Self::Absent => -1,
        }
    }

    /// The character creator's use (FUN_10239720 at 0x1023a2f5, FUN_10238330 at 0x10238420): anything but 0 refuses,
    /// so a dictionary that does not load refuses every name. Deviation: with no dictionary file at all the name is
    /// let through and the server's own check decides.
    pub fn creator_refuses(&self, name: &[u8]) -> bool {
        !matches!(self, Self::Absent) && self.test(name) != 0
    }

    /// An event's use (FUN_10094160, op 0x71 sub 3): a failed load allows the name, a loaded dictionary decides.
    pub fn event_refuses(&self, name: &[u8]) -> bool {
        self.test(name) == 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A section packed the way `unpack` undoes it: the payload padded to 8 bytes, then the result word (the payload
    /// length) and the sum.
    fn pack(key: [u32; 2], payload: &[u8]) -> Vec<u8> {
        let mut plain = payload.to_vec();
        plain.resize(payload.len().next_multiple_of(8), 0);
        let sum =
            plain.as_chunks::<8>().0.iter().fold(0u32, |s, b| s.wrapping_add(b[0] as u32).wrapping_add(b[4] as u32));
        plain.extend((plain.len() as u32).to_le_bytes());
        plain.extend(sum.to_le_bytes());
        let keys = round_keys(key);
        let mut out = Vec::with_capacity(plain.len());
        for (n, block) in plain.as_chunks::<8>().0.iter().enumerate() {
            let pos = (n as u32) * 8;
            let key = keys[n & 0x1f];
            let v = u64::from_le_bytes(*block);
            let mixed = ((v.rotate_right(32) ^ key ^ position_word(pos)).wrapping_add(key)).to_le_bytes();
            let mut prev = (pos >> 3) as u8 ^ 0x45;
            for mut b in mixed {
                for k in key.to_le_bytes().into_iter().rev() {
                    b = b.wrapping_sub(0x78).wrapping_add(k);
                }
                prev ^= b;
                out.push(prev);
            }
        }
        out
    }

    fn put16(d: &mut [u8], o: usize, v: u16) {
        d[o..o + 2].copy_from_slice(&v.to_le_bytes());
    }

    fn put32(d: &mut [u8], o: usize, v: u32) {
        d[o..o + 4].copy_from_slice(&v.to_le_bytes());
    }

    /// The two-byte character the test engines know: first byte 0x82 (class 1), second 0xa0 (class 1).
    const WIDE: [u8; 2] = [0x82, 0xa0];

    /// A tree over `words` (lower case; each at least two characters, single-byte first; words sharing a first
    /// character differ at the second): the first character picks a branch node keyed by the second, and the rest
    /// is a run node.
    fn tree(words: &[&[u8]]) -> Vec<u8> {
        let (mut children, mut keys, mut strings, mut nodes) =
            (vec![0u16], Vec::<u16>::new(), vec![0u8], vec![[0u8; 8]]);
        let mut t = vec![0u8; 0x48f4];
        let mut firsts: Vec<u8> = words.iter().map(|w| w[0]).collect();
        firsts.sort();
        firsts.dedup();
        for f in firsts {
            // (second character's code, the rest), sorted by code as the key search needs.
            let mut group: Vec<(u16, &[u8])> = words
                .iter()
                .filter(|w| w[0] == f)
                .map(|w| {
                    if w[1..].starts_with(&WIDE) { (u16::from_le_bytes(WIDE), &w[3..]) } else { (w[1] as u16, &w[2..]) }
                })
                .collect();
            group.sort();
            let branch = nodes.len();
            put16(&mut t, 0x46f4 + f as usize * 2, branch as u16);
            let mut node = [1, group.len() as u8, 0, 0, 0, 0, 0, 0];
            node[2..4].copy_from_slice(&(children.len() as u16).to_le_bytes());
            node[4..8].copy_from_slice(&(keys.len() as u32).to_le_bytes());
            nodes.push(node);
            let base = children.len();
            children.resize(base + group.len(), 0);
            for (i, (code, rest)) in group.into_iter().enumerate() {
                keys.push(code.wrapping_neg());
                if !rest.is_empty() {
                    children[base + i] = nodes.len() as u16;
                    let mut run = [2, 0, 0, 0, 0, 0, 0, 0];
                    run[4..8].copy_from_slice(&(strings.len() as u32).to_le_bytes());
                    nodes.push(run);
                    strings.extend(rest.iter().map(|c| c.wrapping_neg()));
                    strings.push(0);
                }
            }
        }
        for slot in 0..4 {
            let at = (t.len() - 0x48f4) as u32;
            put32(&mut t, slot * 4, at);
            match slot {
                0 => t.extend(children.iter().flat_map(|v| v.to_le_bytes())),
                1 => t.extend(keys.iter().flat_map(|v| v.to_le_bytes())),
                2 => t.extend(&strings),
                _ => t.extend(nodes.iter().flatten()),
            }
        }
        t
    }

    /// An engine's packed section: space and '-' skipped, A..Z folded to a..z, one two-byte character, the words
    /// and the allowed words.
    fn engine(words: &[&[u8]], allowed: &[&[u8]]) -> Vec<u8> {
        pack([1, 0], &engine_data(tree(words), tree(allowed)))
    }

    /// An engine's unpacked bytes around two trees.
    fn engine_data(words: Vec<u8>, allowed: Vec<u8>) -> Vec<u8> {
        let mut d = vec![0u8; 0x4a38];
        for c in *b" -" {
            d[0x10 + (c >> 3) as usize] |= 1 << (c & 7);
        }
        d[0x50 + WIDE[0] as usize] = 1;
        d[0x150 + WIDE[1] as usize] = 1;
        for c in 0..=255u8 {
            d[0x4930 + c as usize] = c.to_ascii_lowercase();
        }
        for (slot, t) in [(0x4a30, words), (0x4a34, allowed)] {
            let at = d.len() as u32;
            put32(&mut d, slot, at);
            d.extend(t);
        }
        d
    }

    /// A name dictionary file from exact names and the three engines' sections.
    fn dictionary(exact: &[&[u8]], engines: [Vec<u8>; 3]) -> Vec<u8> {
        let mut table = vec![0xffu8; 0x1000];
        for name in exact {
            let (bucket, entry) = (exact_bucket(name) * 4, table.len());
            let next = u32_at(&table, bucket);
            put32(&mut table, bucket, entry as u32);
            table.extend((entry as u32 + 8).to_le_bytes());
            table.extend(next.to_le_bytes());
            table.extend(*name);
            table.push(0);
            table.resize(table.len().next_multiple_of(4), 0);
        }
        let sections = [pack([0, 0], &table), engines[0].clone(), engines[1].clone(), engines[2].clone()];
        let (mut file, mut at) = (Vec::new(), 0u32);
        for s in &sections {
            file.extend(at.to_le_bytes());
            file.extend((s.len() as u32).to_le_bytes());
            at += s.len() as u32;
        }
        file.extend(sections.concat());
        file
    }

    fn sample() -> Vec<u8> {
        dictionary(
            &[b"mod", b"gamemaster"],
            [
                engine(&[b"bad", b"bog", b"worse", b"x\x82\xa0y"], &[b"badge"]),
                engine(&[b"gm"], &[]),
                engine(&[b"staff"], &[]),
            ],
        )
    }

    #[test]
    fn sections_unpack() {
        let payload: Vec<u8> = (0..1000u32).map(|i| (i * 7 + 3) as u8).collect();
        for key in [[0, 0], [1, 0], [0x1234_5678, 0x9abc_def0]] {
            let packed = pack(key, &payload);
            let plain = unpack(key, &packed).expect("unpacks");
            assert_eq!(&plain[..1000], &payload[..]);
            assert_eq!(u32_at(&plain, plain.len() - 8), 1000);
            // The wrong key, a changed byte the sum covers (bytes 0 and 4 of a block) and a size off the 8-byte grid
            // all fail.
            assert!(unpack([key[0] ^ 1, key[1]], &packed).is_none());
            let mut changed = packed.clone();
            changed[16] ^= 0x40;
            assert!(unpack(key, &changed).is_none());
            assert!(unpack(key, &packed[..packed.len() - 1]).is_none());
        }
        assert!(unpack([0, 0], &[]).is_none());
    }

    #[test]
    fn engine_places() {
        let e = Engine::unpack(&engine(&[b"bad", b"bog", b"worse", b"x\x82\xa0y"], &[b"badge"])).unwrap();
        let any = |t: &[u8]| e.matches(t, Place::Anywhere);
        assert!(any(b"bad") && any(b"Bad") && any(b"xxBADxx") && any(b"abogus") && any(b"worse"));
        // Skipped characters inside a word and around it do not hide it.
        assert!(any(b"b-a d") && any(b" -worse- "));
        assert!(!any(b"ba") && !any(b"bud") && !any(b"wors") && !any(b"") && !any(b" - "));
        // A word of the allowed tree is stepped over whole, the word inside it too.
        assert!(!any(b"badge") && !any(b"Badges") && any(b"badgebad"));
        // The two-byte character matches as one unit, not by its bytes.
        assert!(any(b"x\x82\xa0y") && !any(b"x\x82y") && !any(b"x\xa0y"));
        // Start: only skipped characters before the word. End: only skipped ones after it.
        assert!(e.matches(b"bad", Place::Start) && e.matches(b" -Badness", Place::Start));
        assert!(!e.matches(b"abad", Place::Start));
        assert!(e.matches(b"bad", Place::End) && e.matches(b"toobad- ", Place::End));
        assert!(!e.matches(b"badly", Place::End));
        // Like retail, both answer at the first word found: a later one in the right place does not count.
        assert!(!e.matches(b"xbog bad", Place::End) && e.matches(b"bog-xbad", Place::Start));
    }

    /// A damaged tree whose empty run leads back to itself: the walk gives up instead of looping.
    #[test]
    fn empty_run_cycle_ends() {
        let mut t = vec![0u8; 0x48f4];
        // 'a' starts at node 1, a run of no characters whose child is node 1 again.
        put16(&mut t, 0x46f4 + b'a' as usize * 2, 1);
        let children: Vec<u8> = [0u16, 1].iter().flat_map(|v| v.to_le_bytes()).collect();
        let nodes = [[0u8; 8], [2, 0, 1, 0, 0, 0, 0, 0]].concat();
        for (slot, table) in [children, Vec::new(), vec![0], nodes].iter().enumerate() {
            let at = (t.len() - 0x48f4) as u32;
            put32(&mut t, slot * 4, at);
            t.extend(table);
        }
        let e = Engine { data: engine_data(t, tree(&[])) };
        assert!(!e.matches(b"abc", Place::Anywhere));
    }

    /// A branch with no keys still compares key 0, as polcore does.
    #[test]
    fn branch_without_keys() {
        let mut data = vec![0u8; 0x4a38];
        put16(&mut data, 0x100, (b'x' as u16).wrapping_neg());
        let e = Engine { data };
        assert_eq!(e.key_index(b'x' as u16, 0x100, 0), Some(0));
        assert_eq!(e.key_index(b'y' as u16, 0x100, 0), None);
    }

    #[test]
    fn name_dictionary() {
        let file = sample();
        let dic = NameDic::parse(&file).expect("parses");
        // The exact names: letter case and skipped characters aside, the whole name.
        assert!(dic.refuses(b"Mod") && dic.refuses(b"m.o.d") && dic.refuses(b"GameMaster"));
        assert!(!dic.refuses(b"Modest") && !dic.refuses(b"Amod") && !dic.refuses(b"mo"));
        // Engine 1 anywhere, engine 2 at the start, engine 3 at the end.
        assert!(dic.refuses(b"Toobadly"));
        assert!(dic.refuses(b"Gmfriend") && !dic.refuses(b"Pigment"));
        assert!(dic.refuses(b"Thestaff") && !dic.refuses(b"Staffer"));
        assert!(!dic.refuses(b"Shantotto") && !dic.refuses(b"Badge"));

        // A file whose sizes do not add up, or with a damaged section, is no dictionary.
        assert!(NameDic::parse(&file[..file.len() - 8]).is_none());
        let mut damaged = file.clone();
        let n = damaged.len();
        damaged[n - 104] ^= 1;
        assert!(NameDic::parse(&damaged).is_none());
        assert!(NameDic::parse(&[0; 0x20]).is_none());
    }

    /// The three states of the filter: the creator refuses on a refused word and on a dictionary that does not load;
    /// an event only on a refused word; with no file at all both let the name through.
    #[test]
    fn filter_states() {
        let base = std::env::temp_dir().join(format!("vana-poldic-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let absent = NameFilter::load(&base);
        assert!(matches!(absent, NameFilter::Absent) && absent.test(b"Bad") == -1);
        assert!(!absent.creator_refuses(b"Bad") && !absent.event_refuses(b"Bad"));

        let path = name_dic_path(&base);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, b"not a dictionary").unwrap();
        let damaged = NameFilter::load(&base);
        assert!(matches!(damaged, NameFilter::Damaged) && damaged.test(b"Shantotto") == -1);
        assert!(damaged.creator_refuses(b"Shantotto") && !damaged.event_refuses(b"Shantotto"));

        std::fs::write(&path, sample()).unwrap();
        let loaded = NameFilter::load(&base);
        assert_eq!((loaded.test(b"Shantotto"), loaded.test(b"Toobad")), (0, 1));
        assert!(loaded.creator_refuses(b"Toobad") && loaded.event_refuses(b"Toobad"));
        assert!(!loaded.creator_refuses(b"Shantotto") && !loaded.event_refuses(b"Shantotto"));
        let _ = std::fs::remove_dir_all(&base);
    }

    /// The player's own dictionary, when the install has it: it loads, lets an ordinary name through and refuses the
    /// staff prefix at the start, at the end and alone.
    #[test]
    fn installed_dictionary() {
        let cfg = crate::config::Config::load();
        if !name_dic_path(&cfg.game_dir).is_file() {
            return;
        }
        let filter = NameFilter::load(&cfg.game_dir);
        assert!(matches!(filter, NameFilter::Loaded(_)));
        assert_eq!(filter.test(b"Shantotto"), 0);
        assert_eq!((filter.test(b"Gm"), filter.test(b"Gmshantotto"), filter.test(b"Shantottogm")), (1, 1, 1));
    }
}
