//! LSB's xi_profile, which stands in for PlayOnline's profile and IRC services (MODLOG "The Friend List"): TLS
//! 1.3, every connection opening with {u32 account id, session hash}. The profile port answers one request per
//! connection; the IRC port is one long session for presence and new-mail notices.

use super::tls;
use anyhow::{Context, Result, bail};
use std::io::{BufRead, Read, Write};
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// The account's credentials from the game login and where xi_profile listens.
#[derive(Clone, Debug)]
pub struct Cred {
    pub host: String,
    pub port: u16,
    pub irc_port: u16,
    pub account: u32,
    pub hash: [u8; 16],
}

/// XORed into both POL ids of a message header or notice.
pub const POL_MASK: u64 = 0x1C27_3E45_6789_1133;

/// polcore's sqCalcChecksum: the little-endian u32 words summed, a 1..3-byte tail folded in from the top.
pub fn checksum(b: &[u8]) -> u32 {
    let mut sum = 0u32;
    let (words, rest) = b.as_chunks::<4>();
    for c in words {
        sum = sum.wrapping_add(u32::from_le_bytes(*c));
    }
    let tail = rest.iter().fold(0u32, |t, &x| t >> 8 | (x as u32) << 24);
    sum.wrapping_add(tail)
}

/// An IRC line's four checksum characters.
pub fn line_checksum(s: &str) -> String {
    let sum = checksum(s.as_bytes());
    [26, 20, 14, 8].iter().map(|&k| (((sum >> k) & 0x3f) as u8 + 0x3f) as char).collect()
}

const B64: &[u8; 64] = b"TSG8IncW3HFKokOg79qzeCmZs2yBYEQVAUxR5rbwi4P@jMDLtpvad0f_J1hlN6uX";

/// polcore's base64: its alphabet, standard bit order, a short group padded with the zero digit `T` (or not at all).
pub fn b64(bytes: &[u8], padded: bool) -> String {
    let mut out = String::new();
    for c in bytes.chunks(3) {
        let v = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        let n = c.len() + 1;
        for k in 0..4 {
            if k < n {
                out.push(B64[(v >> (18 - 6 * k) & 0x3f) as usize] as char);
            } else if padded {
                out.push('T');
            }
        }
    }
    out
}

/// Decodes whole 4-character groups (padding reads as zero bits).
pub fn b64_decode(s: &str) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    for g in s.as_bytes().chunks(4) {
        let mut v = 0u32;
        for (k, &ch) in g.iter().enumerate() {
            v |= (B64.iter().position(|&a| a == ch)? as u32) << (18 - 6 * k);
        }
        let n = g.len().saturating_sub(1);
        out.extend_from_slice(&[(v >> 16) as u8, (v >> 8) as u8, v as u8][..n]);
    }
    Some(out)
}

/// The IRC nick for a POL id (codec scrambleNick): "U" and 8 base-36 digits of polcore's alphabet.
pub fn nick(pol: u64) -> String {
    const DIGITS: &[u8] = b"EFKAOYMJVNGTDSWBQLPCIRHZXU6328401795";
    let mut v = (pol & 0x1ff_ffff_ffff) | 0xc000_0000_0000;
    for byte in [4, 3, 2, 1, 0] {
        v ^= (v >> 8) & (0xff << (8 * byte));
    }
    v &= !0xc000_0000_0000;
    let mut d = [b'E'; 8];
    for x in d.iter_mut().rev() {
        *x = DIGITS[(v % 36) as usize];
        v /= 36;
    }
    format!("U{}", String::from_utf8_lossy(&d))
}

/// FFXI's character key (characterKey): the id's low 16 bits, bits 16..23 moved to the top byte.
pub fn character_key(id: u32) -> u32 {
    (id & 0xffff) | ((id >> 16) & 0xff) << 24
}

fn connect(c: &Cred, port: u16) -> Result<tls::TlsStream> {
    let mut s = tls::connect(&c.host, port).with_context(|| format!("connecting to xi_profile {}:{port}", c.host))?;
    let mut hello = [0u8; 20];
    hello[..4].copy_from_slice(&c.account.to_le_bytes());
    hello[4..].copy_from_slice(&c.hash);
    s.write_all(&hello)?;
    Ok(s)
}

/// The largest answer body taken: xi_profile's largest is a ReadFile of a whole file (data/files.h fileSizeLimit,
/// 4 MiB) and its checksum; the rest is slack.
const MAX_ANSWER: usize = 0x40_0000 + 0x1000;

/// The longest IRC line taken: notices carry a base64 payload of a few hundred bytes.
const MAX_IRC_LINE: usize = 64 * 1024;

/// One profile request (3.2): ProfOpenData, ProfOpenAns 0x81, ProfSendReqData {kind 2, command, sub, size}, the body;
/// the answer's error (0 ok, 1 refused, 0x7e not found) and body.
pub fn request(c: &Cred, cmd: u8, sub: u8, body: &[u8]) -> Result<(u8, Vec<u8>)> {
    let mut s = connect(c, c.port)?;
    s.sock.set_read_timeout(Some(Duration::from_secs(30)))?;
    let mut open = [0u8; 0x28];
    open[4] = 1;
    s.write_all(&open)?;
    let mut ans = [0u8; 0x18];
    // A close here is xi_profile's answer to the open (the credentials), not a dropped link.
    if let Err(e) = s.read_exact(&mut ans) {
        if e.kind() == std::io::ErrorKind::UnexpectedEof {
            bail!("xi_profile closed the connection at the open (refused the credentials?)");
        }
        return Err(anyhow::Error::new(e).context("no answer to the open"));
    }
    if ans[0] != 0x81 || ans[1] != 0 {
        bail!("xi_profile open answer {:#x} error {}", ans[0], ans[1]);
    }
    let mut head = [0u8; 0x28];
    (head[0], head[1], head[2]) = (2, cmd, sub);
    head[4..8].copy_from_slice(&(body.len() as u32).to_le_bytes());
    s.write_all(&head)?;
    s.write_all(body)?;
    s.flush()?;
    let mut recv = [0u8; 0x18];
    s.read_exact(&mut recv).with_context(|| format!("no answer to request {cmd:#x}/{sub:#x}"))?;
    if recv[0] != 0x83 {
        bail!("xi_profile answer code {:#x}", recv[0]);
    }
    let size = u32::from_le_bytes(recv[4..8].try_into().unwrap()) as usize;
    let out = read_answer(&mut s, size).with_context(|| format!("the answer to request {cmd:#x}/{sub:#x}"))?;
    s.conn.send_close_notify();
    let _ = s.flush();
    Ok((recv[1], out))
}

/// An answer body of the `size` its header gave, at most MAX_ANSWER; it grows as the bytes arrive, so a size the
/// server never sends costs nothing.
fn read_answer(r: &mut impl Read, size: usize) -> Result<Vec<u8>> {
    if size > MAX_ANSWER {
        bail!("xi_profile claims a {size}-byte answer (the most taken is {MAX_ANSWER})");
    }
    let mut out = Vec::new();
    r.take(size as u64).read_to_end(&mut out)?;
    if out.len() != size {
        bail!("xi_profile closed the connection {} bytes into a {size}-byte answer", out.len());
    }
    Ok(out)
}

/// The body sealed with its checksum (the last u32).
fn sealed(mut b: Vec<u8>) -> Vec<u8> {
    let sum = checksum(&b);
    b.extend_from_slice(&sum.to_le_bytes());
    b
}

fn ok(r: (u8, Vec<u8>), what: &str) -> Result<Vec<u8>> {
    match r.0 {
        0 => Ok(r.1),
        e => bail!("{what}: xi_profile error {e:#x}"),
    }
}

fn count(b: &[u8]) -> usize {
    b.get(..4).map_or(0, |c| u32::from_le_bytes(c.try_into().unwrap()) as usize)
}

fn name16(b: &[u8]) -> String {
    let end = b.iter().position(|&c| c == 0).unwrap_or(b.len());
    String::from_utf8_lossy(&b[..end]).into_owned()
}

/// FriendInfo (3.3): one friend or block-list entry.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct FriendInfo {
    /// 1 set, 2 delete.
    pub op: u8,
    pub black: bool,
    pub handle_id: u64,
    pub pending: bool,
    /// The list index (0..199 friends, 0..99 block list) and display order.
    pub num: u8,
    pub order: u8,
    /// A store's answer: 0 applied, 1 refused.
    pub result: u8,
    pub pol: u64,
    pub name: String,
}

pub const FRIEND_INFO: usize = 0xa8;

impl FriendInfo {
    pub fn to_bytes(&self) -> [u8; FRIEND_INFO] {
        let mut b = [0u8; FRIEND_INFO];
        let bits = (self.op as u64 & 0xf)
            | (self.black as u64) << 4
            | 1 << 5
            | (self.handle_id & 0xfff_ffff_ffff) << 13
            | 0xe << 57
            | (self.pending as u64) << 62;
        b[..8].copy_from_slice(&bits.to_le_bytes());
        (b[8], b[9], b[10]) = (self.num, self.order, self.result);
        b[0x10..0x18].copy_from_slice(&self.pol.to_le_bytes());
        let n = self.name.as_bytes();
        b[0x18..0x18 + n.len().min(15)].copy_from_slice(&n[..n.len().min(15)]);
        b
    }

    pub fn from_bytes(b: &[u8]) -> Option<Self> {
        let b = b.get(..FRIEND_INFO)?;
        let bits = u64::from_le_bytes(b[..8].try_into().unwrap());
        Some(Self {
            op: (bits & 0xf) as u8,
            black: bits >> 4 & 1 != 0,
            handle_id: bits >> 13 & 0xfff_ffff_ffff,
            pending: bits >> 62 & 1 != 0,
            num: b[8],
            order: b[9],
            result: b[10],
            pol: u64::from_le_bytes(b[0x10..0x18].try_into().unwrap()),
            name: name16(&b[0x18..0x28]),
        })
    }
}

/// LoadFriendList (0x02 / 0x03): friends, then the block list.
pub fn load_friend_list(c: &Cred) -> Result<Vec<FriendInfo>> {
    let b = ok(request(c, 2, 3, &[])?, "LoadFriendList")?;
    Ok((0..count(&b)).filter_map(|k| FriendInfo::from_bytes(b.get(8 + k * FRIEND_INFO..)?)).collect())
}

/// StoreFriendList (0x02 / 0x06): every list index's display order and the changed entries; the entries answered.
pub fn store_friend_list(
    c: &Cred,
    friend_order: &[u8; 200],
    black_order: &[u8; 100],
    entries: &[FriendInfo],
) -> Result<Vec<FriendInfo>> {
    let mut b = Vec::with_capacity(0x130 + entries.len() * FRIEND_INFO + 8);
    b.extend_from_slice(friend_order);
    b.extend_from_slice(black_order);
    b.extend_from_slice(&(entries.len() as u16).to_le_bytes());
    b.extend_from_slice(&[0, 0]);
    for e in entries {
        b.extend_from_slice(&e.to_bytes());
    }
    b.extend_from_slice(&[0; 4]);
    let a = ok(request(c, 2, 6, &sealed(b))?, "StoreFriendList")?;
    Ok((0..count(&a)).filter_map(|k| FriendInfo::from_bytes(a.get(8 + k * FRIEND_INFO..)?)).collect())
}

/// LoadHandleNameList (0x00 / 0x09): our handle's id and name (LSB: the account's first character).
pub fn load_handle(c: &Cred) -> Result<(u64, String)> {
    let b = ok(request(c, 0, 9, &[])?, "LoadHandleNameList")?;
    let h = b.get(8..8 + 0x88).context("no handle")?;
    Ok((u64::from_le_bytes(h[8..16].try_into().unwrap()) & 0xfff_ffff_ffff, name16(&h[0x10..0x20])))
}

/// LoadCharacterList (0x01 / 0x03): (slot, character id, name) in the account's order.
pub fn load_characters(c: &Cred) -> Result<Vec<(u8, u32, String)>> {
    let b = ok(request(c, 1, 3, &[])?, "LoadCharacterList")?;
    Ok((0..count(&b))
        .filter_map(|k| {
            let e = b.get(8 + k * 0x68..8 + (k + 1) * 0x68)?;
            Some((e[0], u64::from_le_bytes(e[0x10..0x18].try_into().unwrap()) as u32, name16(&e[0x18..0x28])))
        })
        .collect())
}

/// SearchPolId (0x01 / 0x0B) for a character in game: its owner's POL id and the character's name.
pub fn search_pol_id(c: &Cred, char_id: u32) -> Result<Option<(u64, String)>> {
    let mut b = vec![0u8; 0x14];
    b[8..12].copy_from_slice(&character_key(char_id).to_le_bytes());
    b[0xc..0xe].copy_from_slice(&1u16.to_le_bytes());
    let a = ok(request(c, 1, 0xb, &sealed(b))?, "SearchPolId")?;
    if a.len() < 0x30 || a[0x20] == 0 {
        return Ok(None);
    }
    Ok(Some((u64::from_le_bytes(a[..8].try_into().unwrap()), name16(&a[0x10..0x20]))))
}

/// LoadMyStatus (0x04 / 0x06): our open status (0 Online, 1 Away, 4 Invisible).
pub fn load_my_status(c: &Cred) -> Result<u8> {
    let b = ok(request(c, 4, 6, &[])?, "LoadMyStatus")?;
    Ok(b.get(6).map_or(0, |&s| s.saturating_sub(1)))
}

/// ChangeMyStatus (0x04 / 0x05): in game with character `slot` (None: not in game), `open` the open status to set
/// (None keeps it).
pub fn change_my_status(c: &Cred, slot: Option<u8>, open: Option<u8>) -> Result<()> {
    let mut b = vec![0u8; 0x24];
    b[0x11] = slot.is_some() as u8;
    b[0x12] = slot.unwrap_or(0);
    b[0x13] = 1;
    b[0x14..0x16].copy_from_slice(&1u16.to_le_bytes());
    b[0x16] = open.map_or(0, |o| o + 1);
    ok(request(c, 4, 5, &sealed(b))?, "ChangeMyStatus").map(|_| ())
}

/// ProfFileHead (0x198): target (0 our files), path, offset, length.
fn file_head(target: u64, path: &str, offset: u32, length: u32) -> Vec<u8> {
    let mut b = vec![0u8; 0x198];
    b[8..16].copy_from_slice(&target.to_le_bytes());
    let p = path.as_bytes();
    b[0x10..0x10 + p.len().min(0x17f)].copy_from_slice(&p[..p.len().min(0x17f)]);
    b[0x190..0x194].copy_from_slice(&offset.to_le_bytes());
    b[0x194..0x198].copy_from_slice(&length.to_le_bytes());
    b
}

/// The mailbox.
pub const MAILBOX: &str = "O/m/";

/// GetFileList (0x03 / 0x03) of the mailbox: (time, size, name) oldest first.
pub fn mail_list(c: &Cred) -> Result<Vec<(u32, u32, String)>> {
    let mut b = file_head(0, MAILBOX, 0, 0);
    b.extend_from_slice(&[0; 4]);
    let a = ok(request(c, 3, 3, &sealed(b))?, "GetFileList")?;
    Ok((0..count(&a))
        .filter_map(|k| {
            let e = a.get(8 + k * 0x108..8 + (k + 1) * 0x108)?;
            Some((
                u32::from_le_bytes(e[..4].try_into().unwrap()),
                u32::from_le_bytes(e[4..8].try_into().unwrap()),
                name16(&e[8..]),
            ))
        })
        .collect())
}

/// ReadFile (0x03 / 0x00): a whole file of ours (the answer's trailing checksum dropped).
pub fn read_file(c: &Cred, path: &str) -> Result<Vec<u8>> {
    let mut b = file_head(0, path, 0, u32::MAX);
    b.extend_from_slice(&[0; 4]);
    let mut a = ok(request(c, 3, 0, &sealed(b))?, "ReadFile")?;
    a.truncate(a.len().saturating_sub(4));
    Ok(a)
}

/// WriteFile (0x03 / 0x01) to another account: posts a message into its mailbox.
pub fn write_file(c: &Cred, target: u64, path: &str, data: &[u8]) -> Result<()> {
    let mut b = file_head(target, path, 0, data.len() as u32);
    b.extend_from_slice(data);
    ok(request(c, 3, 1, &sealed(b))?, "WriteFile").map(|_| ())
}

/// RemoveFile (0x03 / 0x02): the head's length field carries the checksum.
pub fn remove_file(c: &Cred, path: &str) -> Result<()> {
    let b = sealed(file_head(0, path, 0, 0)[..0x194].to_vec());
    ok(request(c, 3, 2, &b)?, "RemoveFile").map(|_| ())
}

/// Message types (header +0x3e bits 7..11).
pub const PLAIN: u8 = 0;
pub const FRIEND_REQUEST: u8 = 1;
pub const FRIEND_ACCEPTED: u8 = 9;
pub const FRIEND_DECLINED: u8 = 10;

/// sqPolMessageHeader (0x48, 3.4.3): a message's file name is "O/m/" and its base64.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct MsgHeader {
    pub from: u64,
    pub to: u64,
    /// One of the sender's character names (LSB checks it).
    pub sender: String,
    /// The list title: `header_title` of the data, 15 bytes of Shift-JIS (polcore FUN_100150e0).
    pub title: Vec<u8>,
    /// The title did not fit its 15 bytes (+0x42 bit 12).
    pub title_cut: bool,
    pub seq: u32,
    /// sqGetCalendarTime *(inf: unix seconds)*.
    pub date: u32,
    pub length: u32,
    pub kind: u8,
    pub no_reply: bool,
}

impl MsgHeader {
    pub fn to_bytes(&self) -> [u8; 0x48] {
        let mut b = [0u8; 0x48];
        b[..8].copy_from_slice(&(self.from ^ POL_MASK).to_le_bytes());
        b[8..16].copy_from_slice(&(self.to ^ POL_MASK).to_le_bytes());
        for (d, c) in b[0x10..0x1f].iter_mut().zip(self.sender.bytes()) {
            *d = c;
        }
        for (d, c) in b[0x20..0x2f].iter_mut().zip(&self.title) {
            *d = *c;
        }
        b[0x30..0x34].copy_from_slice(&self.seq.to_le_bytes());
        b[0x34..0x38].copy_from_slice(&self.date.to_le_bytes());
        b[0x38..0x3c].copy_from_slice(&self.length.to_le_bytes());
        let bits = ((self.kind as u16 & 0x1f) << 7) | 1 << 15;
        b[0x3e..0x40].copy_from_slice(&bits.to_le_bytes());
        let flags = (self.no_reply as u16) << 9 | (self.title_cut as u16) << 12;
        b[0x42..0x44].copy_from_slice(&flags.to_le_bytes());
        b
    }

    pub fn from_bytes(b: &[u8]) -> Option<Self> {
        let b = b.get(..0x48)?;
        let u32at = |o: usize| u32::from_le_bytes(b[o..o + 4].try_into().unwrap());
        let bits = u16::from_le_bytes([b[0x3e], b[0x3f]]);
        Some(Self {
            from: u64::from_le_bytes(b[..8].try_into().unwrap()) ^ POL_MASK,
            to: u64::from_le_bytes(b[8..16].try_into().unwrap()) ^ POL_MASK,
            sender: name16(&b[0x10..0x20]),
            title: b[0x20..0x30].split(|&c| c == 0).next().unwrap_or_default().to_vec(),
            title_cut: b[0x43] & 0x10 != 0,
            seq: u32at(0x30),
            date: u32at(0x34),
            length: u32at(0x38),
            kind: (bits >> 7 & 0x1f) as u8,
            no_reply: b[0x43] & 2 != 0,
        })
    }

    /// The mailbox file name.
    pub fn file_name(&self) -> String {
        b64(&self.to_bytes(), true)
    }

    /// The whole name is the 96 digits (no separator or dot among them): it becomes a file name in the mail folder.
    pub fn from_name(name: &str) -> Option<Self> {
        Self::from_bytes(&b64_decode((name.len() == 96).then_some(name)?)?)
    }
}

/// polcore's separator between a message's title and its text.
pub const BODY_SEP: u8 = 7;

/// Bytes of Shift-JIS up to a NUL, at most `max`, never half a two-byte character (the copy loops of FFXiMain's
/// FUN_100f2a10 / FUN_100f2ad0: a byte with the top bit set goes with the one after it or not at all).
pub fn sjis_cut(s: &[u8], max: usize) -> &[u8] {
    let mut n = 0;
    while n < s.len() && s[n] != 0 {
        let step = if s[n] & 0x80 != 0 { 2 } else { 1 };
        if n + step > max || (step == 2 && s.get(n + 1).is_none_or(|&c| c == 0)) {
            break;
        }
        n += step;
    }
    &s[..n]
}

/// FUN_100f2a10(title, n): the title FFXiMain hands to polcore. With n = 0x32 (plain messages, replies, declines) at
/// most 50 bytes; with a smaller n (0x10: friend requests and accepts) exactly n bytes, the title over n spaces.
pub fn body_title(title: &[u8], n: usize) -> Vec<u8> {
    if n >= 0x32 {
        return sjis_cut(title, 0x32).to_vec();
    }
    let mut b = vec![b' '; n];
    let t = sjis_cut(title, n);
    b[..t.len()].copy_from_slice(t);
    b
}

/// A message's data as polcore writes it (table +0x440, FUN_10015260): the title (up to a NUL, at most 0x80 bytes),
/// 0x07, the text (up to a NUL, at most 0xfff bytes), NUL; an attachment would follow. FFXiMain's text is at most 300
/// bytes (FUN_100f2ad0).
pub fn encode_body(title: &[u8], text: &[u8]) -> Vec<u8> {
    let part = |s: &[u8], max: usize| s.iter().copied().take_while(|&c| c != 0).take(max).collect::<Vec<u8>>();
    let mut b = part(title, 0x80);
    b.push(BODY_SEP);
    b.extend(part(sjis_cut(text, 300), 0xfff));
    b.push(0);
    b
}

/// polcore's reader (table +0x43c, FUN_10015400): the title ends at 0x07 (at most 0x7f bytes), the text at the NUL
/// after it; data with no 0x07 in reach, nothing after it or no NUL fails (FFXiMain's reader then reports error
/// 0x10). Ours also reads the data this client wrote before 2026-11-11 (title NUL text NUL, no 0x07 anywhere).
pub fn decode_body(b: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    if !b.contains(&BODY_SEP) {
        let mut parts = b.split(|&c| c == 0);
        return Some((parts.next()?.to_vec(), parts.next().unwrap_or_default().to_vec()));
    }
    let end = b.iter().take(0x7f).position(|&c| c == BODY_SEP).unwrap_or(b.len().min(0x7f));
    let rest = b.get(end + 1..).filter(|r| !r.is_empty())?;
    let len = rest.iter().take(0xfff).position(|&c| c == 0)?;
    Some((b[..end].to_vec(), rest[..len].to_vec()))
}

/// FUN_100f4ff0(out, 0x20, data): the header's title is the start of the data itself, title and text run together:
/// every run of bytes at or under a space (the 0x07 too) becomes one space, at most 31 bytes. polcore's header
/// builder (table +0x438, FUN_100150e0) keeps 15 of them, drops half a two-byte character at the end, and flags a
/// title that lost bytes. Returns (title, cut).
pub fn header_title(data: &[u8]) -> (Vec<u8>, bool) {
    let mut out = Vec::new();
    let (mut i, mut run) = (0, false);
    while i < data.len() && data[i] != 0 && out.len() + 1 < 0x20 {
        let c = data[i];
        if c & 0x80 != 0 && out.len() + 2 < 0x20 {
            out.extend_from_slice(&[c, data.get(i + 1).copied().unwrap_or(0)]);
            (i, run) = (i + 2, false);
        } else if c & 0x80 == 0 && c > b' ' {
            out.push(c);
            (i, run) = (i + 1, false);
        } else {
            if !run {
                out.push(b' ');
            }
            (i, run) = (i + 1, true);
        }
    }
    let full = out.iter().position(|&c| c == 0).unwrap_or(out.len());
    let kept = sjis_cut(&out[..full], 15).len();
    out.truncate(kept);
    (out, kept < full)
}

/// A notice's Status as polcore stores it in the friend entry's bits 13..15 (FUN_10017560, 0x1001762e: `dec eax; and
/// eax, 7`, then anything from 5 up is 0): 1 offline -> 0, 2 online -> 1, 3 away -> 2, 4 and 5 -> 3 and 4, 0 and 6
/// up -> 0.
pub fn entry_status(notice: u8) -> u8 {
    let v = notice.wrapping_sub(1) & 7;
    if v >= 5 { 0 } else { v }
}

/// Posts a message: its header names the file, the data follows.
pub fn send_message(c: &Cred, h: &MsgHeader, data: &[u8]) -> Result<()> {
    write_file(c, h.to, &format!("{MAILBOX}{}", h.file_name()), data)
}

/// What the IRC session hears.
#[derive(Clone, Debug)]
pub enum Irc {
    /// The profile-available notice: signed on.
    SignedOn,
    /// A friend's status notice: where we list them, the status block when it applies (`entry_status`, playing),
    /// the character primitive when one follows, and the notice's age (only newer ones apply).
    Status {
        account: u64,
        list_index: u8,
        status: Option<(u8, bool)>,
        char_id: Option<u32>,
        age: u64,
    },
    /// A new message (its header is not kept: the list is fetched again).
    Mail,
    Closed(String),
}

/// The IRC session (3.4) on a separate thread; dropping the sender ends it with QUIT.
pub struct IrcLink {
    pub events: mpsc::Receiver<Irc>,
    /// Held for its Drop: dropping it ends the session with QUIT.
    #[allow(dead_code)]
    pub quit: mpsc::Sender<()>,
}

pub fn irc(c: Cred) -> IrcLink {
    let (tx, events) = mpsc::channel();
    let (quit, stop) = mpsc::channel();
    std::thread::spawn(move || {
        let why = match irc_run(&c, &tx, &stop) {
            Ok(()) => "quit".to_string(),
            Err(e) => format!("{e:#}"),
        };
        let _ = tx.send(Irc::Closed(why));
    });
    IrcLink { events, quit }
}

fn send_line(s: &mut tls::TlsStream, text: &str) -> Result<()> {
    s.write_all(format!("{text}{}\r\n", line_checksum(text)).as_bytes())?;
    s.flush()?;
    Ok(())
}

fn irc_run(c: &Cred, tx: &mpsc::Sender<Irc>, stop: &mpsc::Receiver<()>) -> Result<()> {
    let mut s = connect(c, c.irc_port)?;
    s.sock.set_read_timeout(Some(Duration::from_millis(500)))?;
    let me = nick(c.account as u64);
    send_line(&mut s, "USER vana")?;
    send_line(&mut s, &format!("NICK {me}"))?;
    let mut r = std::io::BufReader::new(s);
    let mut line = String::new();
    let mut last = Instant::now();
    loop {
        match stop.try_recv() {
            Ok(()) | Err(mpsc::TryRecvError::Disconnected) => {
                let _ = send_line(r.get_mut(), "QUIT");
                return Ok(());
            }
            Err(mpsc::TryRecvError::Empty) => {}
        }
        // The server pings after 60 s of silence; ours comes first.
        if last.elapsed() > Duration::from_secs(50) {
            send_line(r.get_mut(), "PING :x")?;
            last = Instant::now();
        }
        // Bounded, so a server that never sends the newline can't grow the line without limit.
        match r.by_ref().take((MAX_IRC_LINE + 1 - line.len()) as u64).read_line(&mut line) {
            Ok(0) => bail!("closed by the server"),
            Ok(_) if line.ends_with('\n') => {
                let l = line.trim_end_matches(['\r', '\n']);
                // A line whose last 4 bytes split a character is malformed: skipped.
                if let Some(text) = l.get(..l.len().saturating_sub(4)) {
                    irc_line(r.get_mut(), text, tx)?;
                }
                line.clear();
            }
            Ok(_) if line.len() > MAX_IRC_LINE => bail!("an IRC line over {MAX_IRC_LINE} bytes"),
            Ok(_) => {}
            Err(e) if matches!(e.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut) => {}
            Err(e) => return Err(e.into()),
        }
    }
}

fn irc_line(s: &mut tls::TlsStream, text: &str, tx: &mpsc::Sender<Irc>) -> Result<()> {
    let words: Vec<&str> = text.split(' ').filter(|w| !w.is_empty()).skip(text.starts_with(':') as usize).collect();
    match words.first().copied() {
        Some("PING") => send_line(s, "PONG a")?,
        Some("NOTICE") => {
            let payload = text.split_once(" :").map_or("", |p| p.1);
            if let Some(ev) = notice(payload) {
                let _ = tx.send(ev);
            }
        }
        _ => {}
    }
    Ok(())
}

/// The status block of a notice (header +0x10..), as polcore's notice handler applies it (the function at
/// 0x100160a0.. passes it to FUN_1001c9b0 only with extension flag 1; FUN_10017560 returns before the status when
/// the connected byte is not 0, 1 or 2): the entry status and the playing bit (+0x12 bit 0).
fn status_block(h: &[u8], ext_flags: u8) -> Option<(u8, bool)> {
    (ext_flags & 1 != 0 && h[0x10] <= 2).then(|| (entry_status(h[0x11]), h[0x12] & 1 != 0))
}

/// The friend list's size in polcore (200 entries at DAT_10109288): a notice for a higher index changes nothing.
const LIST_SIZE: u8 = 200;

/// The extension's character primitive: its offset (after the 8-byte flags block, flag 2's 16 bytes and flag 4's 8)
/// when the notice carries one the entry takes, flags 1 and 8 together (FUN_1001c9b0 stores it inside the status
/// block's branch: 0x1001c9f6 `je 0x1001ca7f` jumps over both).
fn primitive_at(flags: u8) -> Option<usize> {
    (flags & 9 == 9).then(|| 8 + if flags & 2 != 0 { 16 } else { 0 } + if flags & 4 != 0 { 8 } else { 0 })
}

/// A notice's payload (3.4.3): the 0x48-byte header in 96 characters, then a status notice's extended block. The
/// type-31 paths of polcore's handler (FUN_100160c0, header +0x19 / +0x1a / +0x1b):
/// - +0x1b set: the legacy block. The sign-on is +0x10 == 1 with +0x18 and +0x1c both 0xff (LSB's profile-available
///   notice); else the header's own status block applies to entry +0x1c (FUN_1001c970, newer only), no extension
///   read.
/// - +0x1a set: a message notice for the viewer (its title and text to callback 1); not a friend's status.
/// - +0x19 bit 0 with +0x1a and +0x1b clear and a length under 0x158: the extension. Its flag 2 hands the notice to
///   FUN_100200a0 (a 16-byte block for something other than the list) and the entry is not touched; otherwise the
///   status block with flag 1 and the character with flags 1 and 8 (FUN_1001c9b0).
fn notice(payload: &str) -> Option<Irc> {
    let h = b64_decode(payload.get(..96)?)?;
    if h.len() < 0x48 {
        return None;
    }
    let ty = u16::from_le_bytes([h[0x3e], h[0x3f]]) >> 7 & 0x1f;
    let polpro = h[0x42] & 1 != 0;
    if ty != 31 {
        return polpro.then_some(Irc::Mail);
    }
    let account = u64::from_le_bytes(h[..8].try_into().unwrap()) ^ POL_MASK;
    let (list_index, age) = (h[0x1c], u64::from_le_bytes(h[0x30..0x38].try_into().unwrap()));
    if h[0x1b] != 0 {
        if h[0x10] == 1 && h[0x18] == 0xff && h[0x1c] == 0xff {
            return Some(Irc::SignedOn);
        }
        return (list_index < LIST_SIZE).then(|| Irc::Status {
            account,
            list_index,
            status: status_block(&h, 1),
            char_id: None,
            age,
        });
    }
    let length = u32::from_le_bytes(h[0x38..0x3c].try_into().unwrap());
    if h[0x1a] != 0 || h[0x19] & 1 == 0 || length >= 0x158 || list_index >= LIST_SIZE {
        return None;
    }
    let ext = b64_decode(&payload[96..]).unwrap_or_default();
    let flags = ext.first().copied().unwrap_or(0);
    if flags & 2 != 0 {
        return None;
    }
    let char_id = primitive_at(flags)
        .and_then(|at| ext.get(at + 8..at + 0x10))
        .map(|id| u64::from_le_bytes(id.try_into().unwrap()) as u32);
    Some(Irc::Status { account, list_index, status: status_block(&h, flags), char_id, age })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An answer header claiming more than any real answer is refused before anything is allocated, and one cut
    /// short is an error.
    #[test]
    fn answer_size_is_capped() {
        assert!(read_answer(&mut &[][..], u32::MAX as usize).is_err());
        assert!(read_answer(&mut &[][..], MAX_ANSWER + 1).is_err());
        assert!(read_answer(&mut &[1u8, 2][..], 3).is_err());
        assert_eq!(read_answer(&mut &[1u8, 2, 3, 4][..], 3).unwrap(), [1, 2, 3]);
        let whole = vec![7u8; MAX_ANSWER];
        assert_eq!(read_answer(&mut &whole[..], MAX_ANSWER).unwrap().len(), MAX_ANSWER);
    }

    /// Vectors derived from LSB's codec (MODLOG "The Friend List and PlayOnline messages").
    #[test]
    fn codec() {
        assert_eq!(checksum(&[1, 2, 3, 4, 5]), 0x0903_0201);
        assert_eq!(checksum(b"USER x"), 0xca65_5355);
        assert_eq!(line_checksum("USER x"), "qeTR");
        assert_eq!(line_checksum("NICK UABCDEFGH"), "F@Ba");
        assert_eq!(line_checksum("PONG :x"), "nw`n");
        assert_eq!(b64(&[0, 1, 2, 3, 4, 5], true), "TTIGTt7n");
        assert_eq!(b64_decode("TTIGTt7n").unwrap(), vec![0, 1, 2, 3, 4, 5]);
        let f = FriendInfo { op: 1, handle_id: 1003, ..Default::default() };
        assert_eq!(&f.to_bytes()[..8], &[0x21, 0x60, 0x7d, 0, 0, 0, 0, 0x1c]);
        assert_eq!(FriendInfo::from_bytes(&f.to_bytes()).unwrap().handle_id, 1003);
        assert_eq!(character_key(0x12_3456), 0x1200_3456);
    }

    /// The local xi_profile with a test account (by hand: `VANA_TEST_CREDENTIALS=<json with username and password>
    /// cargo test --release profile_live -- --ignored --nocapture`).
    #[test]
    #[ignore]
    fn profile_live() {
        let j: serde_json::Value = serde_json::from_slice(
            &std::fs::read(std::env::var("VANA_TEST_CREDENTIALS").expect("VANA_TEST_CREDENTIALS")).unwrap(),
        )
        .unwrap();
        let req = super::super::auth::Request {
            username: j["username"].as_str().unwrap(),
            password: j["password"].as_str().unwrap(),
            ..Default::default()
        };
        let super::super::auth::Reply::LoggedIn { account_id, session_hash, .. } =
            super::super::auth::send("127.0.0.1", 54231, super::super::auth::Command::Login, &req).unwrap()
        else {
            panic!()
        };
        let c =
            Cred { host: "127.0.0.1".into(), port: 51220, irc_port: 51240, account: account_id, hash: session_hash };
        let link = irc(c.clone());
        println!("irc: {:?}", link.events.recv_timeout(Duration::from_secs(10)));
        println!("status {:?}", load_my_status(&c));
        println!("friends {:?}", load_friend_list(&c));
        println!("handle {:?}", load_handle(&c));
        println!("chars {:?}", load_characters(&c));
        println!("mail {:?}", mail_list(&c));
        let _ = link.quit.send(());
        println!("irc: {:?}", link.events.recv_timeout(Duration::from_secs(5)));
    }

    #[test]
    fn message_header() {
        let h = MsgHeader {
            from: 1000,
            to: 1003,
            sender: "Lnxcsfix".into(),
            title: b"Hi".to_vec(),
            title_cut: false,
            seq: 7,
            date: 1_800_000_000,
            length: 12,
            kind: FRIEND_REQUEST,
            no_reply: false,
        };
        assert_eq!(h.file_name().len(), 96);
        assert_eq!(MsgHeader::from_name(&h.file_name()), Some(h.clone()));
        // A server's name with more after the header would be a path out of the mail folder.
        assert_eq!(MsgHeader::from_name(&format!("{}\\..\\..\\x.bat", h.file_name())), None);
    }

    /// polcore's data layout (FUN_10015260 / FUN_10015400) and FFXiMain's title and text limits.
    #[test]
    fn message_body() {
        assert_eq!(encode_body(b"T", b"text"), b"T\x07text\0");
        assert_eq!(decode_body(b"T\x07text\0"), Some((b"T".to_vec(), b"text".to_vec())));
        // An attachment after the NUL is not text.
        assert_eq!(decode_body(b"T\x07text\0\x01\x02"), Some((b"T".to_vec(), b"text".to_vec())));
        // Nothing after the title, or no NUL: polcore's reader fails.
        assert_eq!(decode_body(b"T\x07"), None);
        assert_eq!(decode_body(b"T\x07text"), None);
        // What this client wrote before.
        assert_eq!(decode_body(b"T\0text\0"), Some((b"T".to_vec(), b"text".to_vec())));
        // Requests and accepts: 16 bytes exactly (the English title loses its "!").
        assert_eq!(body_title(b"Let's be friends!", 0x10), b"Let's be friends");
        assert_eq!(body_title(b"Deleted", 0x10), b"Deleted         ");
        // Half a two-byte character is never kept.
        assert_eq!(sjis_cut(&[0x97, 0x46, 0x92, 0x42], 3), &[0x97, 0x46]);
        assert_eq!(sjis_cut(&[0x97, 0x46, 0x92], 4), &[0x97, 0x46]);
        assert_eq!(encode_body(b"T", &[b'a'; 400]).len(), 2 + 300 + 1);
    }

    /// The header's title is cut from the data (FUN_100f4ff0, then FUN_100150e0's 15 bytes).
    #[test]
    fn title_from_data() {
        assert_eq!(header_title(b"Let's be friends\x07Bob\0"), (b"Let's be friend".to_vec(), true));
        assert_eq!(header_title(b"Message\x07hi  there\0"), (b"Message hi ther".to_vec(), true));
        assert_eq!(header_title(b"Hi\x07yo\0"), (b"Hi yo".to_vec(), false));
        assert_eq!(header_title(b""), (Vec::new(), false));
        // 14 bytes, then a two-byte character that does not fit the 15.
        let mut d = b"abcdefghijklmn".to_vec();
        d.extend_from_slice(&[0x97, 0x46, 0]);
        assert_eq!(header_title(&d), (b"abcdefghijklmn".to_vec(), true));
    }

    /// polcore's Status -> entry status (FUN_10017560) and the gates on the block.
    #[test]
    fn notice_status() {
        let got: Vec<u8> = (0..=9).map(entry_status).collect();
        assert_eq!(got, [0, 0, 1, 2, 3, 4, 0, 0, 0, 0]);
        let mut h = [0u8; 0x48];
        (h[0x10], h[0x11], h[0x12]) = (2, 3, 1);
        assert_eq!(status_block(&h, 1), Some((2, true)));
        assert_eq!(status_block(&h, 8), None);
        h[0x10] = 3;
        assert_eq!(status_block(&h, 1), None);
    }

    /// The handler's paths (FUN_100160c0) on LSB's two notices and the variants no server of ours sends.
    #[test]
    fn notice_paths() {
        let head = |f: &dyn Fn(&mut [u8; 0x48])| {
            let mut h = [0u8; 0x48];
            h[0x3e..0x40].copy_from_slice(&(31u16 << 7).to_le_bytes());
            h[0x42] = 1;
            f(&mut h);
            b64(&h, true)
        };
        let ext = |b: &[u8]| b64(b, false);
        let status = |n: &str| match notice(n) {
            Some(Irc::Status { list_index, status, char_id, .. }) => Some((list_index, status, char_id)),
            _ => None,
        };
        // LSB's profile-available notice.
        let sign_on = head(&|h| (h[0x10], h[0x18], h[0x1b], h[0x1c]) = (1, 0xff, 1, 0xff));
        assert!(matches!(notice(&sign_on), Some(Irc::SignedOn)));
        // A friend's "connected 1" is a status, not the sign-on.
        let connected1 = head(&|h| (h[0x10], h[0x11], h[0x19], h[0x1c]) = (1, 2, 1, 4));
        assert_eq!(status(&(connected1 + &ext(&[1, 0, 0, 0, 0, 0, 0, 0]))), Some((4, Some((1, false)), None)));
        // The legacy block applies the header's status without an extension.
        let legacy = head(&|h| (h[0x10], h[0x11], h[0x1b], h[0x1c]) = (2, 3, 1, 7));
        assert_eq!(status(&legacy), Some((7, Some((2, false)), None)));
        // LSB's playing friend: flags 1 | 8, the id at 0x10; with flag 4 the id moves to 0x18.
        let playing = head(&|h| (h[0x10], h[0x11], h[0x12], h[0x19], h[0x1c]) = (2, 2, 1, 1, 3));
        let mut e = vec![9u8, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0];
        e.extend_from_slice(&0x1234u64.to_le_bytes());
        assert_eq!(status(&(playing.clone() + &ext(&e))), Some((3, Some((1, true)), Some(0x1234))));
        let mut e4 = vec![13u8, 0, 0, 0, 0, 0, 0, 0];
        e4.extend_from_slice(&[0; 8]);
        e4.extend_from_slice(&[1, 0, 0, 0, 0, 0, 0, 0]);
        e4.extend_from_slice(&0x5678u64.to_le_bytes());
        assert_eq!(status(&(playing.clone() + &ext(&e4))), Some((3, Some((1, true)), Some(0x5678))));
        // Flag 8 without flag 1: neither status nor character, only the age.
        e[0] = 8;
        assert_eq!(status(&(playing.clone() + &ext(&e))), Some((3, None, None)));
        // Flag 2 goes elsewhere; +0x1a or a clear +0x19 bit 0 is no status notice.
        e[0] = 3;
        assert_eq!(status(&(playing + &ext(&e))), None);
        assert!(notice(&head(&|h| (h[0x19], h[0x1a]) = (1, 1))).is_none());
        assert!(notice(&head(&|h| h[0x1c] = 3)).is_none());
        // An index past polcore's 200 entries.
        assert!(notice(&head(&|h| (h[0x1b], h[0x1c]) = (1, 200))).is_none());
    }

    #[test]
    fn padding() {
        let h = vec![7u8; 0x48];
        assert_eq!(b64(&h, true).len(), 96);
        assert_eq!(b64_decode(&b64(&h, true)).unwrap(), h);
        assert_eq!(b64(&[1, 2], false).len(), 3);
    }
}
