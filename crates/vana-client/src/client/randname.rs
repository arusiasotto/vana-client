//! The character creator's random names (Num+ on the name step): FFXiMain win_chmkname's message 0xc (FUN_10239b10)
//! and its generator FUN_10239cc0, one per race. Addresses are 30261102_0.
//!
//! Hume names are records of the name lists in files 0x7c00..0x7c05, a Galka's is an adjective (0x7c06) and a noun
//! (0x7c07), and the other races are built from syllable tables that sit in FFXiMain.dll's data. All of it is read
//! from the player's install ([`Tables`]); none of it is in this repository.

use std::path::Path;

/// The CRT's rand(), 0..=32767.
pub type Rand<'a> = &'a mut dyn FnMut() -> u32;
/// A 16-byte record of a name list: (file id, record number) to its text.
pub type Read<'a> = &'a mut dyn FnMut(u32, u32) -> Option<Vec<u8>>;

/// The Galka noun weights by length class (0x103884c0). Also what finds the tables in the DLL: everything else is at a
/// fixed place around it.
pub const NOUN_WEIGHT: [u32; 11] = [2, 56, 149, 171, 173, 169, 127, 81, 34, 17, 2];

/// The generator's tables, 0x10387b28..0x10388aa0 of FFXiMain.dll.
pub struct Tables {
    /// Elvaan women: 22 rows of 6 syllable columns (0x10387b28) and each column's row count (0x10387d38).
    elvaan_f: Vec<Vec<u8>>,
    elvaan_f_rows: [u32; 6],
    /// Elvaan men: 67 rows of 7 columns (0x10387d50), counts 0x103884a4.
    elvaan_m: Vec<Vec<u8>>,
    elvaan_m_rows: [u32; 7],
    /// Galka adjectives by length class: how many and the first record (0x103884ec / 0x10388518).
    adjective_count: [u32; 11],
    adjective_first: [u32; 11],
    /// Records in the six Hume lists (0x10388544).
    hume_records: [u32; 6],
    /// 32 rows of 5 syllables, consonant by vowel (0x10388560), and their weights (0x103887e0).
    kana: Vec<Vec<u8>>,
    weight: [[u32; 5]; 32],
    /// Weights of the 16 ways a Tarutaru man's long name doubles its consonants (0x10388a60).
    double_weight: [u32; 16],
}

impl Tables {
    /// The FFXiMain.dll the client reads (`dat::ffximain`). The file on disk has its code packed and its data in the
    /// clear.
    pub fn load(ffxi_dir: &Path) -> Option<Tables> {
        let path = crate::dat::ffximain(ffxi_dir);
        let dll = match std::fs::read(&path) {
            Ok(d) => d,
            Err(e) => {
                log::warn!("random names: {}: {e}", path.display());
                return None;
            }
        };
        let t = Tables::parse(&dll);
        if t.is_none() {
            log::warn!("random names: the name tables were not found in {}", path.display());
        }
        t
    }

    pub fn parse(dll: &[u8]) -> Option<Tables> {
        let u32_at = |o: usize| Some(u32::from_le_bytes(dll.get(o..o + 4)?.try_into().ok()?));
        let u16_at = |o: usize| Some(u16::from_le_bytes(dll.get(o..o + 2)?.try_into().ok()?));
        // The PE sections, to turn the tables' pointers into file offsets.
        let pe = u32_at(0x3c)? as usize;
        if dll.get(pe..pe + 4)? != b"PE\0\0" {
            return None;
        }
        let (count, optional) = (u16_at(pe + 6)? as usize, u16_at(pe + 20)? as usize);
        let base = u32_at(pe + 24 + 28)?;
        let mut sections = Vec::new();
        for i in 0..count {
            let s = pe + 24 + optional + i * 40;
            sections.push((u32_at(s + 12)?, u32_at(s + 16)?, u32_at(s + 20)?));
        }
        let text = |va: u32| -> Option<Vec<u8>> {
            let rva = va.checked_sub(base)?;
            let &(start, size, raw) = sections.iter().find(|s| rva >= s.0 && rva - s.0 < s.1)?;
            let from = (raw + (rva - start)) as usize;
            let end = ((raw + size) as usize).min(dll.len());
            let s = dll.get(from..end)?;
            let s = &s[..s.iter().position(|&c| c == 0)?];
            (s.len() <= 5 && s.iter().all(u8::is_ascii_lowercase)).then(|| s.to_vec())
        };
        let anchor: Vec<u8> = NOUN_WEIGHT.iter().flat_map(|w| w.to_le_bytes()).collect();
        let mut found = dll.windows(anchor.len()).enumerate().filter(|(_, w)| *w == &anchor[..]).map(|(i, _)| i);
        let (a, None) = (found.next()?, found.next()) else { return None };
        let ints = |o: usize, n: usize| (0..n).map(|i| u32_at(o + i * 4)).collect::<Option<Vec<u32>>>();
        let texts = |o: usize, n: usize| (0..n).map(|i| text(u32_at(o + i * 4)?)).collect::<Option<Vec<_>>>();
        let weight: Vec<u32> = ints(a + 0x320, 160)?;
        let t = Tables {
            elvaan_f: texts(a.checked_sub(0x998)?, 22 * 6)?,
            elvaan_f_rows: ints(a - 0x788, 6)?.try_into().ok()?,
            elvaan_m: texts(a - 0x770, 67 * 7)?,
            elvaan_m_rows: ints(a - 0x1c, 7)?.try_into().ok()?,
            adjective_count: ints(a + 0x2c, 11)?.try_into().ok()?,
            adjective_first: ints(a + 0x58, 11)?.try_into().ok()?,
            hume_records: ints(a + 0x84, 6)?.try_into().ok()?,
            kana: texts(a + 0xa0, 160)?,
            weight: std::array::from_fn(|r| std::array::from_fn(|c| weight[r * 5 + c])),
            double_weight: ints(a + 0x5a0, 16)?.try_into().ok()?,
        };
        // What the generator divides by and indexes with.
        let sane = t.elvaan_f_rows.iter().all(|&n| (1..=22).contains(&n))
            && t.elvaan_m_rows.iter().all(|&n| (1..=67).contains(&n))
            && t.adjective_count.iter().all(|&n| n > 0 && n < 0x10000)
            && t.adjective_first.iter().all(|&n| n < 0x10000)
            && t.hume_records.iter().all(|&n| n > 0)
            && t.weight.iter().flatten().all(|&w| (1..0x1000).contains(&w))
            && t.kana.iter().all(|k| !k.is_empty())
            && t.double_weight.iter().sum::<u32>() == 1000
            && t.double_weight[15] < 1000;
        sane.then_some(t)
    }

    /// The Hume list's record count.
    pub fn hume_records(&self, list: usize) -> u32 {
        self.hume_records[list]
    }

    fn kana(&self, row: usize, col: usize) -> &[u8] {
        &self.kana[row * 5 + col]
    }
}

fn vowel(c: Option<&u8>) -> bool {
    matches!(c, Some(b'a' | b'e' | b'i' | b'o' | b'u'))
}

/// `_strncat(to, from, 1)`.
fn first(to: &mut Vec<u8>, from: &[u8]) {
    to.extend(from.iter().take(1));
}

/// The syllable weights summed (FUN_102377c0): all of them, each row's, each column's.
struct Sums {
    all: u32,
    row: [u32; 32],
    col: [u32; 5],
}

impl Sums {
    fn new(t: &Tables) -> Sums {
        let mut s = Sums { all: 0, row: [0; 32], col: [0; 5] };
        for (r, row) in t.weight.iter().enumerate() {
            for (c, &w) in row.iter().enumerate() {
                s.all += w;
                s.row[r] += w;
                s.col[c] += w;
            }
        }
        s
    }
}

/// The closing letter the two rolls of FUN_10237830 / FUN_10237af0 / FUN_10238960 give: 4 'n', 1 'p', 2 'm', 3 't',
/// and 5 'l' (FUN_10237af0's second half only).
fn closing(kind: u8) -> Option<u8> {
    match kind {
        4 => Some(b'n'),
        1 => Some(b'p'),
        2 => Some(b'm'),
        3 => Some(b't'),
        5 => Some(b'l'),
        _ => None,
    }
}

fn closing_roll(r: u32) -> u8 {
    match r {
        0..=8 => 4,
        11 => 1,
        12 => 2,
        13 => 3,
        _ => 0,
    }
}

/// A weighted cell of the syllable table; `late` (mode 2) leaves the bare vowels of row 0 out. The comparison is
/// `<=`, as retail's.
fn cell(t: &Tables, s: &Sums, late: bool, rand: Rand) -> (usize, usize) {
    let r = if late { rand() % (s.all - s.row[0]) } else { rand() % s.all };
    let mut acc = 0;
    for row in late as usize..32 {
        for col in 0..5 {
            acc += t.weight[row][col];
            if r <= acc {
                return (row, col);
            }
        }
    }
    (31, 4)
}

/// FUN_10237830: one syllable, sometimes with an 'h' or its vowel again, sometimes closed.
fn syllable(t: &Tables, s: &Sums, late: bool, rand: Rand) -> Vec<u8> {
    let (row, col) = cell(t, s, late, rand);
    let mut out = t.kana(row, col).to_vec();
    match rand() % 100 {
        0..=3 => out.push(b'h'),
        4..=7 => out.extend(t.kana(0, col)),
        _ => {}
    }
    out.extend(closing(closing_roll(rand() % 100)));
    out
}

/// FUN_10238960: a Mithra's syllable, every cell as likely as another.
fn plain_syllable(t: &Tables, rand: Rand) -> Vec<u8> {
    let row = (rand() & 0x1f) as usize;
    let col = (rand() % 5) as usize;
    let mut out = t.kana(row, col).to_vec();
    match rand() % 100 {
        0..=7 => out.push(b'h'),
        8..=15 => out.extend(t.kana(0, col)),
        _ => {}
    }
    out.extend(closing(closing_roll(rand() % 100)));
    out
}

/// FUN_10237af0 (mode 0): two syllables that rhyme, the second from the first's vowel column.
fn pair(t: &Tables, s: &Sums, rand: Rand) -> (Vec<u8>, Vec<u8>) {
    let (row1, col1) = cell(t, s, false, rand);
    let mut a = t.kana(row1, col1).to_vec();
    // 2: an 'h' after it; 1: its vowel again.
    let mut longer1 = 0;
    match rand() % 100 {
        0..=3 => {
            a.push(b'h');
            longer1 = 2;
        }
        4..=7 => {
            a.extend(t.kana(0, col1));
            longer1 = 1;
        }
        _ => {}
    }
    let close1 = closing_roll(rand() % 100);
    a.extend(closing(close1));

    let r = rand() % s.col[col1];
    let mut acc = 0;
    let mut row2 = 0;
    while row2 < 32 {
        acc += t.weight[row2][col1];
        if r <= acc {
            break;
        }
        row2 += 1;
    }
    let row2 = row2.min(31);
    let mut col2 = col1;
    if row2 == row1 {
        let r = rand() % s.row[row2];
        let mut acc = 0;
        col2 = 0;
        while col2 < 5 {
            acc += t.weight[row2][col2];
            if r <= acc {
                break;
            }
            col2 += 1;
        }
        col2 = col2.min(4);
    }
    let same = row1 == row2 && col1 == col2;
    let r = rand() % 100;
    let mut longer2 = 0;
    if longer1 == 0 {
        let (h, twice) = if same { (45, 90) } else { (5, 10) };
        if r < h {
            longer2 = 2;
        } else if r < twice {
            longer2 = 1;
        }
    } else {
        let at = if same { 10 } else { 90 };
        if r < at {
            // Retail clears the first half's kind here; only the comparisons below read it again.
            longer1 = 0;
        } else if r == at {
            longer2 = if longer1 == 2 { 1 } else { 2 };
        }
    }
    let mut close2;
    if close1 == 0 {
        let of = if !same {
            100
        } else if longer1 == longer2 {
            12
        } else {
            50
        };
        close2 = match rand() % of {
            0..=8 => 4,
            9 => 1,
            10 => 2,
            11 => 3,
            _ => 0,
        };
    } else {
        let (from, r) = if same && longer1 == longer2 {
            let r = rand();
            (0, if close1 != 4 { r % 22 } else { r % 6 + 9 })
        } else {
            (40, rand() % 100)
        };
        close2 = close1;
        if r >= from {
            close2 = match r - from {
                0..=8 => 4,
                9 => 1,
                10 => 2,
                11 => 3,
                _ => 0,
            };
        }
    }
    if same && longer1 == longer2 && close1 == close2 {
        close2 = 5;
    }
    let mut b = t.kana(row2, col2).to_vec();
    if longer2 == 2 {
        b.push(b'h');
    } else if longer2 == 1 {
        let r = rand();
        b.extend(t.kana(0, if close1 == close2 && r.is_multiple_of(10) { col1 } else { col2 }));
    }
    b.extend(closing(close2));
    (a, b)
}

/// FUN_10238070.
fn taru_m_a(t: &Tables, s: &Sums, rand: Rand) -> Vec<u8> {
    let (a, mut b) = pair(t, s, rand);
    let c = syllable(t, s, false, rand);
    let mut r = rand() % 100;
    if r < 50 {
        b = syllable(t, s, false, rand);
    } else {
        r -= 50;
    }
    if vowel(c.first()) {
        r = 49;
    }
    let mut out = a;
    if r < 7 {
        first(&mut out, &c);
    }
    out.extend(&c);
    out.extend(&b);
    if (3..10).contains(&r) {
        first(&mut out, &c);
    }
    out.extend(&c);
    out
}

/// FUN_102381b0.
fn taru_m_b(t: &Tables, s: &Sums, rand: Rand) -> Vec<u8> {
    let (a, mut b) = pair(t, s, rand);
    let c = syllable(t, s, false, rand);
    let d;
    match rand() % 80 {
        0..=25 => {
            b = syllable(t, s, false, rand);
            d = syllable(t, s, false, rand);
        }
        26..=43 => {
            b = a.clone();
            d = syllable(t, s, false, rand);
        }
        44..=61 => d = syllable(t, s, false, rand),
        _ => {
            d = b;
            b = syllable(t, s, false, rand);
        }
    }
    let q = if vowel(c.first()) { 99 } else { rand() % 100 };
    let mut out = a;
    if q < 6 || (14..20).contains(&q) {
        first(&mut out, &c);
    }
    out.extend(&c);
    out.extend(&b);
    if (6..10).contains(&q) || (14..17).contains(&q) {
        first(&mut out, &d);
    }
    out.extend(&d);
    if (10..14).contains(&q) || (17..20).contains(&q) {
        first(&mut out, &c);
    }
    out.extend(&c);
    out
}

/// FUN_102383b0.
fn taru_m_c(t: &Tables, s: &Sums, rand: Rand) -> Vec<u8> {
    let (a, mut b) = pair(t, s, rand);
    let c = syllable(t, s, false, rand);
    let d;
    match rand() % 84 {
        0..=19 => {
            b = syllable(t, s, false, rand);
            d = syllable(t, s, false, rand);
        }
        20..=35 => {
            b = syllable(t, s, false, rand);
            d = a.clone();
        }
        36..=51 => {
            b = syllable(t, s, false, rand);
            d = b.clone();
        }
        52..=67 => {
            d = b;
            b = syllable(t, s, false, rand);
        }
        _ => (b, d) = pair(t, s, rand),
    }
    let q = if vowel(c.first()) { 99 } else { rand() % 100 };
    let mut out = a;
    if q < 3 || (9..13).contains(&q) {
        first(&mut out, &b);
    }
    out.extend(&b);
    if (3..6).contains(&q) || (9..11).contains(&q) {
        first(&mut out, &c);
    }
    out.extend(&c);
    out.extend(&d);
    if (6..9).contains(&q) || (11..13).contains(&q) {
        first(&mut out, &c);
    }
    out.extend(&c);
    out
}

/// FUN_102385f0.
fn taru_m_d(t: &Tables, s: &Sums, rand: Rand) -> Vec<u8> {
    let (a, mut b) = pair(t, s, rand);
    let (d, mut e) = pair(t, s, rand);
    let c = syllable(t, s, false, rand);
    match rand() % 100 {
        0..=49 => {
            b = syllable(t, s, false, rand);
            e = d.clone();
        }
        50..=59 => e = d.clone(),
        60..=69 => b = a.clone(),
        70..=79 => {}
        80..=84 => b = syllable(t, s, false, rand),
        _ => {
            b = syllable(t, s, false, rand);
            e = syllable(t, s, false, rand);
        }
    }
    let len = a.len() + b.len() + c.len() + d.len() + e.len();
    // Bits: 8 doubles d's first letter, 4 c's (first time), 2 e's, 1 c's (second time).
    let mut double = 0u32;
    if len < 15 {
        let r = rand() % if len > 11 { 1000 - t.double_weight[15] } else { 1000 };
        let mut acc = 0;
        while double < 16 {
            acc += t.double_weight[double as usize];
            if r < acc {
                break;
            }
            double += 1;
        }
        if len > 12 && matches!(double, 7 | 11 | 13 | 14) {
            double = match rand() % 6 {
                0 => 5,
                5 => 10,
                r => r * 3,
            };
        }
        if len > 13 && matches!(double, 3 | 5 | 6 | 9 | 10 | 12) {
            double = 1 << (rand() & 3);
        }
        if double & 5 != 0 && vowel(c.first()) {
            double &= !5;
        }
        if double & 8 != 0 && vowel(d.first()) {
            double &= !8;
        }
        if double & 2 != 0 && vowel(e.first()) {
            double &= !2;
        }
    }
    let mut out = a;
    if double & 8 != 0 {
        first(&mut out, &d);
    }
    out.extend(&d);
    if double & 4 != 0 {
        first(&mut out, &c);
    }
    out.extend(&c);
    out.extend(&b);
    if double & 2 != 0 {
        first(&mut out, &e);
    }
    out.extend(&e);
    if double & 1 != 0 {
        first(&mut out, &c);
    }
    out.extend(&c);
    out
}

/// FUN_102379a0: a Tarutaru man. A name over 15 letters is made again the third way, then as a bare pair
/// (FUN_10237a60).
fn taru_m(t: &Tables, rand: Rand) -> Vec<u8> {
    let s = Sums::new(t);
    let mut out = match rand() % 100 {
        0..=39 => taru_m_a(t, &s, rand),
        40..=54 => taru_m_b(t, &s, rand),
        55..=57 => taru_m_c(t, &s, rand),
        _ => taru_m_d(t, &s, rand),
    };
    if out.len() > 15 {
        out = taru_m_c(t, &s, rand);
        if out.len() > 15 {
            let (a, mut b) = pair(t, &s, rand);
            if rand() % 100 < 10 {
                b = syllable(t, &s, false, rand);
            }
            out = a;
            out.extend(b);
        }
    }
    out.truncate(15);
    out
}

/// FUN_10237410: a Tarutaru woman, the last syllable said twice.
fn taru_f(t: &Tables, rand: Rand) -> Vec<u8> {
    let s = Sums::new(t);
    let r = rand() % 100;
    let mut out = syllable(t, &s, false, rand);
    let middle = matches!(r, 40..=79 | 85..=94 | 98..);
    if middle {
        let y = syllable(t, &s, false, rand);
        if (85..90).contains(&r) {
            first(&mut out, &y);
        }
        out.extend(y);
    }
    let z = syllable(t, &s, true, rand);
    match r {
        80..=84 | 90..=94 => {
            first(&mut out, &z);
            out.extend(&z);
            out.extend(&z);
        }
        95.. => {
            out.extend(&z);
            first(&mut out, &z);
            out.extend(&z);
        }
        _ => {
            out.extend(&z);
            out.extend(&z);
        }
    }
    out.truncate(15);
    out
}

/// FUN_102365d0 / FUN_10236310: an Elvaan, one syllable from each column of a pattern.
fn elvaan(table: &[Vec<u8>], rows: &[u32], pattern: &[usize], rand: Rand) -> Vec<u8> {
    let mut out = Vec::new();
    for &col in pattern {
        let row = (rand() % rows[col]) as usize;
        out.extend(&table[row * rows.len() + col]);
    }
    out.truncate(15);
    out
}

fn elvaan_m(t: &Tables, rand: Rand) -> Vec<u8> {
    let pattern: &[usize] = match rand() % 102 {
        0..=6 => &[1, 3, 5],
        7..=13 => &[1, 4, 6],
        14..=20 => &[2, 3, 5],
        21..=27 => &[2, 4, 6],
        28..=34 => &[3, 0, 5],
        35..=41 => &[0, 1, 6],
        42..=61 => &[0, 1, 3, 5],
        62..=81 => &[0, 2, 3, 5],
        _ => &[0, 2, 4, 6],
    };
    elvaan(&t.elvaan_m, &t.elvaan_m_rows, pattern, rand)
}

fn elvaan_f(t: &Tables, rand: Rand) -> Vec<u8> {
    let pattern: &[usize] = match rand() % 100 {
        0..=9 => &[0, 1, 3],
        10..=19 => &[0, 1, 5],
        20..=29 => &[0, 2, 4],
        30..=39 => &[0, 2, 5],
        40..=69 => &[0, 1, 2, 4],
        _ => &[0, 1, 2, 5],
    };
    elvaan(&t.elvaan_f, &t.elvaan_f_rows, pattern, rand)
}

/// FUN_10236c00: a syllable put before the text, into it or after it, the whole kept to 15 letters.
fn mithra_add(t: &Tables, s: &mut Vec<u8>, rand: Rand) {
    let syl = plain_syllable(t, rand);
    let mut out;
    match rand() % 10 {
        0..=2 => {
            out = syl.clone();
            out.extend(s.iter().take(15 - syl.len()));
        }
        3..=5 => {
            let at = (rand() % (s.len() as u32 + 1)) as usize;
            out = s[..at].to_vec();
            out.extend(syl.iter().take(15 - s.len()));
            out.extend(&s[at..]);
        }
        _ => {
            out = s.clone();
            out.extend(syl.iter().take(15 - s.len()));
        }
    }
    out.truncate(15);
    *s = out;
}

/// FUN_10236b20: the lower-case letters of the text (15 at most), then more syllables the shorter it is.
fn mithra_grow(t: &Tables, text: &[u8], rand: Rand) -> Vec<u8> {
    let mut s = Vec::new();
    for &c in text.iter().take(30) {
        if s.len() > 14 || c == 0 || c == b'\n' {
            break;
        }
        if c.is_ascii_lowercase() {
            s.push(c);
        }
    }
    let r = rand() % 100;
    let add = match s.len() {
        0..=1 => match r {
            0..=9 => 1,
            10..=69 => 2,
            _ => 3,
        },
        2..=3 => match r {
            0..=39 => 1,
            40..=79 => 2,
            80..=89 => 3,
            _ => 0,
        },
        4..=7 => match r {
            0..=39 => 1,
            40..=59 => 2,
            _ => 0,
        },
        8..=11 => (r < 30) as u32,
        _ => 0,
    };
    for _ in 0..add {
        mithra_add(t, &mut s, rand);
    }
    s
}

/// FUN_10236d40: vowels pushed into runs of consonants, then every letter given a chance to change.
fn mithra_mangle(s: &[u8], rand: Rand) -> Vec<u8> {
    let cons = |c: u8| !matches!(c, b'a' | b'e' | b'i' | b'o' | b'u');
    let at = |v: &[u8], i: usize| v.get(i).copied().unwrap_or(0);
    let n = s.len();
    let mut t: Vec<u8> = Vec::new();
    let mut i = 0;
    while i < n {
        if i + 2 < n && cons(s[i]) && cons(s[i + 1]) && cons(s[i + 2]) {
            let r = rand() % 100;
            if r < 20 {
                t.push(s[i]);
                i += 1;
                continue;
            }
            let v = match rand() % 110 {
                0..=19 => b'a',
                20..=39 => b'e',
                40..=59 => b'i',
                60..=79 => b'o',
                80..=99 => b'u',
                _ => b'y',
            };
            if r < 60 {
                t.extend([s[i], v, s[i + 1], s[i + 2]]);
            } else {
                t.extend([s[i], s[i + 1], v, s[i + 2]]);
            }
            i += 3;
        } else if i + 1 < n && cons(s[i]) && cons(s[i + 1]) {
            if rand() % 100 > 89 {
                let x = rand() % 120;
                let next = at(s, i + 2);
                let v = match x {
                    0..=19 => b'a',
                    20..=39 => b'e',
                    40..=59 => b'i',
                    60..=79 => b'o',
                    80..=99 => b'u',
                    _ if (i == 0 || s[i] != b'y') && next != b'y' && x < 110 => b'y',
                    _ if (i == 0 || s[i] != b'h') && next != b'h' => b'h',
                    _ if x & 1 == 0 => b'i',
                    _ => b'a',
                };
                t.extend([s[i], v, s[i + 1]]);
                i += 2;
            } else {
                t.push(s[i]);
                i += 1;
            }
        } else {
            t.push(s[i]);
            i += 1;
        }
    }

    let m = t.len();
    let mut out: Vec<u8> = Vec::new();
    for j in 0..m {
        let c = t[j];
        let next = at(&t, j + 1);
        let prev_is = |x: u8| j != 0 && t[j - 1] == x;
        let last = j + 1 == m && m > 3;
        let r = rand() % 100;
        match c {
            b'a' | b'i' => {
                // (twice, 'h' before, 'h' after, 'y' before, 'y' after), each up to its number.
                let (twice, h_before, h_after, y_before, y_after) =
                    if c == b'a' { (25, 35, 30, 35, 36) } else { (10, 20, 50, 50, 51) };
                // 'a': twice < 25, "ah" < 30, "ha" < 35; 'i': twice < 10, "hi" < 20, "ih" < 50.
                let kind = if r < twice {
                    0
                } else if c == b'a' {
                    if r < h_after {
                        2
                    } else if r < h_before {
                        1
                    } else {
                        3
                    }
                } else if r < h_before {
                    1
                } else if r < h_after {
                    2
                } else {
                    3
                };
                let blocked = match kind {
                    0 => prev_is(c) || next == c,
                    1 => prev_is(b'h'),
                    2 => next == b'h',
                    _ => false,
                };
                if kind < 3 && blocked {
                    match rand() % 100 {
                        0 => {}
                        1 => out.extend([b'y', c]),
                        _ => out.push(c),
                    }
                } else if kind == 0 {
                    out.extend([c, c]);
                } else if kind == 1 {
                    out.extend([b'h', c]);
                } else if kind == 2 {
                    out.extend([c, b'h']);
                } else if r == y_before {
                    if !prev_is(b'y') {
                        out.push(b'y');
                    }
                    out.push(c);
                } else {
                    out.push(c);
                    if r == y_after && next != b'y' {
                        out.push(b'y');
                    }
                }
            }
            b'e' | b'o' | b'u' => {
                let blocked = match r {
                    0..=3 => prev_is(c) || next == c,
                    4..=9 => prev_is(b'h'),
                    10..=21 => next == b'h',
                    _ => false,
                };
                if blocked {
                    match rand() % 100 {
                        0 => {}
                        1 => out.extend([b'y', c]),
                        _ => out.push(c),
                    }
                } else {
                    match r {
                        0..=3 => out.extend([c, c]),
                        4..=9 => out.extend([b'h', c]),
                        10..=21 => out.extend([c, b'h']),
                        22 => {
                            if !prev_is(b'y') {
                                out.push(b'y');
                            }
                            out.push(c);
                        }
                        _ => {
                            out.push(c);
                            if r == 23 && next != b'y' {
                                out.push(b'y');
                            }
                        }
                    }
                }
            }
            b'c' if last => {
                if r < 10 {
                    out.push(b'k');
                }
                if r < 15 {
                    out.extend(b"ch");
                }
                if r > 25 {
                    out.push(b'c');
                }
            }
            b'c' => match r {
                0..=9 => out.push(if next == b'k' { b'c' } else { b'k' }),
                10..=14 if next == b'h' => out.push(b'c'),
                10..=14 => out.extend(b"ch"),
                15 | 16 => {}
                _ => out.push(b'c'),
            },
            b'f' if last => {
                if r < 2 {
                    out.extend(b"ff");
                }
                if r < 5 {
                    out.extend(b"ph");
                }
                if r > 15 {
                    out.push(b'f');
                }
            }
            b'f' => match r {
                0..=4 if next != b'f' => out.extend(b"ff"),
                0..=2 => {}
                3 | 4 => out.push(b'f'),
                5..=9 => {
                    out.push(b'p');
                    if next != b'h' {
                        out.push(b'h');
                    }
                }
                10 | 11 => {}
                _ => out.push(b'f'),
            },
            _ if last => match r {
                10 => out.extend([c, c]),
                0..=11 => {}
                _ => out.push(c),
            },
            _ => {
                if r > 0 {
                    out.push(c);
                }
            }
        }
    }
    out.truncate(15);
    out
}

/// FUN_10239cc0 case 6: a Mithra, from the player's PlayOnline handle (`hint`, empty one time in ten). A result that
/// is the handle again or under 3 letters is no name.
fn mithra(t: &Tables, hint: &[u8], rand: Rand) -> Vec<u8> {
    let hint = &hint[..hint.iter().position(|&c| c == 0).unwrap_or(hint.len())];
    let start = &hint[..hint.len().min(15)];
    let out = mithra_mangle(&mithra_grow(t, start, rand), rand);
    if out == hint || out.len() < 3 { Vec::new() } else { out }
}

/// The Hume list of a face (FUN_10239cc0 cases 0 / 1 into FUN_10236a70): men 0x7c01 / 0x7c03 / 0x7c05, women
/// 0x7c00 / 0x7c02 / 0x7c04, the last of each for every face but two.
pub fn hume_list(woman: bool, face: usize) -> usize {
    match (woman, face) {
        (false, 5) => 1,
        (false, 7) => 3,
        (false, _) => 5,
        (true, 6) => 0,
        (true, 5) => 2,
        (true, _) => 4,
    }
}

fn record(read: Read, file: u32, n: u32) -> Vec<u8> {
    let mut r = read(file, n).unwrap_or_default();
    r.truncate(16);
    if let Some(end) = r.iter().position(|&c| c == 0) {
        r.truncate(end);
    }
    r
}

/// FUN_10239cc0 and, for the names read from the lists, FUN_10239940: the name of a race (0..=7, as the creator
/// counts them) and face (0..=7), or nothing. Without `tables` only a Galka gets one.
pub fn generate(
    tables: Option<&Tables>,
    race: usize,
    face: usize,
    hint: &[u8],
    read: Read,
    rand: Rand,
) -> Option<Vec<u8>> {
    let name = match race {
        0 | 1 => {
            let list = hume_list(race == 1, face);
            let records = tables?.hume_records(list);
            record(read, 0x7c00 + list as u32, rand() % records)
        }
        7 => {
            let n = rand() % 981;
            let mut acc = 0;
            let class = NOUN_WEIGHT
                .iter()
                .position(|w| {
                    acc += w;
                    n < acc
                })
                .unwrap_or(11);
            let noun = record(read, 0x7c07, n);
            let r = rand() % ((1u32 << (11 - class.min(10))) - 1);
            // Retail takes ln(r) / ln(2) through the FPU and cuts it: the whole part of log2(r).
            let k = if r == 0 { 1 } else { r.ilog2() as usize };
            let (count, first) = match tables {
                Some(t) => (t.adjective_count[k], t.adjective_first[k]),
                None => (ADJECTIVE_COUNT[k], ADJECTIVE_FIRST[k]),
            };
            let mut name = record(read, 0x7c06, rand() % count + first);
            if name.is_empty() {
                return None;
            }
            // FUN_10239940: the two joined; 16 letters or more is cut to 16 and then refused.
            name.extend(noun);
            name
        }
        2..=6 => {
            let t = tables?;
            // Two tries at a name that is not empty.
            (0..2)
                .map(|_| match race {
                    2 => elvaan_m(t, rand),
                    3 => elvaan_f(t, rand),
                    4 => taru_m(t, rand),
                    5 => taru_f(t, rand),
                    _ => mithra(t, hint, rand),
                })
                .find(|n| !n.is_empty())?
        }
        _ => return None,
    };
    (!name.is_empty() && name.len() < 16).then_some(name)
}

/// The adjective classes, for an install whose FFXiMain.dll is missing (0x103884ec / 0x10388518).
const ADJECTIVE_COUNT: [u32; 11] = [21, 74, 153, 220, 264, 317, 190, 99, 51, 12, 9];
const ADJECTIVE_FIRST: [u32; 11] = [0, 21, 95, 248, 468, 732, 1049, 1239, 1338, 1389, 1401];

/// Message 0xc of the name step (FUN_10239b10): nine times in ten the generator is handed the player's handle, which
/// only a Mithra's name uses. The name still has to pass the name filter (the caller's).
pub fn roll(
    tables: Option<&Tables>,
    race: usize,
    face: usize,
    handle: &[u8],
    read: Read,
    rand: Rand,
) -> Option<Vec<u8>> {
    let hint = if rand() % 10 != 7 { handle } else { &[] };
    generate(tables, race, face, hint, read, rand)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lcg(seed: u32) -> impl FnMut() -> u32 {
        let mut s = seed;
        move || {
            s = s.wrapping_mul(214013).wrapping_add(2531011);
            (s >> 16) & 0x7fff
        }
    }

    /// A made-up DLL: one section holding the tables, every syllable "ka".."zo" style text of our own.
    pub fn fake_dll() -> Vec<u8> {
        let base = 0x1000_0000u32;
        let (va, raw) = (0x1000u32, 0x400usize);
        let mut data = vec![0u8; 0x4000];
        // Strings first: 64 two-letter syllables at 3-byte steps.
        let strings = 0x3000;
        for i in 0..64usize {
            let s = [b"bdfgklmnprstvwyz"[i / 4 % 16], b"aeio"[i % 4], 0];
            data[strings + i * 3..strings + i * 3 + 3].copy_from_slice(&s);
        }
        let ptr = |i: usize| base + va + (strings + (i % 64) * 3) as u32;
        let a = 0x998;
        let mut put = |o: usize, v: u32| data[o..o + 4].copy_from_slice(&v.to_le_bytes());
        for i in 0..22 * 6 {
            put(a - 0x998 + i * 4, ptr(i));
        }
        for (i, n) in [22, 21, 12, 5, 8, 5].into_iter().enumerate() {
            put(a - 0x788 + i * 4, n);
        }
        for i in 0..67 * 7 {
            put(a - 0x770 + i * 4, ptr(i * 5));
        }
        for (i, n) in [67, 15, 10, 7, 36, 17, 12].into_iter().enumerate() {
            put(a - 0x1c + i * 4, n);
        }
        for (i, n) in NOUN_WEIGHT.into_iter().enumerate() {
            put(a + i * 4, n);
        }
        for i in 0..11 {
            put(a + 0x2c + i * 4, 3);
            put(a + 0x58 + i * 4, i as u32 * 3);
        }
        for i in 0..6 {
            put(a + 0x84 + i * 4, 4);
        }
        for i in 0..160 {
            // Row 0 is the bare vowels in retail; here the first five strings stand in.
            put(a + 0xa0 + i * 4, ptr(i));
            put(a + 0x320 + i * 4, 1 + (i as u32 * 7) % 10);
        }
        for (i, n) in [818, 25, 25, 10, 25, 10, 10, 5, 25, 10, 10, 5, 10, 5, 5, 2].into_iter().enumerate() {
            put(a + 0x5a0 + i * 4, n);
        }
        let mut dll = vec![0u8; raw];
        dll[0x3c] = 0x40;
        dll[0x40..0x44].copy_from_slice(b"PE\0\0");
        dll[0x46] = 1; // one section
        dll[0x54] = 0xe0; // optional header size
        dll[0x58 + 28..0x58 + 32].copy_from_slice(&base.to_le_bytes());
        let s = 0x58 + 0xe0;
        dll[s + 8..s + 12].copy_from_slice(&(data.len() as u32).to_le_bytes());
        dll[s + 12..s + 16].copy_from_slice(&va.to_le_bytes());
        dll[s + 16..s + 20].copy_from_slice(&(data.len() as u32).to_le_bytes());
        dll[s + 20..s + 24].copy_from_slice(&(raw as u32).to_le_bytes());
        dll.extend(data);
        dll
    }

    fn lists(file: u32, n: u32) -> Option<Vec<u8>> {
        let mut r = format!("f{:x}r{n}", file & 0xf).into_bytes();
        r.resize(16, 0);
        Some(r)
    }

    #[test]
    fn tables_from_a_dll() {
        let dll = fake_dll();
        let t = Tables::parse(&dll).expect("tables");
        assert_eq!(t.elvaan_m.len(), 469);
        assert_eq!(t.kana(0, 1), b"be");
        assert_eq!(t.weight[1][0], 1 + 35 % 10);
        // Not there, there twice, or pointing nowhere: no tables.
        assert!(Tables::parse(&dll[..dll.len() - 0x2000]).is_none());
        assert!(Tables::parse(b"MZ").is_none());
        let mut twice = dll.clone();
        twice.extend(NOUN_WEIGHT.iter().flat_map(|w| w.to_le_bytes()));
        assert!(Tables::parse(&twice).is_none());
        let mut wild = dll.clone();
        let at = 0x400 + 0x998 + 0xa0;
        wild[at..at + 4].copy_from_slice(&0x7000_0000u32.to_le_bytes());
        assert!(Tables::parse(&wild).is_none());
    }

    #[test]
    fn every_race_gets_a_name() {
        let t = Tables::parse(&fake_dll()).unwrap();
        for race in 0..8 {
            let mut got = 0;
            for seed in 0..200 {
                let mut rand = lcg(seed);
                if let Some(n) = roll(Some(&t), race, seed as usize % 8, b"steven", &mut lists, &mut rand) {
                    assert!((1..16).contains(&n.len()), "{race}: {n:?}");
                    assert!(race < 2 || race == 7 || n.iter().all(u8::is_ascii_lowercase), "{race}: {n:?}");
                    got += 1;
                }
            }
            assert!(got > 150, "race {race}: {got}");
        }
        // No tables: a Galka's name only (the lists are in the DAT files).
        for race in 0..8 {
            let mut rand = lcg(7);
            assert_eq!(roll(None, race, 0, b"steven", &mut lists, &mut rand).is_some(), race == 7);
        }
    }

    #[test]
    fn hume_lists_by_face() {
        let t = Tables::parse(&fake_dll()).unwrap();
        for (race, face, file) in
            [(0, 0, 5), (0, 5, 1), (0, 7, 3), (0, 6, 5), (1, 0, 4), (1, 5, 2), (1, 6, 0), (1, 7, 4)]
        {
            let mut rand = lcg(1);
            let n = generate(Some(&t), race, face, b"", &mut lists, &mut rand).unwrap();
            assert!(n.starts_with(format!("f{file}r").as_bytes()), "{race} {face}: {n:?}");
        }
    }

    #[test]
    fn galka_joins_adjective_and_noun() {
        let t = Tables::parse(&fake_dll()).unwrap();
        let mut rand = lcg(3);
        let n = generate(Some(&t), 7, 0, b"", &mut lists, &mut rand).unwrap();
        // The adjective list's record, then the noun list's.
        let s = String::from_utf8(n).unwrap();
        assert!(s.starts_with("f6r") && s.contains("f7r"), "{s}");
        // 16 letters or more is no name.
        let mut long = |_: u32, _: u32| Some(b"eightlet".to_vec());
        assert_eq!(generate(Some(&t), 7, 0, b"", &mut long, &mut lcg(3)), None);
    }

    #[test]
    fn mithra_starts_from_the_handle() {
        let t = Tables::parse(&fake_dll()).unwrap();
        // Only lower-case letters of the handle are kept.
        let mut rand = || 99;
        assert_eq!(mithra_grow(&t, b"Kupo-Mog 99", &mut rand), b"upoog");
        // Letters that roll in the middle are left alone; the handle unchanged is no name.
        assert_eq!(mithra_mangle(b"steven", &mut || 50), b"steven");
        assert_eq!(mithra(&t, b"satevenomaleketu", &mut || 50), b"satevenomaleket");
        assert_eq!(mithra(&t, b"satevenoma", &mut || 50), b"");
        // 10 doubles an 'a' and a last consonant and turns a 'c' into "ch"; 0 drops a letter.
        assert_eq!(mithra_mangle(b"abcd", &mut || 10), b"aabchdd");
        assert_eq!(mithra_mangle(b"xyz", &mut || 0), b"");
    }

    /// The port against retail: `VANA_RANDNAME_RETAIL` names a file written by the Wine harness that calls
    /// FFXiMain's own FUN_10239cc0 / FUN_10239940 (lines of race, face, hint, seed, rand() calls, name).
    #[test]
    fn same_names_as_retail() {
        let Ok(path) = std::env::var("VANA_RANDNAME_RETAIL") else { return };
        const HINTS: [&str; 22] = [
            "",
            "a",
            "Zz",
            "steven",
            "Steven",
            "akreao",
            "xX_Sephiroth_Xx",
            "bcdfgh",
            "aeiou",
            "mithra99",
            "abcdefghijklmno",
            "ABCDEFGHIJKLMNO",
            "cafe",
            "fffccc",
            "the quick brown",
            "Yy",
            "kyle",
            "ch",
            "ooo",
            "rhythm",
            "Kupo-Mog",
            "ffxi",
        ];
        let cfg = crate::config::Config::load();
        let index = crate::dat::DatIndex::open(&cfg.ffxi_dir()).expect("install");
        let tables = Tables::load(&cfg.ffxi_dir()).expect("tables");
        let files: Vec<Vec<u8>> = (0x7c00..0x7c08).map(|f| index.read(f).unwrap()).collect();
        let mut read = |file: u32, n: u32| {
            files[(file - 0x7c00) as usize].get(n as usize * 16..n as usize * 16 + 16).map(<[u8]>::to_vec)
        };
        let text = std::fs::read_to_string(path).unwrap();
        let (mut lines, mut wrong) = (0, 0);
        for line in text.lines() {
            let f: Vec<&str> = line.split(' ').collect();
            let (race, face, h): (usize, usize, usize) =
                (f[0].parse().unwrap(), f[1].parse().unwrap(), f[2].parse().unwrap());
            let mut calls = 0;
            let mut next = lcg(f[3].parse().unwrap());
            let mut rand = || {
                calls += 1;
                next()
            };
            let handle = if race == 6 { HINTS[h] } else { "steven" };
            let name = roll(Some(&tables), race, face, handle.as_bytes(), &mut read, &mut rand);
            let name = name.map_or("-".to_string(), |n| String::from_utf8_lossy(&n).into_owned());
            lines += 1;
            if name != f[5] || calls.to_string() != f[4] {
                wrong += 1;
                if wrong <= 20 {
                    eprintln!("{line}: ours {name} after {calls}");
                }
            }
        }
        assert!(lines > 0);
        assert_eq!(wrong, 0, "of {lines}");
    }
}
