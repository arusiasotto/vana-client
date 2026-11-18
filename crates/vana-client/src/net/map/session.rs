//! UDP session with a zone (map) server.
//!
//! Datagram: 28-byte header (u16 our sequence, u16 last server sequence seen, u32 time at 8),
//! then sub-packets. Except for the first 0x00A, sub-packets are compressed (or, when the codes would not fit, plain
//! behind a 0 byte), followed by the size in bits (u32) and an MD5 of both, and everything after the header is
//! Blowfish-encrypted in whole 8-byte blocks. The coder is FUN_100dd590 (out) and FUN_100dd6c0 (in).

use super::blowfish::Blowfish;
use super::compress::Codec;
use anyhow::{Result, bail};
use md5::{Digest, Md5};
use std::net::{SocketAddr, UdpSocket};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const HEADER: usize = 28;

#[derive(Debug, Clone)]
pub struct SubPacket {
    pub id: u16,
    pub sync: u16,
    /// Whole sub-packet, including its 4-byte header.
    pub data: Vec<u8>,
}

impl SubPacket {
    pub fn u8(&self, o: usize) -> u8 {
        self.data.get(o).copied().unwrap_or(0)
    }
    pub fn u16(&self, o: usize) -> u16 {
        u16::from_le_bytes([self.u8(o), self.u8(o + 1)])
    }
    pub fn u32(&self, o: usize) -> u32 {
        u32::from_le_bytes([self.u8(o), self.u8(o + 1), self.u8(o + 2), self.u8(o + 3)])
    }
    pub fn f32(&self, o: usize) -> f32 {
        f32::from_bits(self.u32(o))
    }
    pub fn str(&self, o: usize, len: usize) -> String {
        let end = (o + len).min(self.data.len());
        let bytes = &self.data[o.min(end)..end];
        let bytes = &bytes[..bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len())];
        // The game's text is Shift-JIS (with its glyph pairs and auto-translate blocks).
        crate::dat::font::decode_sjis(bytes)
    }
}

/// Builds one sub-packet; the body is padded to the 4-byte unit the size field counts in.
pub fn build(id: u16, body: &[u8]) -> Vec<u8> {
    let len = (4 + body.len()).div_ceil(4) * 4;
    let mut p = vec![0u8; len];
    p[..2].copy_from_slice(&(id & 0x1FF | ((len / 4) as u16) << 9).to_le_bytes());
    p[4..4 + body.len()].copy_from_slice(body);
    p
}

fn now() -> u32 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as u32).unwrap_or(0)
}

pub struct MapSession {
    sock: UdpSocket,
    cipher: Blowfish,
    /// The key the cipher was made from, for 0x00A's ticket, and the 20 bytes hashed for it.
    key: [u8; 16],
    key20: [u8; 20],
    /// A second key (MapLogin::old_key) tried while no datagram has been read; the first to pass with it makes it ours.
    alt: Option<(Blowfish, [u8; 20])>,
    codec: Codec,
    seq: u16,
    server_seq: u16,
    /// Datagram bytes sent / received on this session, for the Network window.
    pub bytes_out: u64,
    pub bytes_in: u64,
    /// Datagrams dropped because they failed their checksum or didn't decompress, and how many in a row.
    pub bad_in: u64,
    bad_run: u32,
    /// Sub-packets not yet acked, stamped with the sequence of their first send (FUN_100fac80 resends them in
    /// every datagram until the server's header u16 @2 reaches it), and that ack.
    unacked: Vec<(u16, Vec<u8>)>,
    server_ack: u16,
    /// Header sequence of the last datagram handled; none before the first.
    last_in: Option<u16>,
    /// Datagrams logged so far each way (the first few of a session are logged).
    logged: (u32, u32),
    /// From the zone-in (s2c 0x00A u32 @0x94 / @0x98): every later datagram's header carries it (FUN_100fa9f0).
    cert: Option<[u32; 2]>,
    /// The header clock (DAT_10492e10): seconds and ms at an instant, set by the zone-in and every 30th datagram.
    clock: Option<(u32, u32, std::time::Instant)>,
    /// Retail's simulated loss (DAT_104e1ca0 +0x184, FUN_100fa710 0x100fa7f1): the percentage of read datagrams thrown
    /// away, and the generator's state. Ours takes it from FFXI_NET_DROP, for testing the lag step.
    drop: (u32, u32),
}

const LOG_DATAGRAMS: u32 = 40;
/// Unreadable datagrams in a row that end the session: past this it is a wrong key or a broken link, not noise.
const BAD_RUN_LIMIT: u32 = 50;

/// The sub-packets' ids and syncs, for the log.
fn sub_ids(plain: &[u8]) -> String {
    let mut out = Vec::new();
    let mut at = 0;
    while at + 4 <= plain.len() {
        let word = u16::from_le_bytes([plain[at], plain[at + 1]]);
        let len = ((word >> 9) as usize) * 4;
        if len == 0 {
            break;
        }
        out.push(format!("{:03X}/{}", word & 0x1ff, u16::from_le_bytes([plain[at + 2], plain[at + 3]])));
        at += len;
    }
    out.join(" ")
}

/// FUN_100dc430: the socket binds to 54090, then 50 more tries 0x100 apart (a u16, so it wraps), at every connection; a
/// zone change comes from the same port, which LSB's older map servers key the session by.
fn bind_socket() -> Result<UdpSocket> {
    let mut port = 54090u16;
    for _ in 0..=50 {
        if let Ok(s) = UdpSocket::bind(("0.0.0.0", port)) {
            return Ok(s);
        }
        port = port.wrapping_add(0x100);
    }
    bail!("no local UDP port for the zone server: 54090 and the 50 after it 256 apart are all taken")
}

/// FUN_100fdd40's raw limit: the build stops before the header and sub-packets pass 3999 bytes.
const MAX_PAYLOAD: usize = 3999 - HEADER;
/// FUN_100fab40 hands FUN_100dd590 a 0x550-byte buffer: a datagram that would be larger is not sent. FUN_100dc670
/// reads into as many, so a larger one is never read either.
const MAX_DATAGRAM: usize = 0x550;
/// FUN_100dd6c0 refuses a datagram under 0x2d bytes: the header, one byte, the MD5.
const MIN_DATAGRAM: usize = 0x2d;
/// The compressed size field (payload bits + 8) that still fits MAX_DATAGRAM with the header, the field and the MD5.
const MAX_BITS: u32 = ((MAX_DATAGRAM - HEADER - 4 - 16) * 8) as u32;
/// The room FUN_100dd590 gives the compressor (FUN_100df7c0): the datagram less the header and the MD5. The size
/// field's 4 bytes are not taken off, so the last 4 bytes of it can be filled but not sent.
const ROOM: usize = MAX_DATAGRAM - HEADER - 16;
/// The most sub-packet bytes the plain form carries: its leading byte, the field and the MD5 still fit MAX_DATAGRAM.
const MAX_PLAIN: usize = MAX_DATAGRAM - HEADER - 1 - 4 - 16;

/// Whether FUN_100dd590 makes a datagram of `raw` sub-packet bytes whose codes are `bits` long: compressed while the
/// size field fits, plain once the codes reach the compressor's room (FUN_100df7c0) and the bytes fit. Between the
/// two (the room's last 4 bytes) it makes none.
fn sendable(raw: usize, bits: u32) -> bool {
    bits + 8 <= MAX_BITS || (bits as usize >= (ROOM - 1) * 8 && raw <= MAX_PLAIN)
}

/// FUN_100fab40 (0x100fad1c): the sequence after `seq`; it steps over 0, which marks a sub-packet not sent yet.
fn seq_after(seq: u16) -> u16 {
    match seq.wrapping_add(1) {
        0 => 1,
        n => n,
    }
}

impl MapSession {
    pub fn connect(server: SocketAddr, key: &[u8; 20], codec: Codec) -> Result<Self> {
        let sock = bind_socket()?;
        sock.connect(server)?;
        log::info!("map: {server} from local port {}", sock.local_addr()?.port());
        Ok(Self {
            sock,
            cipher: Blowfish::for_session_key(key),
            key: super::blowfish::session_key(key),
            key20: *key,
            alt: None,
            codec,
            seq: 0,
            server_seq: 0,
            bytes_out: 0,
            bytes_in: 0,
            bad_in: 0,
            bad_run: 0,
            unacked: Vec::new(),
            drop: (std::env::var("FFXI_NET_DROP").ok().and_then(|v| v.parse().ok()).unwrap_or(0), now() | 1),
            server_ack: 0,
            last_in: None,
            logged: (0, 0),
            cert: None,
            clock: None,
        })
    }

    /// Also tries `alt` until a datagram has been read.
    pub fn or_key(mut self, alt: Option<[u8; 20]>) -> Self {
        self.alt = alt.map(|k| (Blowfish::for_session_key(&k), k));
        self
    }

    /// The 20 bytes behind the cipher in use, stepped by the caller for the next zone.
    pub fn key20(&self) -> [u8; 20] {
        self.key20
    }

    /// @0 our sequence, @2 the last server datagram handled, @4 / @8 the clock's ms and seconds; after the zone-in
    /// @0x0C = 1 and the zone-in's two words @0x10 / @0x14 (FUN_100fa9f0, FUN_100fdbf0).
    fn header(&mut self) -> Vec<u8> {
        self.seq = seq_after(self.seq);
        let mut h = vec![0u8; HEADER];
        h[..2].copy_from_slice(&self.seq.to_le_bytes());
        h[2..4].copy_from_slice(&self.server_seq.to_le_bytes());
        let (secs, ms) = match self.clock {
            Some((s, m, at)) => {
                let t = m as u64 + at.elapsed().as_millis() as u64;
                (s.wrapping_add((t / 1000) as u32), (t % 1000) as u32)
            }
            None => (now(), 0),
        };
        h[4..8].copy_from_slice(&ms.to_le_bytes());
        h[8..12].copy_from_slice(&secs.to_le_bytes());
        h
    }

    /// The zone-in (s2c 0x00A, LAB_100facf0): its two words for every later header, its clock (@0x38 seconds, @0x34
    /// ms, FUN_100dc150).
    pub fn zoned_in(&mut self, p: &SubPacket) {
        self.cert = Some([p.u32(0x94), p.u32(0x98)]);
        self.clock = Some((p.u32(0x38), p.u32(0x34), std::time::Instant::now()));
        log::info!("map: zone-in, header words {:08x} {:08x}", p.u32(0x94), p.u32(0x98));
    }

    fn stamp(&self, packets: &[Vec<u8>]) -> Vec<u8> {
        let mut body = Vec::new();
        for p in packets {
            let mut p = p.clone();
            p[2..4].copy_from_slice(&self.seq.to_le_bytes());
            body.extend_from_slice(&p);
        }
        body
    }

    /// The opening 0x00A goes out unencrypted and uncompressed; `attempt` @6 is DAT_104df920: 0 at first, then 2, or 3
    /// once a datagram was read (FUN_100fa940).
    pub fn send_login(&mut self, char_id: u32, char_name: &str, account: &str, attempt: u16) -> Result<()> {
        let mut body = vec![0u8; 88];
        body[2..4].copy_from_slice(&attempt.to_le_bytes());
        body[8..12].copy_from_slice(&char_id.to_le_bytes());
        let put = |b: &mut [u8], at: usize, s: &str| {
            let s = &s.as_bytes()[..s.len().min(14)];
            b[at..at + s.len()].copy_from_slice(s);
        };
        put(&mut body, 30, char_name);
        put(&mut body, 45, account);
        // The ticket @0x40: MD5(the account's 15 bytes ‖ the Blowfish key) (FUN_100fba40 -> FUN_100dd800).
        let mut h = Md5::new();
        h.update(&body[45..60]);
        h.update(self.key);
        body[60..76].copy_from_slice(&h.finalize());
        body[80..84].copy_from_slice(b"WIN\0");
        // The language (FFXi.dll's map of polcore 0x1A5: 0 ja, 1 en, 2 de, 3 fr), then SYS\info02.bin's
        // {01 01} after a normal start (FUN_102532c0).
        body[84..86].copy_from_slice(&1u16.to_le_bytes());
        body[86..88].copy_from_slice(&0x0101u16.to_le_bytes());
        // LoginPacketCheck: byte sum of everything from MyIP (packet offset 8) on.
        body[0] = body[4..].iter().fold(0u8, |a, &b| a.wrapping_add(b));
        let packet = build(0x00A, &body);

        let mut dgram = self.header();
        dgram.extend_from_slice(&self.stamp(&[packet]));
        log::info!("map out (login): header {} [{}]", hex::encode(&dgram[..HEADER]), sub_ids(&dgram[HEADER..]));
        let digest = Md5::digest(&dgram[HEADER..]);
        dgram.extend_from_slice(&digest);
        self.sock.send(&dgram)?;
        Ok(())
    }

    /// FUN_100fab40's lag measure (0x100fab59): the sequence the next datagram will carry (+6) less the last of ours
    /// the server acknowledged (+0xA, its header u16 @2), both as plain u16 values (no wrap handling, as retail).
    pub fn lag(&self) -> i32 {
        seq_after(self.seq) as i32 - self.server_ack as i32
    }

    /// Sub-packets sent and not acknowledged yet (they hold their queue slots in retail), without the position.
    pub fn pending(&self) -> usize {
        self.unacked.iter().filter(|(_, p)| u16::from_le_bytes([p[0], p[1]]) & 0x1ff != 0x015).count()
    }

    /// One datagram: the new sub-packets plus every earlier one the server has not acked; a new 0x015 replaces
    /// a queued one (retail rewrites its single 0x015 slot).
    pub fn send(&mut self, packets: &[Vec<u8>]) -> Result<()> {
        self.send_slots(packets, false)
    }

    /// The session's last datagram (0x00D before a zone change or logout): no later one carries what waits, so
    /// `packets` always go and older slots are left out when the datagram would be too large.
    pub fn send_last(&mut self, packets: &[Vec<u8>]) -> Result<()> {
        self.send_slots(packets, true)
    }

    fn send_slots(&mut self, packets: &[Vec<u8>], last: bool) -> Result<()> {
        let mut dgram = self.header();
        let (seq, ack) = (self.seq, self.server_ack);
        // FUN_100fdd40: a slot goes while its sync is 0 (not sent yet) or the server's ack has not reached it.
        self.unacked.retain(|(s, _)| *s == 0 || ack.wrapping_sub(*s) >= 0x8000);
        let id = |p: &[u8]| u16::from_le_bytes([p[0], p[1]]) & 0x1ff;
        if packets.iter().any(|p| id(p) == 0x015) {
            self.unacked.retain(|(_, p)| id(p) != 0x015);
        }
        let mut older = self.unacked.len();
        self.unacked.extend(packets.iter().map(|p| (0, p.clone())));
        // A sub-packet takes the sequence of the first datagram that carries it; one left out is stamped again.
        for (sync, p) in &mut self.unacked {
            if *sync == 0 {
                p[2..4].copy_from_slice(&seq.to_le_bytes());
            }
        }
        // Retail never sends a slot too large for any datagram (FUN_100dd590 returns -1 each time); ours drops it.
        let (codec, n) = (&self.codec, older);
        let mut at = 0;
        self.unacked.retain(|(s, p)| {
            let keep = *s != 0 || sendable(p.len(), codec.bits(p));
            if !keep {
                log::warn!("map out: c2s {:#05x} dropped: it alone fits no {MAX_DATAGRAM:#x}-byte datagram", id(p));
                older -= (at < n) as usize;
            }
            at += 1;
            keep
        });
        if let Some([a, b]) = self.cert {
            dgram[0x0C] = 1;
            dgram[0x10..0x14].copy_from_slice(&a.to_le_bytes());
            dgram[0x14..0x18].copy_from_slice(&b.to_le_bytes());
        }
        let picked = self.pick(if last { older } else { self.unacked.len() });
        let mut raw = Vec::new();
        for &i in &picked {
            raw.extend_from_slice(&self.unacked[i].1);
        }
        // `pick` only takes what FUN_100dd590 sends; retail sends nothing when the coder fails.
        let fits = |(body, _): &(Vec<u8>, u32)| HEADER + body.len() + 4 + 16 <= MAX_DATAGRAM;
        let Some((mut body, bits)) = self.codec.pack(&raw, ROOM).filter(fits) else {
            log::warn!("map out: {} sub-packet bytes fit no datagram", raw.len());
            return Ok(());
        };
        body.extend_from_slice(&bits.to_le_bytes());
        for &i in &picked {
            if self.unacked[i].0 == 0 {
                self.unacked[i].0 = seq;
            }
        }
        let left = self.unacked.len() - picked.len();
        if left > 0 && last {
            log::warn!("map out: {left} sub-packets left out of the session's last datagram (size limit)");
        } else if left > 0 {
            log::warn!("map out: {left} sub-packets wait for the next datagram (size limit)");
        }
        if self.logged.1 < LOG_DATAGRAMS {
            self.logged.1 += 1;
            log::info!("map out: header {} [{}]", hex::encode(&dgram[..HEADER]), sub_ids(&raw));
        }
        let digest = Md5::digest(&body);
        body.extend_from_slice(&digest);
        self.cipher.encrypt(&mut body);
        dgram.extend_from_slice(&body);
        self.sock.send(&dgram)?;
        self.bytes_out += dgram.len() as u64;
        Ok(())
    }

    /// The slots a datagram carries, in order: the oldest while the raw size fits and the coder takes them, after room for
    /// every slot from `kept` on (when those fit together). Retail drops an oversized datagram whole and builds the
    /// same one again; ours leaves the newest out for the next one, so the oldest still go.
    fn pick(&self, kept: usize) -> Vec<usize> {
        let cost = |i: usize| (self.unacked[i].1.len(), self.codec.bits(&self.unacked[i].1));
        let fit = |(size, bits): (usize, u32), (s, b): (usize, u32)| {
            (size + s <= MAX_PAYLOAD && sendable(size + s, bits + b)).then_some((size + s, bits + b))
        };
        // Only the whole reserved batch has to be sendable: a prefix of it may sit in the size gap.
        let total = (kept..self.unacked.len()).map(cost).fold((0, 0), |a, c| (a.0 + c.0, a.1 + c.1));
        let tail = (total.0 <= MAX_PAYLOAD && sendable(total.0, total.1)).then_some(total);
        let (kept, mut at) = match tail {
            Some(at) => (kept, at),
            None => (self.unacked.len(), (0, 0)),
        };
        let mut out = Vec::new();
        for i in 0..kept {
            match fit(at, cost(i)) {
                Some(next) => at = next,
                None => break,
            }
            out.push(i);
        }
        out.extend(kept..self.unacked.len());
        out
    }

    /// Drops a datagram that can't be read: counted, logged (the first few), and an error only after BAD_RUN_LIMIT in a
    /// row.
    fn bad_datagram(&mut self, n: usize, why: &str) -> Result<Option<Vec<SubPacket>>> {
        self.bad_in += 1;
        self.bad_run += 1;
        if self.bad_in <= LOG_DATAGRAMS as u64 {
            log::warn!("map in: dropped a {n}-byte datagram that {why}");
        }
        if self.bad_run >= BAD_RUN_LIMIT {
            bail!("{BAD_RUN_LIMIT} datagrams in a row could not be read; the last {why}");
        }
        Ok(None)
    }

    /// Waits for one datagram and unpacks its sub-packets.
    pub fn recv(&mut self, timeout: Duration) -> Result<Option<Vec<SubPacket>>> {
        self.sock.set_read_timeout(Some(timeout))?;
        let mut buf = vec![0u8; 4096];
        let n = match self.sock.recv(&mut buf) {
            Ok(n) => n,
            Err(e) if matches!(e.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut) => {
                return Ok(None);
            }
            // Windows fails the read of a datagram longer than the buffer (WSAEMSGSIZE), as retail's does.
            Err(e) if e.raw_os_error() == Some(10040) => return Ok(None),
            Err(e) => return Err(e.into()),
        };
        // FUN_100dd6c0 reads 0x2d..=0x550 bytes; FUN_100dc670's read fails on more. LSB sends an empty datagram when
        // nothing is queued (send_parse sets the size to 0): it is too short, so it counts as no answer and the login
        // keeps retrying.
        if !(MIN_DATAGRAM..=MAX_DATAGRAM).contains(&n) {
            log::debug!("dropped a {n}-byte datagram");
            return Ok(None);
        }
        let mut dgram = buf[..n].to_vec();
        self.cipher.decrypt(&mut dgram[HEADER..]);
        let sealed = |d: &[u8]| {
            let (data, digest) = d[HEADER..].split_at(d.len() - HEADER - 16);
            Md5::digest(data).as_slice() == digest
        };
        if !sealed(&dgram)
            && self.last_in.is_none()
            && let Some((cipher, _)) = &self.alt
        {
            let mut again = buf[..n].to_vec();
            cipher.decrypt(&mut again[HEADER..]);
            if sealed(&again) {
                log::info!("map: the server keys this session with the loader's zero value (LSB's older login)");
                let (cipher, k) = self.alt.take().unwrap();
                (self.cipher, self.key, self.key20, dgram) = (cipher, super::blowfish::session_key(&k), k, again);
            }
        }
        // A datagram that fails its checksum or doesn't decompress (corrupt, cut short, not the server's) is dropped
        // and counts as no answer; LSB resends what we haven't acked. Only a run of them ends the session.
        if !sealed(&dgram) {
            return self.bad_datagram(n, "failed its checksum (wrong session key?)");
        }
        // FUN_100dd6c0 takes the size field from the 4 bytes before the MD5 wherever they fall (in the header for a
        // datagram under 48 bytes) and hands the compressor everything after the header.
        let bits = u32::from_le_bytes(dgram[n - 20..n - 16].try_into().unwrap());
        let plain = match self.codec.decompress(&dgram[HEADER..n - 16], bits) {
            Ok(p) => p,
            Err(e) => return self.bad_datagram(n, &format!("did not decompress: {e:#}")),
        };
        self.bad_run = 0;
        // FUN_100f76b0 counts a datagram's bytes (FUN_100f9b90) only once FUN_100dad80 has read it.
        self.bytes_in += n as u64;
        if self.drop.0 > 0 {
            self.drop.1 = self.drop.1.wrapping_mul(1_103_515_245).wrapping_add(12345);
            if (self.drop.1 >> 16) % 100 < self.drop.0 {
                log::debug!("map in: datagram thrown away (FFXI_NET_DROP)");
                return Ok(None);
            }
        }
        // FUN_100f76b0: a datagram not newer than the last one handled is dropped (counted), and so is a sub-packet
        // whose sync is not newer; only an accepted datagram moves the stored sequence and ack.
        let seq = u16::from_le_bytes([dgram[0], dgram[1]]);
        if self.logged.0 < LOG_DATAGRAMS {
            self.logged.0 += 1;
            log::info!("map in: header {} [{}]", hex::encode(&dgram[..HEADER]), sub_ids(&plain));
        }
        let newer = |s: u16| self.last_in.is_none_or(|last| last.wrapping_sub(s) >= 0x8000);
        if !newer(seq) {
            // LSB resends its last datagram when our ack lags (map_networking.cpp parse).
            log::debug!("dropped resent datagram {seq}");
            return Ok(Some(Vec::new()));
        }

        let mut out = Vec::new();
        let mut at = 0;
        while at + 4 <= plain.len() {
            let word = u16::from_le_bytes([plain[at], plain[at + 1]]);
            let len = ((word >> 9) as usize) * 4;
            if len == 0 || at + len > plain.len() {
                break;
            }
            let sync = u16::from_le_bytes([plain[at + 2], plain[at + 3]]);
            if newer(sync) {
                out.push(SubPacket { id: word & 0x1FF, sync, data: plain[at..at + len].to_vec() });
            }
            at += len;
        }
        self.server_seq = seq;
        self.server_ack = u16::from_le_bytes([dgram[2], dgram[3]]);
        self.last_in = Some(seq);
        // Every 30th datagram re-syncs the clock to the server's header (FUN_100fbd10; ours without the drift limit).
        if seq.is_multiple_of(30) && self.clock.is_some() {
            let at = |o: usize| u32::from_le_bytes(dgram[o..o + 4].try_into().unwrap());
            self.clock = Some((at(8), at(4), std::time::Instant::now()));
        }
        Ok(Some(out))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The sequence steps over 0, and the lag is the next sequence less the server's ack.
    #[test]
    fn sequence_and_lag() {
        assert_eq!((seq_after(0), seq_after(1), seq_after(0xFFFE), seq_after(0xFFFF)), (1, 2, 0xFFFF, 1));
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        let mut s = MapSession::connect(server.local_addr().unwrap(), &[7; 20], plain_codec()).unwrap();
        // Nothing sent: the first datagram will be 1, nothing acknowledged.
        assert_eq!(s.lag(), 1);
        s.send(&[build(0x0DD, &[0; 12]), build(0x015, &[0; 28])]).unwrap();
        assert_eq!((s.seq, s.lag(), s.pending()), (1, 2, 1));
        assert!(s.unacked.iter().all(|(sync, p)| *sync == 1 && p[2..4] == [1, 0]));
        s.server_ack = 1;
        assert_eq!(s.lag(), 1);
        s.send(&[build(0x015, &[0; 28])]).unwrap();
        assert_eq!((s.seq, s.pending(), s.unacked.len()), (2, 0, 1));
    }

    /// No datagram passes 0x550 bytes: the newest slots wait unsent, the last datagram keeps the packets given over
    /// older ones, and a slot no datagram can hold is dropped.
    #[test]
    fn datagram_size_limit() {
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        let mut s = MapSession::connect(server.local_addr().unwrap(), &[7; 20], plain_codec()).unwrap();
        // Plain codes: six 200-byte slots fit (8 + 6 x 1600 bits), the seventh does not.
        let slots: Vec<_> = (0..10u8).map(|k| build(0x0DD, &[k; 196])).collect();
        s.send(&slots).unwrap();
        assert!(s.bytes_out as usize <= MAX_DATAGRAM);
        assert_eq!(s.unacked.iter().map(|(sync, _)| *sync).collect::<Vec<_>>(), [1, 1, 1, 1, 1, 1, 0, 0, 0, 0]);
        let mut buf = [0u8; 4096];
        assert_eq!(server.recv(&mut buf).unwrap(), s.bytes_out as usize);
        s.send_last(&[build(0x00D, &[0; 4])]).unwrap();
        let (sync, p) = s.unacked.last().unwrap();
        assert_eq!((*sync, p[0]), (2, 0x0D));
        assert_eq!(s.unacked[6].0, 0);
        assert!(server.recv(&mut buf).unwrap() <= MAX_DATAGRAM);
        // 400 bytes whose codes are 10496 bits: past the size field's limit and short of the plain form's start, so no
        // datagram holds it.
        let gap = [vec![0xFFu8; 304], vec![0u8; 92]].concat();
        let mut s = MapSession::connect(server.local_addr().unwrap(), &[7; 20], long_codec()).unwrap();
        assert_eq!(s.codec.bits(&build(0x0DD, &gap)), 10496);
        s.send(&[build(0x0DD, &gap), build(0x0DD, &[0; 12])]).unwrap();
        assert_eq!(s.unacked.iter().map(|(sync, p)| (*sync, p.len())).collect::<Vec<_>>(), [(1, 16)]);
        assert!(server.recv(&mut buf).unwrap() <= MAX_DATAGRAM);
    }

    /// The last datagram's reserved batch goes when the whole batch is sendable, even if a prefix of it sits in the size
    /// gap (the two-slot prefix here is 10496 bits).
    #[test]
    fn send_last_batch_past_gap_prefix() {
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        let mut s = MapSession::connect(server.local_addr().unwrap(), &[7; 20], long_codec()).unwrap();
        let old: Vec<_> = (0..6).map(|_| build(0x0DD, &[0; 196])).collect();
        s.send(&old).unwrap();
        let big = || build(0x0DD, &[vec![0xFFu8; 152], vec![0u8; 44]].concat());
        let batch = [big(), big(), build(0x0DD, &[0; 12])];
        s.send_last(&batch).unwrap();
        let new = &s.unacked[s.unacked.len() - 3..];
        assert!(new.iter().all(|(sync, _)| *sync != 0), "{:?}", s.unacked.iter().map(|u| u.0).collect::<Vec<_>>());
    }

    /// FUN_100dd590's limits: compressed up to a 10488-bit payload, nothing from there to 10519, plain from 10520
    /// while the bytes fit.
    #[test]
    fn sendable_forms() {
        assert!(sendable(3000, 10488) && !sendable(100, 10489) && !sendable(100, 10519));
        assert!(sendable(1311, 10520) && !sendable(1312, 10520));
    }

    /// Sub-packets whose codes pass the compressor's room go plain behind a 0 byte, and are read back the same way.
    #[test]
    fn plain_form_both_ways() {
        let key = [7u8; 20];
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        let mut s = MapSession::connect(server.local_addr().unwrap(), &key, long_codec()).unwrap();
        // 504 bytes of 32-bit codes: 16128 bits.
        let slot = build(0x0DD, &[0xFF; 500]);
        s.send(std::slice::from_ref(&slot)).unwrap();
        let mut buf = [0u8; 4096];
        let (n, from) = server.recv_from(&mut buf).unwrap();
        assert_eq!(n, HEADER + 1 + 504 + 4 + 16);
        let cipher = Blowfish::for_session_key(&key);
        cipher.decrypt(&mut buf[HEADER..n]);
        let body = &buf[HEADER..n - 20];
        assert_eq!((body[0], &body[5..], &buf[n - 20..n - 16]), (0, &slot[4..], &(505u32 * 8).to_le_bytes()[..]));
        assert_eq!(Md5::digest(&buf[HEADER..n - 16]).as_slice(), &buf[n - 16..n]);
        // The same bytes back, as the server's datagram 1.
        buf[..2].copy_from_slice(&1u16.to_le_bytes());
        cipher.encrypt(&mut buf[HEADER..n]);
        server.send_to(&buf[..n], from).unwrap();
        let got = s.recv(Duration::from_secs(1)).unwrap().unwrap();
        assert_eq!((got.len(), got[0].id, got[0].data.len()), (1, 0x0DD, 504));
    }

    /// FUN_100dd6c0 reads a datagram of 0x2d..=0x550 bytes; the size field sits 20 bytes from the end even when that
    /// is inside the header.
    #[test]
    fn datagram_size_bounds() {
        let key = [7u8; 20];
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        let mut s = MapSession::connect(server.local_addr().unwrap(), &key, plain_codec()).unwrap();
        let to = s.sock.local_addr().unwrap();
        let cipher = Blowfish::for_session_key(&key);
        let t = Duration::from_secs(1);
        // 45 bytes: one body byte, a 0 (the plain form), which is also the top byte of the field at 25..29: 8 bits,
        // so no sub-packets.
        let mut d = vec![0u8; MIN_DATAGRAM];
        d[0] = 1;
        d[25..29].copy_from_slice(&8u32.to_le_bytes());
        let digest = Md5::digest(&d[HEADER..HEADER + 1]);
        d[HEADER + 1..].copy_from_slice(&digest);
        cipher.encrypt(&mut d[HEADER..]);
        server.send_to(&d, to).unwrap();
        server.send_to(&d[..MIN_DATAGRAM - 1], to).unwrap();
        server.send_to(&vec![0u8; MAX_DATAGRAM + 1], to).unwrap();
        assert_eq!(s.recv(t).unwrap().map(|p| p.len()), Some(0));
        assert!(s.recv(t).unwrap().is_none() && s.recv(t).unwrap().is_none());
        assert_eq!((s.server_seq, s.bad_in), (1, 0));
    }

    /// Set FFXI_MAIN_DLL to run: a resent datagram (same header sequence) and an older one carry nothing.
    #[test]
    fn resent_datagram_dropped() {
        let Ok(dll) = std::env::var("FFXI_MAIN_DLL") else { return };
        let codec = Codec::from_ffximain(&std::fs::read(dll).unwrap()).unwrap();
        let key = [7u8; 20];
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        let mut s = MapSession::connect(server.local_addr().unwrap(), &key, codec.clone()).unwrap();
        let cipher = Blowfish::for_session_key(&key);
        let dgram = |seq: u16| {
            let mut sub = build(0x029, &[0u8; 24]);
            sub[2..4].copy_from_slice(&seq.to_le_bytes());
            let (mut body, bits) = codec.compress(&sub);
            body.extend_from_slice(&bits.to_le_bytes());
            let digest = Md5::digest(&body);
            body.extend_from_slice(&digest);
            cipher.encrypt(&mut body);
            let mut d = vec![0u8; HEADER];
            d[..2].copy_from_slice(&seq.to_le_bytes());
            d.extend_from_slice(&body);
            d
        };
        let to = s.sock.local_addr().unwrap();
        for seq in [5, 5, 4, 6] {
            server.send_to(&dgram(seq), to).unwrap();
        }
        let got: Vec<usize> = (0..4).map(|_| s.recv(Duration::from_secs(1)).unwrap().unwrap().len()).collect();
        assert_eq!(got, [1, 0, 0, 1]);
        assert_eq!(s.server_seq, 6);
    }

    /// A codec of plain 8-bit codes (each byte its code), so the test needs no FFXiMain.dll.
    fn plain_codec() -> Codec {
        let mut table = vec![0u8; 2048];
        for b in 0..=255u8 {
            let i = (b as i8 as i32 + 0x80) as usize;
            table[i * 4..i * 4 + 4].copy_from_slice(&(b as u32).to_le_bytes());
            table[(i + 0x100) * 4..(i + 0x100) * 4 + 4].copy_from_slice(&8u32.to_le_bytes());
        }
        Codec::from_table(&table).unwrap()
    }

    /// Plain codes but 0xFE and 0xFF, which take 32 bits (their byte, then 24 zero bits).
    fn long_codec() -> Codec {
        let mut table = vec![0u8; 2048];
        for b in 0..=255u8 {
            let i = (b as i8 as i32 + 0x80) as usize;
            table[i * 4..i * 4 + 4].copy_from_slice(&(b as u32).to_le_bytes());
            let len = if b >= 0xFE { 32u32 } else { 8 };
            table[(i + 0x100) * 4..(i + 0x100) * 4 + 4].copy_from_slice(&len.to_le_bytes());
        }
        Codec::from_table(&table).unwrap()
    }

    /// A datagram that fails its checksum or doesn't decompress is dropped, not the session; a run of them ends it.
    #[test]
    fn bad_datagram_dropped() {
        let codec = plain_codec();
        let key = [7u8; 20];
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        let mut s = MapSession::connect(server.local_addr().unwrap(), &key, codec.clone()).unwrap();
        let cipher = Blowfish::for_session_key(&key);
        // `body` sealed (bits, MD5) and encrypted behind a header with `seq`.
        let seal = |seq: u16, mut body: Vec<u8>, bits: u32| {
            body.extend_from_slice(&bits.to_le_bytes());
            let digest = Md5::digest(&body);
            body.extend_from_slice(&digest);
            cipher.encrypt(&mut body);
            let mut d = vec![0u8; HEADER];
            d[..2].copy_from_slice(&seq.to_le_bytes());
            d.extend_from_slice(&body);
            d
        };
        let good = |seq: u16| {
            let mut sub = build(0x029, &[0u8; 24]);
            sub[2..4].copy_from_slice(&seq.to_le_bytes());
            let (body, bits) = codec.compress(&sub);
            seal(seq, body, bits)
        };
        let to = s.sock.local_addr().unwrap();
        let mut corrupt = good(5);
        corrupt[HEADER + 3] ^= 0x40;
        // Passes its checksum but its size field is under the leading byte's 8 bits.
        let undecodable = seal(5, vec![1u8; 24], 7);
        for d in [&corrupt, &undecodable, &good(5)] {
            server.send_to(d, to).unwrap();
        }
        let t = Duration::from_secs(1);
        assert!(s.recv(t).unwrap().is_none());
        assert!(s.recv(t).unwrap().is_none());
        assert_eq!(s.recv(t).unwrap().unwrap().len(), 1);
        assert_eq!((s.server_seq, s.bad_in), (5, 2));
        // A good datagram resets the run: BAD_RUN_LIMIT - 1 more are still dropped, the next one ends it.
        for _ in 0..BAD_RUN_LIMIT - 1 {
            server.send_to(&corrupt, to).unwrap();
            assert!(s.recv(t).unwrap().is_none());
        }
        server.send_to(&corrupt, to).unwrap();
        assert!(s.recv(t).is_err());
    }

    /// The older key is taken when the first datagram passes only with it, and never once a datagram was read.
    #[test]
    fn old_key_taken_before_the_first_read() {
        let codec = plain_codec();
        let (ours, old) = ([7u8; 20], [0u8; 20]);
        let dgram = |key: &[u8; 20], seq: u16| {
            let mut sub = build(0x029, &[0u8; 24]);
            sub[2..4].copy_from_slice(&seq.to_le_bytes());
            let (mut body, bits) = codec.compress(&sub);
            body.extend_from_slice(&bits.to_le_bytes());
            let digest = Md5::digest(&body);
            body.extend_from_slice(&digest);
            Blowfish::for_session_key(key).encrypt(&mut body);
            let mut d = vec![0u8; HEADER];
            d[..2].copy_from_slice(&seq.to_le_bytes());
            d.extend_from_slice(&body);
            d
        };
        let t = Duration::from_secs(1);
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        let mut s = MapSession::connect(server.local_addr().unwrap(), &ours, codec.clone()).unwrap().or_key(Some(old));
        let to = s.sock.local_addr().unwrap();
        server.send_to(&dgram(&old, 1), to).unwrap();
        assert_eq!(s.recv(t).unwrap().unwrap().len(), 1);
        assert_eq!((s.key20(), s.key), (old, crate::net::map::blowfish::session_key(&old)));
        server.send_to(&dgram(&ours, 2), to).unwrap();
        assert!(s.recv(t).unwrap().is_none());
        // Ours read first: the older key is never tried after it.
        let mut s = MapSession::connect(server.local_addr().unwrap(), &ours, codec.clone()).unwrap().or_key(Some(old));
        let to = s.sock.local_addr().unwrap();
        server.send_to(&dgram(&ours, 1), to).unwrap();
        server.send_to(&dgram(&old, 2), to).unwrap();
        assert_eq!(s.recv(t).unwrap().unwrap().len(), 1);
        assert!(s.recv(t).unwrap().is_none());
        assert_eq!(s.key20(), ours);
    }
}
