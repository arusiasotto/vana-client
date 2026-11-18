//! The auto-translate dictionary (language slot 0x18; English file 55665) and the phrase blocks in text
//! (`FD kind lang hi lo FD`, kept by font::decode_sjis as four private-use chars). MODLOG "Auto-translate: the
//! dictionary" (loader FUN_101bb7a0, resolver FUN_101bc100, expander FUN_101ac990).

use super::DatIndex;
use super::font::{KIND_VARIABLE, PHRASE_MARK, decode_sjis, is_phrase, raw_byte};
use super::msg::Messages;
use super::names::NameSource;
use anyhow::{Context, Result};
use std::collections::HashMap;

/// One phrase group: its title (phrase id 0, "【Greetings】") and its phrases by id.
pub struct Group {
    pub id: u8,
    pub title: String,
    pub key: String,
    /// (phrase id, text, completion key) in file order; `@X<hex>` texts stay raw until resolved.
    pub phrases: Vec<(u8, String, String)>,
}

pub struct Dictionary {
    pub groups: Vec<Group>,
    by_id: HashMap<u8, usize>,
    /// Group 0x12 (job names, `@J`), group 0x14 (places, `@A`), group 0xb 0x91 .. 0x94 (the item and key item groups'
    /// titles and keys).
    jobs: Option<Messages>,
    places: Option<Messages>,
    titles: [(String, String); 2],
    /// The groups built at run time (FUN_101bcd10), in slot order: Key Items (D+0x218), then Items (D+0x214). Empty
    /// until the root category list first opens.
    built: std::sync::RwLock<Vec<Built>>,
}

/// A group built at run time: its header kind (7 items, 0x13 key items), title, completion key and words (block id,
/// text; a word's key is its text).
#[derive(Clone, Debug, PartialEq)]
pub struct Built {
    pub kind: u8,
    pub title: String,
    pub key: String,
    pub words: Vec<([u8; 4], String)>,
}

/// Header kind 2 a phrase group; language 2 English (the client's language + 1).
const GROUP_KIND: u8 = 2;
const LANG_EN: u8 = 2;
/// The built groups' header kinds.
pub const KIND_ITEMS: u8 = 7;
pub const KIND_KEY_ITEMS: u8 = 0x13;

/// FUN_101ae530: block kinds 7..0x12 are items (7), 0x13.. key items (0x13); the rest stay.
fn norm(kind: u8) -> u8 {
    match kind {
        0..=6 => kind,
        7..=0x12 => KIND_ITEMS,
        _ => KIND_KEY_ITEMS,
    }
}

/// An item or key item block's id (the inner switches of FUN_101bd6d0): kinds 7 / 0xb / 0xf / 0x13 carry both bytes,
/// 9 / 0xd / 0x11 / 0x15 the low byte, 0xa / 0xe / 0x12 / 0x16 the high byte; any other kind is id 0.
fn block_id(kind: u8, hi: u8, lo: u8) -> u32 {
    match kind {
        7 | 0xb | 0xf | 0x13 => (hi as u32) << 8 | lo as u32,
        9 | 0xd | 0x11 | 0x15 => lo as u32,
        0xa | 0xe | 0x12 | 0x16 => (hi as u32) << 8,
        _ => 0,
    }
}

/// What a block names: None a phrase (its group and id are the block's last two bytes), else (key item, id) of an
/// item or key item block, id 0 its group's title.
pub fn block_item(b: [u8; 4]) -> Option<(bool, u32)> {
    (b[0] >= 7).then(|| (norm(b[0]) == KIND_KEY_ITEMS, block_id(b[0], b[2], b[3])))
}

/// An item or key item id as a block (FUN_101bc770 / FUN_101bca80): no 00 byte; `base` 7 or 0x13, + 1 for id 0,
/// + 2 when only the high byte is 0, + 3 when only the low byte is 0, the zero bytes written FF.
pub fn id_block(base: u8, id: u16) -> [u8; 4] {
    let [hi, lo] = id.to_be_bytes();
    match (hi, lo) {
        (0, 0) => [base + 1, LANG_EN, 0xff, 0xff],
        (0, _) => [base + 2, LANG_EN, 0xff, lo],
        (_, 0) => [base + 3, LANG_EN, hi, 0xff],
        _ => [base, LANG_EN, hi, lo],
    }
}

impl Dictionary {
    pub fn load(index: &DatIndex, ffximain: &[u8]) -> Result<Self> {
        let file = super::msg::slot_file(ffximain, 1, 0x18).context("auto-translate slot")?;
        let data = index.read(file)?;
        let msgs = |g: u8| super::msg::group_file(ffximain, 1, g).and_then(|f| Messages::load(index, f).ok());
        let slot = |s: usize| super::msg::slot_file(ffximain, 1, s).and_then(|f| Messages::load(index, f).ok());
        let b = msgs(0xb);
        let title = |id: usize| b.as_ref().and_then(|m| m.get(id)).unwrap_or_default();
        let mut d = Self::parse(&data)?;
        d.jobs = msgs(0x12);
        d.places = msgs(0x14);
        d.titles = [(title(0x91), title(0x92)), (title(0x93), title(0x94))];
        // FUN_101ba5d0 replaces @ texts by the names at load; the keys follow them.
        let (spells, abilities) = (slot(super::battle::SLOT_SPELLS), slot(super::battle::SLOT_ABILITIES));
        let mut groups = std::mem::take(&mut d.groups);
        for g in &mut groups {
            for p in &mut g.phrases {
                if let Some(t) = d.at_name(&p.1, spells.as_ref(), abilities.as_ref()) {
                    p.1 = t.clone();
                    p.2 = t;
                }
            }
        }
        d.groups = groups;
        Ok(d)
    }

    /// `@A` place, `@C` spell, `@J` job, `@Y` ability by hex id (FUN_101ba5d0); None for other texts.
    fn at_name(&self, text: &str, spells: Option<&Messages>, abilities: Option<&Messages>) -> Option<String> {
        let rest = text.strip_prefix('@')?;
        let (kind, hex) = rest.split_at(rest.len().min(1));
        let id = usize::from_str_radix(hex, 16).ok()?;
        match kind {
            "A" => self.places.as_ref()?.get(id),
            "J" => self.jobs.as_ref()?.get(id),
            "C" => spells?.get(id),
            "Y" => abilities?.get(id),
            _ => None,
        }
        .filter(|n| !n.is_empty())
    }

    /// FUN_101bcd10 on the root category list: Key Items, then Items, built again from the record cache's slots
    /// (`recent`) and the key item table as (id, name, owned); a group with no entry is not there.
    pub fn rebuild(&self, recent: &[(u32, String)], key_items: &[(u32, String, bool)]) {
        let mut built = Vec::new();
        let mut keys = Vec::new();
        for (id, name, _) in key_items.iter().filter(|k| k.2) {
            if (0x181..=0x183).contains(id) || keys.len() >= 0xfe {
                break;
            }
            keys.push((id_block(KIND_KEY_ITEMS, *id as u16), name.clone()));
        }
        // A title that did not load (group 0xb) leaves its group out: no blank category, no empty brackets.
        if !keys.is_empty() && !self.titles[1].0.is_empty() {
            let (title, key) = self.titles[1].clone();
            built.push(Built { kind: KIND_KEY_ITEMS, title, key, words: keys });
        }
        let items: Vec<_> = recent
            .iter()
            .filter(|(id, name)| *id != 0 && !name.starts_with('.') && !(0x7400..=0xfffe).contains(id))
            .map(|(id, name)| (id_block(KIND_ITEMS, *id as u16), name.clone()))
            .collect();
        if !items.is_empty() && !self.titles[0].0.is_empty() {
            let (title, key) = self.titles[0].clone();
            built.push(Built { kind: KIND_ITEMS, title, key, words: items });
        }
        if let Ok(mut b) = self.built.write() {
            *b = built;
        }
    }

    /// The groups built at run time as they stand (held read: `rebuild` waits).
    pub fn built(&self) -> std::sync::RwLockReadGuard<'_, Vec<Built>> {
        self.built.read().unwrap_or_else(|e| e.into_inner())
    }

    /// FUN_101bba90 / FUN_101bbc60 / FUN_101bbe60: the phrases of category `filter` (FUN_101bc640), else the words
    /// whose key starts with `word`, else the categories. (text, block id) by key, and whether the word matched.
    pub fn query(&self, word: &str, filter: Option<[u8; 4]>) -> (Vec<(String, [u8; 4])>, bool) {
        let sorted = |mut v: Vec<(String, String, [u8; 4])>| {
            v.sort_by_key(|w| w.1.to_lowercase());
            v
        };
        let built = self.built();
        if let Some(f) = filter {
            let words: Vec<(String, String, [u8; 4])> = if let Some(&i) = self.by_id.get(&f[2]) {
                let gr = &self.groups[i];
                gr.phrases.iter().map(|p| (p.1.clone(), p.2.clone(), [GROUP_KIND, LANG_EN, gr.id, p.0])).collect()
            } else if let Some(b) = built.iter().find(|b| b.kind == f[0]) {
                b.words.iter().map(|w| (w.1.clone(), w.1.clone(), w.0)).collect()
            } else {
                return (Vec::new(), false);
            };
            return (sorted(words).into_iter().map(|w| (w.0, w.2)).collect(), false);
        }
        let titles = || {
            self.groups
                .iter()
                .map(|g| (g.title.clone(), [GROUP_KIND, LANG_EN, g.id, 0]))
                .chain(built.iter().map(|b| (b.title.clone(), [b.kind, LANG_EN, 0, 0])))
                .collect::<Vec<_>>()
        };
        let w = word.to_lowercase();
        if w.is_empty() {
            return (titles(), false);
        }
        let mut all: Vec<(String, String, [u8; 4])> = Vec::new();
        for g in &self.groups {
            all.push((g.title.clone(), g.key.clone(), [GROUP_KIND, LANG_EN, g.id, 0]));
            all.extend(g.phrases.iter().map(|p| (p.1.clone(), p.2.clone(), [GROUP_KIND, LANG_EN, g.id, p.0])));
        }
        for b in built.iter() {
            all.push((b.title.clone(), b.key.clone(), [b.kind, LANG_EN, 0, 0]));
            all.extend(b.words.iter().map(|w| (w.1.clone(), w.1.clone(), w.0)));
        }
        let mut seen = std::collections::HashSet::new();
        let hits: Vec<(String, [u8; 4])> = sorted(all)
            .into_iter()
            .filter(|x| !x.0.is_empty() && !x.0.starts_with(' ') && x.1.to_lowercase().starts_with(&w))
            .filter(|x| seen.insert(x.0.clone()))
            .map(|x| (x.0, x.2))
            .collect();
        if hits.is_empty() { (titles(), false) } else { (hits, true) }
    }

    /// FUN_101ac990 without braces (a text command's argument, the line being typed): blocks as their plain text.
    pub fn expand_plain(&self, s: &str, names: Option<&dyn NameSource>) -> String {
        self.expand(s, names).chars().filter(|&c| c != '\u{E008}' && c != '\u{E009}').collect()
    }

    /// Groups (0x4c-byte header: kind, language, group id, 0, title[32], completion[32], u32 count, u32 bytes) then
    /// entries (4 id bytes, u8 length, text; languages 1 and 4 add a second string). Only English groups are kept.
    pub fn parse(data: &[u8]) -> Result<Self> {
        Self::parse_lang(data, LANG_EN)
    }

    /// The groups of one language byte (1 Japanese, 2 English, 3 German, 4 French: the client's language + 1; the
    /// group loader FUN_101bc090 by the group's own byte). English and German entries are a word whose key is its
    /// text (FUN_101bbfa0). In a Japanese or French group (FUN_101bbe00) every entry outside the item kinds 7..0x12
    /// carries a second string after the text: the kana reading in Japanese, the text without its accents in French.
    /// When it holds more than its NUL it is the word's key (FUN_101bddc0), the key completion matches and sorts by;
    /// else the key is the text. This client is English only: the French extras (a second word keyed by the text
    /// itself for each entry with a second string, and a second title word keyed by the title inside its brackets
    /// when FUN_101c9e70 finds it differs from the completion) are not built.
    pub fn parse_lang(data: &[u8], language: u8) -> Result<Self> {
        let mut groups = Vec::new();
        let mut at = 0;
        let cstr = |b: &[u8]| decode_sjis(&b[..b.iter().position(|&c| c == 0).unwrap_or(b.len())]);
        while at + 0x4c <= data.len() {
            let h = &data[at..at + 0x4c];
            let bytes = u32::from_le_bytes(h[0x48..0x4c].try_into().unwrap()) as usize;
            let count = u32::from_le_bytes(h[0x44..0x48].try_into().unwrap()) as usize;
            let body = data.get(at + 0x4c..at + 0x4c + bytes).context("group runs past the file")?;
            at += 0x4c + bytes;
            if h[0] != GROUP_KIND || h[1] != language {
                continue;
            }
            // Each phrase takes at least 5 bytes; a bad count must not reserve more than the group holds.
            let mut phrases = Vec::with_capacity(count.min(body.len() / 5));
            let mut p = 0;
            while p + 5 <= body.len() && phrases.len() < count {
                let (kind, id, len) = (body[p], body[p + 3], body[p + 4] as usize);
                let text = cstr(body.get(p + 5..p + 5 + len).context("phrase runs past its group")?);
                p += 5 + len;
                let mut key = text.clone();
                if matches!(h[1], 1 | 4) && !(7..=0x12).contains(&kind) {
                    let l2 = body.get(p).copied().unwrap_or(0) as usize;
                    if l2 >= 2 {
                        key = cstr(body.get(p + 1..p + 1 + l2).context("phrase key runs past its group")?);
                    }
                    p += 1 + l2;
                }
                phrases.push((id, text, key));
            }
            groups.push(Group { id: h[2], title: cstr(&h[4..0x24]), key: cstr(&h[0x24..0x44]), phrases });
        }
        let by_id = groups.iter().enumerate().map(|(i, g)| (g.id, i)).collect();
        Ok(Dictionary {
            groups,
            by_id,
            jobs: None,
            places: None,
            titles: Default::default(),
            built: Default::default(),
        })
    }

    /// FUN_101bd6d0: a block's text, the language byte ignored. Kinds 7.. are items / key items (`block_id`, id 0 the
    /// built group's title), any other kind (6 too) a phrase. None: unknown (the line ends there).
    pub fn resolve(&self, b: [u8; 4], names: Option<&dyn NameSource>) -> Option<String> {
        let [kind, _, hi, lo] = b;
        if kind >= 7 {
            let id = block_id(kind, hi, lo);
            let key = norm(kind) == KIND_KEY_ITEMS;
            if id == 0 {
                let title = self.built.read().ok()?.iter().find(|g| g.kind == norm(kind)).map(|g| g.title.clone());
                if title.is_some() || !key {
                    return title;
                }
            }
            let n = names?;
            return if key { n.key_item(id).map(|x| x.bare) } else { n.item_name(id) };
        }
        let g = &self.groups[*self.by_id.get(&hi)?];
        if lo == 0 {
            return Some(g.title.clone());
        }
        let (_, text, _) = g.phrases.iter().find(|p| p.0 == lo)?;
        Some(text.clone()).filter(|t| !t.starts_with('@'))
    }

    /// FUN_101ac990 with braces (the log): each block becomes its text between the green and red auto-translate
    /// brackets (EF 27 / EF 28, U+E008 / U+E009); an unknown block cuts the line there. A variable block (kind 6)
    /// has no brackets (`variable`).
    pub fn expand(&self, s: &str, names: Option<&dyn NameSource>) -> String {
        let chars: Vec<char> = s.chars().collect();
        let mut out = String::with_capacity(s.len());
        let mut at = 0;
        while at < chars.len() {
            if is_variable(&chars, at) {
                match self.variable(&chars, &mut at, names) {
                    Some(t) => out.push_str(&t),
                    None => break,
                }
            } else if let Some(block) = block_at(&chars, at) {
                at += 4;
                // A 6-byte block of kind 6 is a variable block whose length byte is FD (negative): the line ends.
                match Some(block).filter(|b| b[0] != KIND_VARIABLE).and_then(|b| self.resolve(b, names)) {
                    Some(t) => {
                        out.push('\u{E008}');
                        out.push_str(&t);
                        out.push('\u{E009}');
                    }
                    None => break,
                }
            } else {
                // A lone phrase char (a cut block) shows nothing, as before.
                if !is_phrase(chars[at]) {
                    out.push(chars[at]);
                }
                at += 1;
            }
        }
        out
    }

    /// FUN_101adbb0: `FD 06 x x x nn <template> x`; each FD in the template is a place, filled by the next block in
    /// the line, else by the place's id bytes. None (the line ends): nn over 0x7f, or a following block that fails.
    fn variable(&self, chars: &[char], at: &mut usize, names: Option<&dyn NameSource>) -> Option<String> {
        let byte = |i: usize| chars.get(i).and_then(|&c| raw_byte(c));
        let nn = byte(*at + 5).filter(|&n| n < 0x80)? as usize;
        let body: Vec<u8> = (0..nn).map(|k| byte(*at + 6 + k)).collect::<Option<_>>()?;
        byte(*at + 6 + nn)?;
        *at += nn + 7;
        let mut out = String::new();
        let mut run = Vec::new();
        let mut i = 0;
        while i < nn {
            if body[i] != PHRASE_MARK {
                run.push(body[i]);
                i += 1;
                continue;
            }
            out.push_str(&decode_sjis(&std::mem::take(&mut run)));
            if is_variable(chars, *at) {
                out.push_str(&self.variable(chars, at, names)?);
            } else if let Some(block) = block_at(chars, *at) {
                // Kind 6 there is a variable block with a negative length: FUN_101adbb0 fails on it.
                if block[0] == KIND_VARIABLE {
                    return None;
                }
                *at += 4;
                out.push_str(&self.resolve(block, names)?);
            } else {
                // A failed id adds the resolver's -1 to this call's length (its buffer, not the caller's).
                let id = [1, 2, 3, 4].map(|k| body.get(i + k).copied().unwrap_or(0));
                match self.resolve(id, names) {
                    Some(t) => out.push_str(&t),
                    None => {
                        out.pop();
                    }
                }
            }
            i += 6;
        }
        out.push_str(&decode_sjis(&run));
        Some(out)
    }
}

/// The four id bytes of the block starting at `at` (four phrase chars, positions 0..3).
fn block_at(chars: &[char], at: usize) -> Option<[u8; 4]> {
    let mut b = [0u8; 4];
    for (k, x) in b.iter_mut().enumerate() {
        let cp = *chars.get(at + k)? as u32;
        if !is_phrase(chars[at + k]) || (cp - super::font::PHRASE_BASE) / 0x100 != k as u32 {
            return None;
        }
        *x = cp as u8;
    }
    Some(b)
}

/// A variable block starts at `at`: the kept bytes FD 06 (font::decode_sjis).
fn is_variable(chars: &[char], at: usize) -> bool {
    let byte = |i: usize| chars.get(i).and_then(|&c| raw_byte(c));
    byte(at) == Some(PHRASE_MARK) && byte(at + 1) == Some(KIND_VARIABLE)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The other languages' files (slot 0x18: ja 55545, de 55785, fr 56205): the same 42 groups; Japanese and French
    /// entries carry the second key.
    #[test]
    fn second_keys() {
        let cfg = crate::config::Config::load();
        let Ok(index) = DatIndex::open(&cfg.ffxi_dir()) else { return };
        for (file, lang) in [(55545, 1), (55785, 3), (56205, 4)] {
            let Ok(data) = index.read(file) else { return };
            let d = Dictionary::parse_lang(&data, lang).unwrap();
            let all: Vec<&(u8, String, String)> = d.groups.iter().flat_map(|g| &g.phrases).collect();
            let key = |text: &str| all.iter().find(|p| p.1 == text).map(|p| p.2.as_str());
            assert_eq!((d.groups.len(), all.len()), (42, 2685));
            match lang {
                // The kana reading; a phrase written in kana already has none.
                1 => assert_eq!(key("初めまして。"), Some("ハジメマシテ。")),
                3 => assert!(all.iter().all(|p| p.1 == p.2)),
                // The text without accents (and here without its full stop).
                _ => assert_eq!(key("Pardon."), Some("Pardon")),
            }
        }
    }

    /// File 55665: 42 English groups; Greetings 1 is "Nice to meet you."; @J / @C / @Y name references resolve; a
    /// block in a chat line expands between the brackets.
    #[test]
    fn english_dictionary() {
        let cfg = crate::config::Config::load();
        let Ok(index) = DatIndex::open(&cfg.ffxi_dir()) else { return };
        let Ok(dll) = std::fs::read(crate::dat::ffximain(&cfg.ffxi_dir())) else { return };
        let d = Dictionary::load(&index, &dll).unwrap();
        assert_eq!(d.groups.len(), 42);
        let names = crate::dat::names::Names::load(&index, crate::dat::items::Lang::En).unwrap();
        let n: Option<&dyn NameSource> = Some(&names);
        assert_eq!(d.resolve([2, 2, 1, 1], n).as_deref(), Some("Nice to meet you."));
        assert_eq!(d.resolve([2, 2, 0x10, 1], n).as_deref(), Some("Thief"));
        assert_eq!(d.resolve([2, 2, 0x1b, 1], n).as_deref(), Some("Protect"));
        assert_eq!(d.resolve([2, 2, 0x2a, 0x27], n).as_deref(), Some("Soul Enslavement"));
        let line = decode_sjis(b"Hi \xFD\x02\x02\x01\x01\xFD");
        assert_eq!(d.expand(&line, n), "Hi \u{E008}Nice to meet you.\u{E009}");
        // Completion: "prot" finds Protect (and its kin) before the categories; no word gives the 42 titles.
        let (hits, matched) = d.query("prot", None);
        assert!(matched && hits.iter().any(|c| c.0 == "Protect"));
        assert_eq!(d.query("", None).0.len(), 42);
        assert_eq!(d.query("", Some([2, 2, 1, 0])).0.first().map(|c| c.1[2]), Some(1));
        // An item phrase is the record's name, not its log noun (record cache +0x1b4), and joins the Items group.
        assert_eq!(d.resolve([7, 2, 0x40, 0x97], n).as_deref(), Some("Bronze Sword"));
        assert_eq!(d.resolve([8, 2, 0xff, 0xff], n), None);
        d.rebuild(&names.items.recent(), &[]);
        let b = d.built().clone();
        assert_eq!(b.len(), 1);
        assert_eq!((b[0].kind, b[0].words.as_slice()), (7, &[([7, 2, 0x40, 0x97], "Bronze Sword".to_string())][..]));
        assert_eq!(d.query("", None).0.len(), 43);
        assert_eq!(d.resolve([8, 2, 0xff, 0xff], n).as_deref(), Some(b[0].title.as_str()));
        assert!(d.query("bronze s", None).0.iter().any(|c| c.1 == [7, 2, 0x40, 0x97]));
    }

    /// One group (id 1) with phrases 1 "Hello!" and 2 "Thanks.".
    fn small() -> Dictionary {
        let mut data = vec![2, 2, 1, 0];
        let field = |t: &str| {
            let mut f = t.as_bytes().to_vec();
            f.resize(32, 0);
            f
        };
        data.extend(field("[Greetings]"));
        data.extend(field("greetings"));
        let mut body = Vec::new();
        for (id, t) in [(1u8, "Hello!"), (2, "Thanks.")] {
            body.extend([2, 2, 1, id, t.len() as u8 + 1]);
            body.extend(t.as_bytes());
            body.push(0);
        }
        data.extend(2u32.to_le_bytes());
        data.extend((body.len() as u32).to_le_bytes());
        data.extend(body);
        let mut d = Dictionary::parse(&data).unwrap();
        d.titles = [("(Items)".into(), "items".into()), ("(Key Items)".into(), "key items".into())];
        d
    }

    /// FUN_101bcd10: Key Items takes the first free slot, Items the next; the skips, the 00-free ids and the scan's
    /// end at an owned 0x181..0x183.
    #[test]
    fn built_groups() {
        let d = small();
        assert_eq!(d.query("", None).0.len(), 1);
        // No group yet: id 0 of an item is nothing, of a key item key item 0's name (none here).
        assert_eq!(d.resolve([8, 2, 0xff, 0xff], None), None);
        assert_eq!(d.resolve([0x14, 2, 0xff, 0xff], None), None);
        let s = |t: &str| t.to_string();
        let recent = [
            (0x1010, s("Potion")),
            (0x0050, s("Chair")),
            (0x1000, s("Ether")),
            (0x7400, s("Objective")),
            (0xfffe, s("Last")),
            (0xffff, s("Gil")),
            (0x0011, s(".hidden")),
        ];
        let keys = [
            (0, s("-header"), false),
            (0x45, s("Airship pass"), true),
            (0x46, s("Not owned"), false),
            (0x200, s("Map"), true),
            (0x182, s("Stop"), true),
            (0x300, s("After"), true),
        ];
        d.rebuild(&recent, &keys);
        let b = d.built().clone();
        assert_eq!(b.iter().map(|g| g.kind).collect::<Vec<_>>(), vec![0x13, 7]);
        assert_eq!(b[0].words, vec![([0x15, 2, 0xff, 0x45], s("Airship pass")), ([0x16, 2, 2, 0xff], s("Map"))]);
        assert_eq!(
            b[1].words,
            vec![
                ([7, 2, 0x10, 0x10], s("Potion")),
                ([9, 2, 0xff, 0x50], s("Chair")),
                ([10, 2, 0x10, 0xff], s("Ether")),
                ([7, 2, 0xff, 0xff], s("Gil")),
            ]
        );
        // The categories: the file's groups, Key Items, Items; a category's words by key.
        let cats = d.query("", None).0;
        assert_eq!(
            cats.iter().map(|c| c.0.as_str()).collect::<Vec<_>>(),
            vec!["[Greetings]", "(Key Items)", "(Items)"]
        );
        assert_eq!(cats[2].1, [7, 2, 0, 0]);
        let items = d.query("", Some(cats[2].1)).0;
        assert_eq!(items.iter().map(|c| c.0.as_str()).collect::<Vec<_>>(), vec!["Chair", "Ether", "Gil", "Potion"]);
        assert_eq!(d.query("", Some(cats[1].1)).0.len(), 2);
        // A typed word finds them among the phrases; the titles answer by their keys.
        assert_eq!(d.query("po", None).0, vec![(s("Potion"), [7, 2, 0x10, 0x10])]);
        assert_eq!(d.query("key", None).0, vec![(s("(Key Items)"), [0x13, 2, 0, 0])]);
        // Id 0 is the group's title while it stands; kinds past 0x16 are id 0 too.
        assert_eq!(d.resolve([8, 2, 0xff, 0xff], None).as_deref(), Some("(Items)"));
        assert_eq!(d.resolve([0x17, 2, 1, 2], None).as_deref(), Some("(Key Items)"));
        assert_eq!((block_id(0xd, 0xff, 0x50), block_id(0x12, 0x10, 0xff), block_id(0xf, 1, 2)), (0x50, 0x1000, 0x102));
        // What a block names: every built word gives its id back; a category block is id 0; a phrase is none.
        assert_eq!(
            b[1].words.iter().map(|w| block_item(w.0)).collect::<Vec<_>>(),
            [0x1010, 0x50, 0x1000, 0xffff].map(|i| Some((false, i)))
        );
        assert_eq!(
            b[0].words.iter().map(|w| block_item(w.0)).collect::<Vec<_>>(),
            [0x45, 0x200].map(|i| Some((true, i)))
        );
        assert_eq!(
            (block_item(cats[2].1), block_item(cats[1].1), block_item(cats[0].1)),
            (Some((false, 0)), Some((true, 0)), None)
        );
        // Nothing held and an empty cache: both groups go.
        d.rebuild(&[], &keys[..3].iter().map(|k| (k.0, k.1.clone(), false)).collect::<Vec<_>>());
        assert!(d.built().is_empty());
    }

    /// A title that did not load leaves its group out: no blank category, and id 0 still ends the line.
    #[test]
    fn untitled_groups() {
        let mut d = small();
        d.titles = Default::default();
        d.rebuild(&[(0x1010, "Potion".into())], &[(0x45, "Airship pass".into(), true)]);
        assert!(d.built().is_empty());
        assert_eq!(d.query("", None).0.len(), 1);
        assert_eq!(d.resolve([8, 2, 0xff, 0xff], None), None);
    }

    /// FUN_101adbb0's variable block: the template's places take the blocks that follow it, else their id bytes; no
    /// brackets; a length byte over 0x7f ends the line.
    #[test]
    fn variable_block() {
        let d = small();
        // "<" place ">" then the block that fills the place.
        let line = decode_sjis(b"a \xFD\x06\x02\x01\x01\x08<\xFD\x02\x02\x01\x02\xFD>\xFD\xFD\x02\x02\x01\x01\xFD b");
        assert_eq!(d.expand(&line, None), "a <Hello!> b");
        // No block follows: the place's id bytes; the next plain block keeps its brackets.
        let line = decode_sjis(b"\xFD\x06\x00\x00\x00\x06\xFD\x02\x02\x01\x02\xFD\xFD!");
        assert_eq!(d.expand(&line, None), "Thanks.!");
        let line = decode_sjis(b"\xFD\x06\x00\x00\x00\x00\xFD\xFD\x02\x02\x01\x01\xFD");
        assert_eq!(d.expand(&line, None), "\u{E008}Hello!\u{E009}");
        // A variable block fills a place of another; an unknown place id takes one byte off.
        let line = decode_sjis(
            b"\xFD\x06\x00\x00\x00\x07[\xFD\x02\x02\x01\x02\xFD\xFD\xFD\x06\x00\x00\x00\x08xy\xFD\x02\x02\x09\x09\xFD\xFD.",
        );
        assert_eq!(d.expand(&line, None), "[x.");
        // A following block that resolves to nothing, and a negative length, end the line.
        let line = decode_sjis(b"ok\xFD\x06\x00\x00\x00\x06\xFD\x02\x02\x01\x02\xFD\xFD\xFD\x02\x02\x09\x09\xFDtail");
        assert_eq!(d.expand(&line, None), "ok");
        let line = decode_sjis(b"ok\xFD\x06\x00\x00\x00\xFDtail");
        assert_eq!(d.expand(&line, None), "ok");
        // The template's text before a failing place goes with it: the call builds its text apart and returns -1.
        let line =
            decode_sjis(b"ok\xFD\x06\x00\x00\x00\x09Hi \xFD\x02\x02\x01\x02\xFD\xFD\xFD\x02\x02\x09\x09\xFDtail");
        assert_eq!(d.expand(&line, None), "ok");
        // A following kind-6 block (its length byte FD) ends the line; a place's id bytes of kind 6 are a phrase.
        let line = decode_sjis(b"ok\xFD\x06\x00\x00\x00\x06\xFD\x02\x02\x01\x02\xFD\xFD\xFD\x06\x02\x01\x01\xFDtail");
        assert_eq!(d.expand(&line, None), "ok");
        let line = decode_sjis(b"\xFD\x06\x00\x00\x00\x06\xFD\x06\x02\x01\x01\xFD\xFD!");
        assert_eq!(d.expand(&line, None), "Hello!!");
        // The bytes survive a round trip.
        let raw = b"\xFD\x06\x02\x01\x01\x08<\xFD\x02\x02\x01\x02\xFD>\xFD";
        assert_eq!(crate::dat::font::encode_sjis(&decode_sjis(raw)), raw);
    }
}
