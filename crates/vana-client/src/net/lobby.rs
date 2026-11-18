//! The lobby: FFXiMain's view link (TCP 54001), as the game builds it (FUN_10116610), in two dialects.
//! LSB (xi_connect): a session hash in each header, plus the data link (TCP 54230) that xiloader speaks there.
//! PlayOnline (FFXiMain's `-net 3` path): one link, an MD5 of the packet in each header, the session from net/pol.

use anyhow::{Context, Result, bail};
use md5::{Digest, Md5};
use std::collections::VecDeque;
use std::io::{Read, Write};
use std::net::{Ipv4Addr, TcpStream};
use std::sync::Arc;
use std::sync::atomic::{AtomicU8, AtomicU32, Ordering};
use std::time::Duration;

const MAGIC: &[u8; 4] = b"IXFF";
const NAME_LEN: usize = 16;
const CHAR_INFO_LEN: usize = 140;
/// FFXiMain's largest accepted reply (FUN_1026be74).
const MAX_REPLY: usize = 0xB68;

/// Who vouches for the lobby session.
#[derive(Clone)]
pub enum Session {
    /// xi_connect's login (net/auth.rs): the account id and session hash, and the key the lobby's TLS ports must
    /// hold (LSB for xiloader 3.0 and later; none: the older plain lobby).
    Lsb { account_id: u32, hash: [u8; 16], lobby_key: Option<super::tls::Fingerprint> },
    /// A PlayOnline sign-in: polcore's authCode (table 0x3A8) and 16-byte value (0x3EB).
    PlayOnline { auth_code: [u8; 64], k16: [u8; 16] },
}

impl Session {
    /// The 16 bytes the key fields and the map key hash: polcore's value; on LSB xi_profile gives polcore MD5(hash).
    fn k16(&self) -> [u8; 16] {
        match self {
            Session::Lsb { hash, .. } => Md5::digest(hash).into(),
            Session::PlayOnline { k16, .. } => *k16,
        }
    }

    fn auth_code(&self) -> [u8; 64] {
        match self {
            Session::Lsb { .. } => [0; 64],
            Session::PlayOnline { auth_code, .. } => *auth_code,
        }
    }
}

/// FUN_100185a0 over FFXiMain.dll (period 0x13): each signed byte shifted left by 4 * (i mod 20), summed. 0x07 sends it.
pub fn ffximain_checksum(dll: &[u8]) -> u32 {
    dll.iter().enumerate().fold(0u32, |s, (i, &b)| s.wrapping_add(((b as i8 as i32) << (((i % 20) * 4) & 31)) as u32))
}

#[derive(Clone, Debug)]
pub struct Character {
    pub content_id: u32,
    pub name: String,
    pub world: String,
    /// 0 hidden, 1 available, 2 disabled.
    pub status: u16,
    pub rename_required: bool,
    pub race: u16,
    pub main_job: u8,
    pub main_level: u8,
    pub sub_job: u8,
    pub face: u16,
    pub nation: u8,
    pub size: u8,
    pub zone: u16,
    /// face, head, body, hands, legs, feet, main, sub
    pub looks: [u16; 8],
}

impl Character {
    pub fn is_empty_slot(&self) -> bool {
        self.name.trim().is_empty()
    }
}

#[derive(Clone, Debug)]
pub struct MapLogin {
    pub char_id: u32,
    pub name: String,
    pub map: (Ipv4Addr, u16),
    pub search: (Ipv4Addr, u16),
    /// The 16-byte value and the key counter at world entry; the map's Blowfish key is their MD5.
    pub key: [u8; 20],
    /// LSB: the same counter behind xiloader's zero value, as LSB keyed the map before it took the profile's value;
    /// tried when the first datagrams fail with `key`.
    pub old_key: Option<[u8; 20]>,
    /// The LSB login's account id and session hash (xi_profile's credentials); none for PlayOnline.
    pub lsb: Option<(u32, [u8; 16])>,
    /// PlayOnline: the chat link, kept open while the game runs (held for its Drop, never read).
    #[allow(dead_code)]
    pub pol: Option<Arc<super::pol::Link>>,
}

/// The creator's choices for 0x21's make block (the 0x20 record's +0x2C).
pub struct NewCharacter {
    pub race: u8,
    pub face: u8,
    pub size: u8,
    pub job: u8,
    pub nation: u8,
}

fn rd_u16(b: &[u8], o: usize) -> u16 {
    u16::from_le_bytes([b[o], b[o + 1]])
}
fn rd_u32(b: &[u8], o: usize) -> u32 {
    u32::from_le_bytes(b[o..o + 4].try_into().unwrap())
}
fn rd_name(b: &[u8]) -> String {
    let end = b.iter().position(|&c| c == 0).unwrap_or(b.len());
    String::from_utf8_lossy(&b[..end]).into_owned()
}
fn put(b: &mut [u8], at: usize, v: &[u8]) {
    b[at..at + v.len()].copy_from_slice(v);
}
/// A name field: 15 bytes and a NUL.
fn put_name(b: &mut [u8], at: usize, s: &str) {
    let s = s.as_bytes();
    put(b, at, &s[..s.len().min(NAME_LEN - 1)]);
}

pub fn error_text(code: u16) -> &'static str {
    match code {
        201 => "That character is already logged in. Wait a few minutes before reconnecting.",
        208 => "The world server is congested.",
        305 => "Unable to connect to the world server.",
        313 => "That character name is unavailable.",
        314 => "Failed to register with the name server.",
        316 => "Incorrect World Pass.",
        317 => "World Pass expired.",
        321 => "The character's parameters are incorrect.",
        331 => "The game data has been updated (client version rejected).",
        332 => "Could not connect to the lobby server.",
        339 => "A Gold World Pass is valid for your first character only.",
        _ => "Lobby error.",
    }
}

/// A lobby refusal (view 0x04): retail shows it as FFXI-3000 + code.
#[derive(Debug)]
pub struct Refused(pub u16);

impl std::fmt::Display for Refused {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{} (FFXI-{})", error_text(self.0), 3000 + self.0 as u32)
    }
}

impl std::error::Error for Refused {}

/// What the netwait run shares with a lobby link's worker (client/netwait.rs).
#[derive(Default)]
pub struct Watch {
    /// View replies read so far: the netbar's waits.
    pub replies: AtomicU32,
    /// The run's end, which the time-out and the worker's result race for: `RUN`, `GIVEN_UP` or `DONE`.
    state: AtomicU8,
}

const RUN: u8 = 0;
const GIVEN_UP: u8 = 1;
const DONE: u8 = 2;

impl Watch {
    /// A new run on the link.
    pub fn start(&self) {
        self.state.store(RUN, Ordering::SeqCst);
    }

    /// The 3600-call time-out (FUN_100edff0): false when the worker's result came first.
    pub fn give_up(&self) -> bool {
        self.state
            .compare_exchange(RUN, GIVEN_UP, Ordering::SeqCst, Ordering::SeqCst)
            .map_or_else(|s| s == GIVEN_UP, |_| true)
    }

    /// The worker's result: false when the run gave up first, and the link goes back instead.
    pub fn finish(&self) -> bool {
        self.state
            .compare_exchange(RUN, DONE, Ordering::SeqCst, Ordering::SeqCst)
            .map_or_else(|s| s != GIVEN_UP, |_| true)
    }

    /// The run gave up: the worker stops waiting, the request still open.
    pub fn given_up(&self) -> bool {
        self.state.load(Ordering::SeqCst) == GIVEN_UP
    }
}

/// The run stopped waiting for a reply (`Watch::give_up`).
#[derive(Debug)]
pub struct Abandoned;

impl std::fmt::Display for Abandoned {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "the wait for the lobby's reply was given up")
    }
}

impl std::error::Error for Abandoned {}

/// Marks a failure of the list refresh after a change (steps 0x13 / 2 of ops 2, 3 and 5): FFXI-3115 follows it.
#[derive(Debug)]
pub struct InRefresh;

impl std::fmt::Display for InRefresh {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "refreshing the character list")
    }
}

/// A step that failed with a code of its own (thunk_FUN_100efa60): the link's 0x68 (FFXI-3104, the 0x0B came with
/// no character list held, FUN_10115ea0 case 5), or a negative one from PlayOnline (the state's +0x136ac: -1 when
/// polcore's list has no entry for the character, FUN_100eff30, else polcore's own code, FUN_100ee2a0 subs 0xe / 0xf).
#[derive(Debug)]
pub struct Failed(pub i32);

impl std::fmt::Display for Failed {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self.0 {
            c if c < 0 => write!(f, "PlayOnline failed the log-in (POL-{:04})", -(c as i64)),
            c => write!(f, "the lobby step failed (FFXI-{})", 3000 + c),
        }
    }
}

impl std::error::Error for Failed {}

/// A step that failed before its request went out: the link is as it was.
#[derive(Debug)]
pub struct Unsent;

impl std::fmt::Display for Unsent {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "nothing was sent")
    }
}

impl std::error::Error for Unsent {}

/// The key FFXiMain looks a character up by in polcore's list (FUN_100efee0): the 0x20 record's u16 +4, u16 +6 and
/// byte +0xB.
fn world_key(rec: &[u8; CHAR_INFO_LEN]) -> u32 {
    rd_u16(rec, 4) as u32 | (rd_u16(rec, 6) as u32) << 16 | (rec[0xB] as u32) << 24
}

/// The lobby's 0x0B with an empty character list held.
pub const NO_LIST_CODE: i32 = 0x68;
/// A broken or unexpected reply (FFXI-3101).
pub const BROKEN_CODE: i32 = 0x65;
/// The popup after a failed list refresh (FFXI-3115, LAB_1023d0a6): the lobby is left.
pub const LOST_CODE: i32 = 0x73;
/// The code FUN_1023d440 sends down the PlayOnline path unchanged (FFXI-0108).
pub const POL_PATH_CODE: i32 = 0x6c;
/// The refusal that leaves the lobby (FFXI-3331).
pub const LEAVES_LOBBY: u16 = 0x14b;
/// The refusals of a name (FFXI-3313 / 3322): the creator's name step and the rename remember the name.
pub const NAME_REFUSALS: [u16; 2] = [0x139, 0x142];

/// The code retail's popup shows for a failed lobby step (thunk_FUN_100efa60): the lobby's refusal, a step's own
/// code (`Failed`), else `BROKEN_CODE`.
pub fn failure_code(e: &anyhow::Error) -> i32 {
    // A code attached as a context (PlayOnline's, over the refusal it came from) is not in the chain as itself.
    e.downcast_ref::<Failed>()
        .map(|f| f.0)
        .or_else(|| e.chain().find_map(|c| c.downcast_ref::<Refused>().map(|r| r.0 as i32)))
        .unwrap_or(BROKEN_CODE)
}

/// Whether the view link outlives the failure: a refusal (0x04) and the 0x68 only zero the link's wait state
/// (FUN_10115ea0 LAB_101163f3), so the next run's step 1 finds it alive (FUN_101164f0); nothing sent, nothing lost.
pub fn link_kept(e: &anyhow::Error) -> bool {
    match e.downcast_ref::<Failed>() {
        Some(f) => f.0 == NO_LIST_CODE,
        None => e.chain().any(|c| c.is::<Refused>() || c.is::<Unsent>()),
    }
}

/// polcore's character list as xiloader fills it from LSB's data message 0x03 (count @1, 16-byte entries from
/// 0x10: the content id, then the world key): (content id, key). xiloader marks every entry linked to handle 0
/// (+0x10 = its index, +0x11 = 0x80), so FFXiMain's step 3 takes the short path, sub 0xe -> 0xf -> 0x16.
fn pol_entries(msg: &[u8]) -> Vec<(u32, u32)> {
    let count = (msg[1] as usize).min((msg.len() - 8) / 16);
    (1..=count).filter_map(|x| Some((rd_u32(msg, x * 16), rd_u32(msg.get(..x * 16 + 8)?, x * 16 + 4)))).collect()
}

/// How long a read waits before it looks at `Watch::given_up` again.
const POLL: Duration = Duration::from_millis(100);

/// A lobby connection: plain, or TLS (LSB's data and view ports since xiloader 3.0).
enum Link {
    Plain(TcpStream),
    Tls(Box<super::tls::TlsStream>),
}

impl Link {
    /// `key`: TLS held to that key, else plain.
    fn open(host: &str, port: u16, key: Option<super::tls::Fingerprint>) -> Result<Self> {
        Ok(match key {
            Some(k) => Link::Tls(Box::new(super::tls::connect_with_key(host, port, k)?)),
            None => Link::Plain(super::tcp(host, port)?),
        })
    }

    fn tcp(&self) -> &TcpStream {
        match self {
            Link::Plain(s) => s,
            Link::Tls(s) => &s.sock,
        }
    }
}

impl Read for Link {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self {
            Link::Plain(s) => s.read(buf),
            Link::Tls(s) => s.read(buf),
        }
    }
}

impl Write for Link {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match self {
            Link::Plain(s) => s.write(buf),
            Link::Tls(s) => s.write(buf),
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        match self {
            Link::Plain(s) => s.flush(),
            Link::Tls(s) => s.flush(),
        }
    }

    /// rustls's write sends the record but drops the socket's error until the next call: the flush reports it here.
    fn write_all(&mut self, buf: &[u8]) -> std::io::Result<()> {
        match self {
            Link::Plain(s) => s.write_all(buf),
            Link::Tls(s) => {
                s.write_all(buf)?;
                s.flush()
            }
        }
    }
}

/// How long a look at the view link waits while a data message is awaited.
const PEEK: Duration = Duration::from_millis(1);

/// One read toward a whole message in `buf`, `len` its size as far as it is in: true once it is whole. The read
/// wakes after the link's time-out; a run that gave up its wait (`Watch::give_up`) ends it with `Abandoned`, the
/// bytes so far kept in `buf`.
fn read_toward(link: &mut Link, buf: &mut Vec<u8>, len: fn(&[u8]) -> Result<usize>, watch: &Watch) -> Result<bool> {
    let need = len(buf)?;
    if buf.len() < need {
        let mut chunk = [0u8; 4096];
        let want = (need - buf.len()).min(chunk.len());
        match link.read(&mut chunk[..want]) {
            Ok(0) => return Err(std::io::Error::from(std::io::ErrorKind::UnexpectedEof).into()),
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
            Err(e) if matches!(e.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut) => {
                if watch.given_up() {
                    return Err(Abandoned.into());
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(e) => return Err(e.into()),
        }
    }
    Ok(buf.len() >= len(buf)?)
}

/// The lobby closed or reset the link (no reply, no refusal).
fn hung_up(e: &anyhow::Error) -> bool {
    e.downcast_ref::<std::io::Error>()
        .is_some_and(|io| matches!(io.kind(), std::io::ErrorKind::UnexpectedEof | std::io::ErrorKind::ConnectionReset))
}

/// A view packet's size, as far as its header is in.
fn view_len(buf: &[u8]) -> Result<usize> {
    let Some(head) = buf.get(..4) else { return Ok(4) };
    let size = u32::from_le_bytes(head.try_into().unwrap()) as usize;
    if !(28..=MAX_REPLY).contains(&size) {
        bail!("bad lobby packet size {size}");
    }
    Ok(size)
}

/// An LSB data message's size, as far as its first byte is in.
fn data_len(buf: &[u8]) -> Result<usize> {
    match buf.first() {
        None => Ok(1),
        Some(0x01 | 0x02) => Ok(5),
        Some(0x03) => Ok(0x148),
        Some(other) => bail!("unknown lobby data message 0x{other:02X}"),
    }
}

/// A view refusal (0x04) as its error: the code is the u32 @0x20.
fn refused(pkt: &[u8]) -> anyhow::Error {
    match pkt.get(32..36) {
        Some(c) => Refused(u32::from_le_bytes(c.try_into().unwrap()) as u16).into(),
        None => anyhow::anyhow!("the lobby's refusal is too short to carry its code"),
    }
}

/// What a request written still has to come: the LSB data message it waits for (each step has at most one, of its
/// own type), and whether a view reply.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Owed {
    request: u8,
    data: Option<u8>,
    view: bool,
}

/// A lobby result with the server's refusal split out: Err only when the link itself failed.
pub fn refusal<T>(r: Result<T>) -> Result<std::result::Result<T, u16>> {
    match r {
        Ok(v) => Ok(Ok(v)),
        Err(e) => match e.downcast_ref::<Refused>() {
            Some(c) => Ok(Err(c.0)),
            None => Err(e),
        },
    }
}

/// Where each request carries its 16-byte key (FUN_10116610); 0x26 has none.
fn key_at(command: u8) -> Option<usize> {
    match command {
        0x1F | 0x24 => Some(0x1C),
        0x21 => Some(0x20),
        0x14 => Some(0x24),
        0x22 => Some(0x30),
        0x07 | 0x28 | 0x2B => Some(0x34),
        _ => None,
    }
}

/// A request of `size` bytes with the header's size and magic; the command, key and header MD5 go in at send.
fn packet(size: usize) -> Vec<u8> {
    let mut p = vec![0u8; size];
    put(&mut p, 0, &(size as u32).to_le_bytes());
    put(&mut p, 4, MAGIC);
    p
}

pub struct Lobby {
    view: Link,
    /// LSB's data link (xiloader's part); none for PlayOnline.
    data: Option<Link>,
    session: Session,
    k16: [u8; 16],
    /// FFXiMain.dll's checksum, for 0x07.
    checksum: u32,
    server_ip: Ipv4Addr,
    /// The game's key counter (data+0x138): each key-carrying request hashes it, then it steps (FUN_10116d30).
    key_counter: u32,
    last_request: u8,
    pub expansions: u32,
    pub features: u32,
    /// The netbar's reply count and the run's give-up flag (client/netwait.rs).
    pub replies: Arc<Watch>,
    /// Bytes read off the view and data links that are not a whole message yet (a wait given up keeps them).
    view_in: Vec<u8>,
    data_in: Vec<u8>,
    /// What the requests written still have to come, oldest first; the last is the current one. What an earlier
    /// one (its wait given up) gets is read and dropped.
    owed: VecDeque<Owed>,
    /// Sends of the FFXI_LOBBY_MUTE command so far.
    mute_seen: u32,
    /// The world table (0x23), kept for the creator's world step.
    pub worlds: Vec<(u32, String)>,
    /// The last 0x20's records, as sent: requests take their ids from them.
    records: Vec<[u8; CHAR_INFO_LEN]>,
    /// LSB: polcore's character list as xiloader would hold it (`pol_entries`).
    pol_list: Vec<(u32, u32)>,
    /// PlayOnline: the signed-in member (net/pol).
    pub pol: Option<super::pol::Pol>,
}

impl Lobby {
    /// `host`: the lobby (LSB's server, or ffxi00.pol.com); `data_port` is LSB's only. `content`: the installed
    /// ROMs (FUN_101c3400, dat::installed).
    pub fn connect(
        host: &str,
        view_port: u16,
        data_port: u16,
        session: Session,
        ffximain: &[u8],
        version: &str,
        region: u32,
        content: u32,
        replies: Arc<Watch>,
    ) -> Result<Self> {
        // LSB: the data link too, and the key its TLS lobby holds (none: plain).
        let (lsb, key) = match session {
            Session::Lsb { lobby_key, .. } => (true, lobby_key),
            Session::PlayOnline { .. } => (false, None),
        };
        // Both open at once, so a TLS lobby's two handshakes cost one wait; nothing is sent until both have passed.
        let (data, view) = std::thread::scope(|s| {
            let data = lsb.then(|| {
                s.spawn(|| {
                    Link::open(host, data_port, key)
                        .with_context(|| format!("connecting to lobby data {host}:{data_port}"))
                })
            });
            let view =
                Link::open(host, view_port, key).with_context(|| format!("connecting to the lobby {host}:{view_port}"));
            (data.map(|h| h.join().unwrap_or_else(|p| std::panic::resume_unwind(p))), view)
        });
        let (data, view) = (data.transpose()?, view?);
        // Reads wake up to look at the run's give-up flag.
        view.tcp().set_read_timeout(Some(POLL))?;
        if let Some(d) = &data {
            d.tcp().set_read_timeout(Some(POLL))?;
        }
        let server_ip = match view.tcp().peer_addr()?.ip() {
            std::net::IpAddr::V4(ip) => ip,
            std::net::IpAddr::V6(ip) => ip.to_ipv4().unwrap_or(Ipv4Addr::LOCALHOST),
        };
        let k16 = session.k16();
        let mut lobby = Self {
            view,
            data,
            session,
            k16,
            checksum: ffximain_checksum(ffximain),
            server_ip,
            key_counter: 0,
            last_request: 0,
            expansions: 0,
            features: 0,
            replies,
            view_in: Vec::new(),
            data_in: Vec::new(),
            owed: VecDeque::new(),
            mute_seen: 0,
            worlds: Vec::new(),
            records: Vec::new(),
            pol_list: Vec::new(),
            pol: None,
        };

        // Registers the data socket under the session hash.
        if let (Some(d), Session::Lsb { hash, .. }) = (lobby.data.as_mut(), &lobby.session) {
            let mut hello = [0u8; 28];
            hello[0] = 0xFE;
            hello[12..28].copy_from_slice(hash);
            d.write_all(&hello)?;
        }

        // 0x26: the authCode, the region (3 Japanese, else 5), the version, the installed content; 0x05 answers with
        // the counter seed and the expansion bitmasks.
        let mut p = packet(0x98);
        put(&mut p, 0x2C, &region.to_le_bytes());
        put(&mut p, 0x34, &lobby.session.auth_code());
        put_name(&mut p, 0x74, version);
        put(&mut p, 0x84, &content.to_le_bytes());
        lobby.send_view(0x26, p)?;
        let reply = match lobby.read_view(0x05, 0x28) {
            // A TLS lobby drops a plain link unanswered.
            Err(e) if lsb && key.is_none() && e.downcast_ref::<Refused>().is_none() => {
                return Err(e.context(
                    "the lobby gave no answer. If it is TLS (LSB for xiloader 3.0), the login server, which took \
                     loader 2.x, is from another version",
                ));
            }
            // PlayOnline's lobby hanging up on 0x26 (seen 2026-11-16; a sign-in with the Viewer cleared it).
            Err(e) if !lsb && hung_up(&e) => {
                return Err(e.context(
                    "The PlayOnline lobby hung up without answering. If it keeps happening, sign in once with the \
                     PlayOnline Viewer, then try again",
                ));
            }
            r => r?,
        };
        lobby.key_counter = rd_u32(&reply, 0x1C).wrapping_add(1);
        lobby.expansions = rd_u32(&reply, 0x20);
        lobby.features = rd_u32(&reply, 0x24);
        Ok(lobby)
    }

    /// Test hook: FFXI_LOBBY_MUTE=CMD[:N] (hex command, e.g. `14` or `1f:2`) holds back every send of that view
    /// request, or only its Nth on this link, so its reply never comes and the run times out (FFXI-3113).
    fn muted(&mut self, command: u8) -> bool {
        let Ok(v) = std::env::var("FFXI_LOBBY_MUTE") else { return false };
        let (cmd, nth) = v.split_once(':').map_or((v.as_str(), None), |(c, n)| (c, n.parse::<u32>().ok()));
        if u8::from_str_radix(cmd.trim_start_matches("0x"), 16) != Ok(command) {
            return false;
        }
        self.mute_seen += 1;
        nth.is_none_or(|n| n == self.mute_seen)
    }

    fn playonline(&self) -> bool {
        matches!(self.session, Session::PlayOnline { .. })
    }

    /// MD5(K16 ‖ counter) (FUN_10116d80), then the counter steps.
    fn next_key(&mut self) -> [u8; 16] {
        let mut h = Md5::new();
        h.update(self.k16);
        h.update(self.key_counter.to_le_bytes());
        self.key_counter = self.key_counter.wrapping_add(1);
        h.finalize().into()
    }

    fn send_view(&mut self, command: u8, mut pkt: Vec<u8>) -> Result<()> {
        put(&mut pkt, 8, &(command as u32).to_le_bytes());
        if let Some(at) = key_at(command) {
            let key = self.next_key();
            put(&mut pkt, at, &key);
        }
        // FFXiMain: the packet's MD5 with these 16 bytes zero (FUN_10116c90); LSB reads its session hash there.
        let tag: [u8; 16] = match &self.session {
            Session::Lsb { hash, .. } => *hash,
            Session::PlayOnline { .. } => Md5::digest(&pkt).into(),
        };
        put(&mut pkt, 12, &tag);
        self.last_request = command;
        if self.muted(command) {
            log::warn!("lobby: request 0x{command:02X} held back (FFXI_LOBBY_MUTE)");
            return Ok(());
        }
        self.view.write_all(&pkt)?;
        self.owe(command);
        Ok(())
    }

    /// What the lobby owes for a request just written. LSB answers 0x1F and 0x07 on the data link (0x01 / 0x02), and
    /// on the view link only after the loader's 0xA1 / 0xA2.
    fn owe(&mut self, command: u8) {
        let data = match command {
            0x1F if self.data.is_some() => Some(0x01),
            0x07 if self.data.is_some() => Some(0x02),
            _ => None,
        };
        self.owed.push_back(Owed { request: command, data, view: data.is_none() });
    }

    /// The request a view reply answers: the oldest owing one, else the oldest owing only data, answered on the view
    /// link in its place (LSB's 0x04 when it has no data session).
    fn view_owner(&self) -> Option<usize> {
        self.owed.iter().position(|o| o.view).or_else(|| self.owed.iter().position(|o| o.data.is_some()))
    }

    /// Whether the request at `i` is an earlier one than the current request.
    fn is_late(&self, i: Option<usize>) -> bool {
        i.is_some_and(|i| i + 1 < self.owed.len())
    }

    /// Reads one whole view packet and settles the request it answers; true when that is an earlier request. A
    /// refusal settles the data messages it replaces (LSB's 0x04 after a refused 0xA1 comes without the 0x03).
    fn take_view(&mut self) -> Result<(Vec<u8>, bool)> {
        while !read_toward(&mut self.view, &mut self.view_in, view_len, &self.replies)
            .context("the lobby closed the view connection")?
        {}
        let size = view_len(&self.view_in)?;
        let pkt: Vec<u8> = self.view_in.drain(..size).collect();
        if &pkt[4..8] != MAGIC {
            bail!("not a lobby packet");
        }
        // FFXiMain checks every reply's MD5 (FUN_10116540).
        if self.playonline() {
            let mut zeroed = pkt.clone();
            zeroed[12..28].fill(0);
            if Md5::digest(&zeroed)[..] != pkt[12..28] {
                log::warn!("lobby reply failed its checksum: {}", hex::encode(&pkt));
                bail!("lobby reply failed its checksum");
            }
        }
        let command = pkt[8];
        let at = self.view_owner();
        let late = self.is_late(at);
        let request = at.map_or(self.last_request, |i| self.owed[i].request);
        if let Some(i) = at {
            let o = &mut self.owed[i];
            o.view = false;
            if command == 0x04 {
                o.data = None;
            }
            self.owed.retain(|o| o.view || o.data.is_some());
        }
        log::info!("lobby: reply 0x{command:02X} ({size} bytes) to 0x{request:02X}");
        // The lobby stepped its key counter for a late reply as for any.
        if matches!(command, 0x03 | 0x0B | 0x20 | 0x23)
            || (command == 0x04 && matches!(request, 0x22 | 0x24 | 0x28 | 0x2B))
        {
            self.key_counter = self.key_counter.wrapping_add(1);
        }
        if late {
            log::warn!("lobby: dropped the late reply 0x{command:02X} to 0x{request:02X}");
        }
        Ok((pkt, late))
    }

    /// Reads one view packet and checks it is `expect` and at least `min_len` bytes, the end of the last field its
    /// caller reads (lobby errors become `Err`). A reply owed to an earlier request (its wait given up) is dropped.
    fn read_view(&mut self, expect: u8, min_len: usize) -> Result<Vec<u8>> {
        let pkt = loop {
            let (pkt, late) = self.take_view()?;
            if !late {
                break pkt;
            }
        };
        let (command, size) = (pkt[8], pkt.len());
        self.replies.replies.fetch_add(1, Ordering::Relaxed);
        if command == 0x04 {
            return Err(refused(&pkt));
        }
        if command != expect {
            bail!("expected lobby reply 0x{expect:02X}, got 0x{command:02X}");
        }
        if size < min_len {
            bail!("lobby reply 0x{command:02X} is {size} bytes, too short (needs {min_len})");
        }
        Ok(pkt)
    }

    /// Reads one server-to-loader message from LSB's data socket; one owed to an earlier request is dropped. The
    /// view link is watched too: LSB refuses some steps there in place of the data message (a refused 0xA1, a 0x1F
    /// with no data session), and that refusal is the result.
    fn read_data(&mut self) -> Result<Vec<u8>> {
        loop {
            // The view link first: LSB sent a late refusal there before it took the requests after it, and the
            // refusal settles the data message it replaced before a later one of that type comes.
            if self.view_ready()? {
                if self.is_late(self.view_owner()) {
                    self.take_view()?;
                    continue;
                }
                if self.view_in[8] == 0x04 {
                    let (pkt, _) = self.take_view()?;
                    self.replies.replies.fetch_add(1, Ordering::Relaxed);
                    return Err(refused(&pkt));
                }
                // Else the current request's reply came ahead of its data message: it waits for read_view.
            }
            let data = self.data.as_mut().context("no lobby data link")?;
            if !read_toward(data, &mut self.data_in, data_len, &self.replies)
                .context("the lobby closed the data connection")?
            {
                continue;
            }
            let len = data_len(&self.data_in)?;
            let msg: Vec<u8> = self.data_in.drain(..len).collect();
            // The oldest request waiting for this type (each step waits for a different type).
            let at = self.owed.iter().position(|o| o.data == Some(msg[0]));
            let late = self.is_late(at);
            if let Some(i) = at {
                self.owed[i].data = None;
                self.owed.retain(|o| o.view || o.data.is_some());
            }
            if !late {
                return Ok(msg);
            }
            log::warn!("lobby: dropped the late data message 0x{:02X}", msg[0]);
        }
    }

    /// One short read toward a whole view packet: true once one is in.
    fn view_ready(&mut self) -> Result<bool> {
        self.view.tcp().set_read_timeout(Some(PEEK))?;
        let r = read_toward(&mut self.view, &mut self.view_in, view_len, &self.replies);
        self.view.tcp().set_read_timeout(Some(POLL))?;
        r.context("the lobby closed the view connection")
    }

    /// Writes the loader's answer to a data message (0xA1 / 0xA2 for `request`): its view reply comes next, after
    /// the 0x03 for 0xA1.
    fn write_data(&mut self, msg: &[u8], request: u8) -> Result<()> {
        self.data.as_mut().context("no lobby data link")?.write_all(msg)?;
        self.owed.push_back(Owed { request, data: (msg[0] == 0xA1).then_some(0x03), view: true });
        Ok(())
    }

    /// The 0x20 record of a content id.
    fn record(&self, content_id: u32) -> Option<&[u8; CHAR_INFO_LEN]> {
        self.records.iter().find(|r| rd_u32(&r[..], 0) == content_id)
    }

    /// The first free slot (status 1, name " ": FUN_1023df20), whose content id a new character takes.
    fn free_slot(&self) -> u32 {
        self.records
            .iter()
            .find(|r| rd_u16(&r[..], 8) == 1 && r[12] == b' ' && r[13] == 0)
            .map_or(0, |r| rd_u32(&r[..], 0))
    }

    /// The record's u16 at +4 (ffxi_id_world), which 0x07 / 0x14 / 0x28 carry @0x20.
    fn world_id(&self, content_id: u32) -> u32 {
        self.record(content_id).map_or(content_id & 0xFFFF, |r| rd_u16(&r[..], 4) as u32)
    }

    /// The list again after a change (steps 0x13 and 2 of the create, delete and rename runs): PlayOnline's own
    /// character list first (FUN_100ee1e0; under xiloader the loader rewrites polcore's from the 0x03 that follows),
    /// then the lobby's.
    pub fn refresh(&mut self) -> Result<Vec<Character>> {
        if let Some(p) = self.pol.as_mut() {
            p.profile.reload_characters()?;
        }
        self.characters()
    }

    pub fn characters(&mut self) -> Result<Vec<Character>> {
        self.send_view(0x1F, packet(0x2C))?;
        if let Session::Lsb { account_id, hash, .. } = self.session.clone() {
            let msg = self.read_data()?;
            if msg[0] != 0x01 {
                bail!("lobby asked for 0x{:02X} instead of the account id", msg[0]);
            }
            let mut ident = [0u8; 28];
            ident[0] = 0xA1;
            ident[1..5].copy_from_slice(&account_id.to_le_bytes());
            ident[5..9].copy_from_slice(&self.server_ip.octets());
            ident[12..28].copy_from_slice(&hash);
            self.write_data(&ident, 0x1F)?;
            let list = self.read_data()?;
            if list[0] != 0x03 {
                bail!("expected the character list, got 0x{:02X}", list[0]);
            }
            self.pol_list = pol_entries(&list);
        }
        let pkt = self.read_view(0x20, 32)?;
        let count = (rd_u32(&pkt, 28) as usize).min(16);
        self.records = (0..count)
            .filter_map(|i| pkt.get(32 + i * CHAR_INFO_LEN..32 + (i + 1) * CHAR_INFO_LEN))
            .map(|r| r.try_into().unwrap())
            .collect();
        Ok(self.records.iter().map(|r| parse_char(r)).collect())
    }

    pub fn worlds(&mut self) -> Result<Vec<(u32, String)>> {
        self.send_view(0x24, packet(0x2C))?;
        let pkt = self.read_view(0x23, 32)?;
        // No more than the reply holds (a bad count would spin to 4 G).
        let count = (rd_u32(&pkt, 28) as usize).min(pkt.len().saturating_sub(32) / 20);
        let worlds: Vec<(u32, String)> = (0..count)
            .filter_map(|i| {
                let o = 32 + i * 20;
                (o + 20 <= pkt.len()).then(|| (rd_u32(&pkt, o), rd_name(&pkt[o + 4..o + 20])))
            })
            .collect();
        self.worlds = worlds.clone();
        Ok(worlds)
    }

    /// View 0x22, the name check after the creator's world step: the free slot @0x1C, the name @0x20, the world's
    /// name @0x40 and the Gold World Pass @0x50 (LSB reads the name and the pass, keeps them for the 0x21 after it).
    pub fn check_name(&mut self, name: &str, world: &str, pass: &str) -> Result<()> {
        let p = check_body(self.free_slot(), name, world, pass);
        self.send_view(0x22, p)?;
        self.read_view(0x03, 28)?;
        Ok(())
    }

    /// View 0x21, after a passed check_name.
    pub fn create_character(&mut self, c: &NewCharacter) -> Result<()> {
        let p = make_body(self.free_slot(), c);
        self.send_view(0x21, p)?;
        self.read_view(0x03, 28)?;
        Ok(())
    }

    pub fn delete_character(&mut self, ch: &Character) -> Result<()> {
        let mut p = packet(0x34);
        put(&mut p, 0x1C, &ch.content_id.to_le_bytes());
        put(&mut p, 0x20, &self.world_id(ch.content_id).to_le_bytes());
        self.send_view(0x14, p)?;
        self.read_view(0x03, 28)?;
        Ok(())
    }

    /// Renames a character flagged with renamef (0x28: content id @0x1C, its world id @0x20, the name @0x24).
    pub fn rename(&mut self, ch: &Character, name: &str) -> Result<()> {
        let p = rename_body(ch.content_id, self.world_id(ch.content_id), name);
        self.send_view(0x28, p)?;
        self.read_view(0x03, 28)?;
        Ok(())
    }

    /// Whether logging this character in registers it to a PlayOnline handle first (step 3's subs 0x10..0x13):
    /// PlayOnline lists it and no handle holds it. Never under xiloader, whose entries are all linked.
    pub fn registers(&self, ch: &Character) -> bool {
        let (Some(pol), Some(rec)) = (self.pol.as_ref(), self.record(ch.content_id)) else { return false };
        pol.profile.unlinked(ch.content_id, world_key(rec))
    }

    /// Picks a character; the lobby answers with where its zone runs.
    pub fn select(&mut self, ch: &Character) -> Result<MapLogin> {
        // With no list held (the 0x20's count 0, data +0x144) retail still asks, from an empty slot, and fails once
        // the 0x0B is in.
        let listed = !self.records.is_empty();
        let rec = match self.record(ch.content_id) {
            Some(r) => *r,
            None if !listed => [0; CHAR_INFO_LEN],
            None => return Err(anyhow::Error::from(Unsent).context("that character is not in the lobby's list")),
        };
        let mut p = packet(0x58);
        put(&mut p, 0x1C, &ch.content_id.to_le_bytes());
        put(&mut p, 0x20, &(rd_u16(&rec, 4) as u32).to_le_bytes());
        put(&mut p, 0x24, &rec[12..12 + NAME_LEN - 1]);
        put(&mut p, 0x44, &3u32.to_le_bytes());
        // @0x48: MD5(authCode ‖ this request's key ‖ 3 ‖ FFXiMain.dll checksum ‖ content id); the key goes in first.
        let key = self.next_key();
        put(&mut p, 0x34, &key);
        let mut h = Md5::new();
        h.update(self.session.auth_code());
        h.update(key);
        h.update(3u32.to_le_bytes());
        h.update(self.checksum.to_le_bytes());
        h.update(ch.content_id.to_le_bytes());
        put(&mut p, 0x48, &h.finalize());
        // The key is in: send without drawing another one.
        put(&mut p, 8, &7u32.to_le_bytes());
        let tag: [u8; 16] = match &self.session {
            Session::Lsb { hash, .. } => *hash,
            Session::PlayOnline { .. } => Md5::digest(&p).into(),
        };
        put(&mut p, 12, &tag);
        self.last_request = 0x07;
        if self.muted(0x07) {
            log::warn!("lobby: request 0x07 held back (FFXI_LOBBY_MUTE)");
        } else {
            self.view.write_all(&p)?;
            self.owe(0x07);
        }

        if self.data.is_some() {
            let msg = self.read_data()?;
            if msg[0] != 0x02 {
                bail!("lobby asked for 0x{:02X} instead of the key", msg[0]);
            }
            // xi_connect derives the real key itself; these bytes are xiloader's placeholders.
            let mut key_msg = [0u8; 28];
            key_msg[0] = 0xA2;
            key_msg[17..21].copy_from_slice(&[0x58, 0xE0, 0x5D, 0xAD]);
            self.write_data(&key_msg, 0x07)?;
        }

        let pkt = self.read_view(0x0B, 0x48)?;
        let ip = |o| Ipv4Addr::from(rd_u32(&pkt, o).to_le_bytes());
        // FUN_10115ea0 case 5: the 0x0B is taken, then data +0x144 == 0 fails the wait with the link's code 0x68.
        if !listed {
            return Err(Failed(NO_LIST_CODE).into());
        }
        let world_key = world_key(&rec);
        // The lobby closes the link after 0x0B and the game waits for it (FUN_100ee160 sub 2), then makes the character
        // PlayOnline's active one (subs 0xE..0x15); a failure there ends the login.
        if self.playonline() {
            self.view.tcp().set_read_timeout(Some(Duration::from_secs(10)))?;
            let mut rest = Vec::new();
            // Bounded: anything after 0x0B is ignored, and a lobby that keeps sending can't grow it without limit.
            let _ = (&mut self.view).take(MAX_REPLY as u64).read_to_end(&mut rest);
            if let Some(p) = self.pol.as_mut() {
                p.profile.select(ch.content_id, world_key)?;
            }
        } else if !self.pol_list.contains(&(ch.content_id, world_key)) {
            // Sub 0xe under xiloader (FUN_100efee0 -> FUN_100eff30): polcore's list is the data link's 0x03, and a
            // character it does not hold under the same content id and key fails the step with -1. A listed one is
            // linked there, and its ChangeMyStatus (subs 0xe / 0xf) is answered by the loader, so the step ends.
            return Err(Failed(-1).into());
        }
        // World entry hashes the counter after two more steps (step 6: FUN_101158e0 twice); 0x0B made one.
        let mut key20 = [0u8; 20];
        key20[..16].copy_from_slice(&self.k16);
        key20[16..].copy_from_slice(&self.key_counter.wrapping_add(2).to_le_bytes());
        let mut old_key = [0u8; 20];
        old_key[16..].copy_from_slice(&key20[16..]);
        Ok(MapLogin {
            // The record's (FUN_100ef1a0): +0xB << 16 | u16 +4.
            char_id: (rec[0xB] as u32) << 16 | rd_u16(&rec, 4) as u32,
            name: rd_name(&rec[12..28]),
            map: (ip(0x38), rd_u32(&pkt, 0x3C) as u16),
            search: (ip(0x40), rd_u32(&pkt, 0x44) as u16),
            key: key20,
            old_key: self.data.is_some().then_some(old_key),
            lsb: match self.session {
                Session::Lsb { account_id, hash, .. } => Some((account_id, hash)),
                Session::PlayOnline { .. } => None,
            },
            pol: self.pol.take().map(|p| Arc::new(p.into_link())),
        })
    }
}

/// 0x22: the free slot @0x1C, name @0x20, world @0x40, pass @0x50 (15 + NUL each); the key @0x30 at send.
fn check_body(slot: u32, name: &str, world: &str, pass: &str) -> Vec<u8> {
    let mut p = packet(0x60);
    put(&mut p, 0x1C, &slot.to_le_bytes());
    put_name(&mut p, 0x20, name);
    put_name(&mut p, 0x40, world);
    put_name(&mut p, 0x50, pass);
    p
}

/// 0x21: the free slot @0x1C, the make block @0x30: race @0x30, job @0x32, nation @0x36, size @0x39, face @0x3C
/// (LSB login_helpers reads them there).
fn make_body(slot: u32, c: &NewCharacter) -> Vec<u8> {
    let mut p = packet(0x90);
    put(&mut p, 0x1C, &slot.to_le_bytes());
    p[0x30] = c.race;
    p[0x32] = c.job;
    p[0x36] = c.nation;
    p[0x39] = c.size;
    p[0x3C] = c.face;
    p
}

fn rename_body(content_id: u32, world_id: u32, name: &str) -> Vec<u8> {
    let mut p = packet(0x44);
    put(&mut p, 0x1C, &content_id.to_le_bytes());
    put(&mut p, 0x20, &world_id.to_le_bytes());
    put_name(&mut p, 0x24, name);
    p
}

fn parse_char(b: &[u8]) -> Character {
    let info = &b[44..];
    // Model ids 1..7 may carry their slot in the top nibble (0x1000 head .. 0x7000 sub), as the zone's GrapIDTbl
    // does (look_from); LSB's lobby sends them bare.
    let mut looks = [0u16; 8];
    for (i, l) in looks.iter_mut().enumerate() {
        let id = rd_u16(info, 12 + i * 2);
        *l = if i == 0 { id } else { id & 0x0FFF };
    }
    Character {
        content_id: rd_u32(b, 0),
        status: rd_u16(b, 8),
        rename_required: b[10] & 1 != 0,
        name: rd_name(&b[12..28]),
        world: rd_name(&b[28..44]),
        race: rd_u16(info, 0),
        main_job: info[2],
        sub_job: info[3],
        face: rd_u16(info, 4),
        nation: info[6],
        size: info[9],
        zone: info[28] as u16 | ((info[35] as u16 & 1) << 8),
        main_level: info[29],
        looks,
    }
}

#[cfg(test)]
mod create_tests {
    use super::*;

    #[test]
    fn size_lands_where_lsb_reads_it() {
        // LSB: m_look.size = ref<uint8>(buf, 57), buf from the packet start.
        for size in 0..3u8 {
            let pkt = make_body(7, &NewCharacter { race: 2, face: 5, size, job: 3, nation: 1 });
            assert_eq!(
                (pkt.len(), pkt[57], pkt[48], pkt[50], pkt[54], pkt[60], pkt[0x1C]),
                (0x90, size, 2, 3, 1, 5, 7)
            );
        }
    }

    /// LSB view 0x22: the name @32 and the Gold World Pass @0x50 (15 each); the world @0x40 it ignores.
    #[test]
    fn name_check_lands_where_lsb_reads_it() {
        let pkt = check_body(9, "Abcde", "Nameless", "1234567890");
        assert_eq!(
            (pkt.len(), &pkt[32..37], &pkt[0x40..0x48], &pkt[0x50..0x5a], pkt[0x1C]),
            (0x60, &b"Abcde"[..], &b"Nameless"[..], &b"1234567890"[..], 9)
        );
    }

    #[test]
    fn rename_lands_where_lsb_reads_it() {
        // LSB 0x28: charid = ref<uint32>(buf, 28), name from buf + 36 (15 bytes).
        let pkt = rename_body(0x0102_0304, 0x0304, "Newname");
        assert_eq!(u32::from_le_bytes(pkt[28..32].try_into().unwrap()), 0x0102_0304);
        assert_eq!(&pkt[36..44], b"Newname\0");
        assert_eq!(pkt.len(), 0x44);
    }

    /// A lobby as FFXiMain's -net 3 path expects it (MODLOG "PlayOnline sign-in"): every packet's MD5 checked both
    /// ways, the authCode in 0x26, MD5(K16 ‖ counter) in each key field, the 0x07 hash; the map key two steps past
    /// 0x0B.
    #[test]
    fn playonline_dialect_against_a_spec_lobby() {
        use std::net::TcpListener;
        let k16 = [0x42u8; 16];
        let mut auth = [0u8; 64];
        auth[..0x34].fill(0xa5);
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let md5_ok = |p: &[u8]| {
                let mut z = p.to_vec();
                z[12..28].fill(0);
                Md5::digest(&z)[..] == p[12..28]
            };
            let read = |s: &mut TcpStream| {
                let mut n = [0u8; 4];
                s.read_exact(&mut n).unwrap();
                let mut p = vec![0u8; u32::from_le_bytes(n) as usize];
                p[..4].copy_from_slice(&n);
                s.read_exact(&mut p[4..]).unwrap();
                p
            };
            let reply = |s: &mut TcpStream, cmd: u8, body: &[u8]| {
                let mut p = packet(28 + body.len());
                p[8] = cmd;
                p[28..].copy_from_slice(body);
                let d = Md5::digest(&p);
                p[12..28].copy_from_slice(&d);
                s.write_all(&p).unwrap();
            };
            let key = |c: u32| -> [u8; 16] {
                let mut m = Md5::new();
                m.update(k16);
                m.update(c.to_le_bytes());
                m.finalize().into()
            };
            let p = read(&mut s);
            assert!(
                md5_ok(&p)
                    && p[8] == 0x26
                    && p.len() == 0x98
                    && p[0x34..0x74] == auth[..]
                    && &p[0x74..0x7e] == b"30261006_0"
            );
            let mut b = [0u8; 12];
            b[..4].copy_from_slice(&99u32.to_le_bytes());
            reply(&mut s, 0x05, &b);
            let mut c = 100;
            let p = read(&mut s);
            assert!(md5_ok(&p) && p[8] == 0x1F && p.len() == 0x2C && p[0x1C..0x2C] == key(c));
            c += 1;
            let mut list = vec![0u8; 4 + CHAR_INFO_LEN];
            list[0] = 1;
            list[4..8].copy_from_slice(&7u32.to_le_bytes());
            list[8..10].copy_from_slice(&0x1234u16.to_le_bytes());
            list[4 + 0xB] = 2;
            list[4 + 12..4 + 16].copy_from_slice(b"Nine");
            reply(&mut s, 0x20, &list);
            c += 1;
            let p = read(&mut s);
            assert!(md5_ok(&p) && p[8] == 0x07 && p[0x34..0x44] == key(c));
            let mut m = Md5::new();
            m.update(auth);
            m.update(key(c));
            m.update(3u32.to_le_bytes());
            m.update(ffximain_checksum(b"dll").to_le_bytes());
            m.update(7u32.to_le_bytes());
            assert!(p[0x48..0x58] == m.finalize()[..] && p[0x20..0x24] == 0x1234u32.to_le_bytes());
            let mut b = vec![0u8; 0x48 - 28];
            b[0x3C - 28..0x3E - 28].copy_from_slice(&54230u16.to_le_bytes());
            reply(&mut s, 0x0B, &b);
            c
        });
        let mut l = Lobby::connect(
            "127.0.0.1",
            port,
            0,
            Session::PlayOnline { auth_code: auth, k16 },
            b"dll",
            "30261006_0",
            5,
            0xfff,
            Default::default(),
        )
        .unwrap();
        let chars = l.characters().unwrap();
        let m = l.select(&chars[0]).unwrap();
        // The 0x07 hashed c; 0x0B makes it c + 2 and world entry c + 4 (MODLOG "PlayOnline sign-in").
        let c = server.join().unwrap();
        assert_eq!(
            (m.char_id, m.map.1, m.key[..16].to_vec(), u32::from_le_bytes(m.key[16..].try_into().unwrap())),
            (2 << 16 | 0x1234, 54230, k16.to_vec(), c + 4)
        );
    }

    /// A view request off the server's end: its command.
    fn req(v: &mut impl Read) -> u8 {
        let mut n = [0u8; 4];
        v.read_exact(&mut n).unwrap();
        let mut p = vec![0u8; u32::from_le_bytes(n) as usize - 4];
        v.read_exact(&mut p).unwrap();
        p[4]
    }

    /// A view reply `cmd` with `body` after the header.
    fn reply(v: &mut impl Write, cmd: u8, body: &[u8]) {
        let mut p = packet(28 + body.len());
        p[8] = cmd;
        p[28..].copy_from_slice(body);
        v.write_all(&p).unwrap();
        v.flush().unwrap();
    }

    /// A connection within 10 s, its reads timing out alike, so a failing client fails the test rather than hang it.
    fn accept_by(l: &std::net::TcpListener) -> Option<TcpStream> {
        l.set_nonblocking(true).unwrap();
        let end = std::time::Instant::now() + Duration::from_secs(10);
        loop {
            match l.accept() {
                Ok((s, _)) => {
                    s.set_nonblocking(false).unwrap();
                    s.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
                    return Some(s);
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock && std::time::Instant::now() < end => {
                    std::thread::sleep(Duration::from_millis(5))
                }
                Err(_) => return None,
            }
        }
    }

    /// LSB's dialect with its old fixed counter seed: a plain login reaches world entry at xiloader's 0xAD5DE058, the
    /// counter LSB's older login keyed the map with, so `old_key` is the loader's zero value and that counter.
    #[test]
    fn old_key_matches_the_older_lsb_login() {
        let hash = [0x33u8; 16];
        let m = lsb_select(hash, 1).unwrap();
        let old = m.old_key.unwrap();
        assert_eq!(
            (old[..16].to_vec(), u32::from_le_bytes(old[16..].try_into().unwrap())),
            (vec![0u8; 16], 0xAD5DE058)
        );
        assert_eq!((m.key[..16].to_vec(), m.key[16..].to_vec()), (Md5::digest(hash).to_vec(), old[16..].to_vec()));
    }

    /// Step 3 sub 0xe under xiloader (FUN_100efee0 -> FUN_100eff30): the character has to be in polcore's list, which
    /// the loader fills from the data link's 0x03, under the same content id and key; else the step fails with -1
    /// (the popup's "Error code: POL-0001"), after the lobby has answered and closed, so the link is not kept.
    #[test]
    fn a_character_the_loader_list_lacks_fails_the_log_in() {
        let e = lsb_select([0; 16], 0).unwrap_err();
        assert_eq!(failure_code(&e), -1);
        assert!(!link_kept(&e));
    }

    /// The codes of a failed step: the lobby's refusal, the step's code, else 0x65; a refusal, the 0x68 and a request
    /// never sent leave the link up.
    #[test]
    fn failure_codes() {
        let refused = anyhow::Error::from(Refused(201));
        assert_eq!((failure_code(&refused), link_kept(&refused)), (201, true));
        let empty = anyhow::Error::from(Failed(NO_LIST_CODE)).context("select");
        assert_eq!((failure_code(&empty), link_kept(&empty)), (0x68, true));
        let pol = anyhow::Error::from(Failed(-0x104));
        assert_eq!((failure_code(&pol), link_kept(&pol)), (-0x104, false));
        let broken = anyhow::anyhow!("closed");
        assert_eq!((failure_code(&broken), link_kept(&broken)), (BROKEN_CODE, false));
        let unsent = anyhow::Error::from(Unsent).context("not listed");
        assert_eq!((failure_code(&unsent), link_kept(&unsent)), (BROKEN_CODE, true));
        // PlayOnline's code as net/pol attaches it: a context over the profile service's refusal.
        let coded = anyhow::Error::from(super::super::pol::polpro::Refused(0xb4)).context("x").context(Failed(-0x104));
        assert_eq!((failure_code(&coded), link_kept(&coded)), (-0x104, false));
    }

    /// The loader's list from the data message 0x03, as xiloader's applyList reads it.
    #[test]
    fn loader_list_entries() {
        let mut msg = vec![0u8; 0x148];
        (msg[0], msg[1]) = (3, 2);
        msg[16..24].copy_from_slice(&[7, 0, 0, 0, 0x34, 0x12, 9, 1]);
        msg[32..40].copy_from_slice(&[8, 0, 0, 0, 0, 0, 0, 0]);
        msg[48..52].copy_from_slice(&[9, 0, 0, 0]);
        assert_eq!(pol_entries(&msg), vec![(7, 0x0109_1234), (8, 0)]);
        // A count past the message's room stops at its end.
        msg[1] = 0xff;
        assert_eq!(pol_entries(&msg).len(), 20);
    }

    /// An LSB log-in against a spec server whose data list holds `listed` characters (the one picked is the first).
    fn lsb_select(hash: [u8; 16], listed: u8) -> Result<MapLogin> {
        use std::net::TcpListener;
        let (view, data) = (TcpListener::bind("127.0.0.1:0").unwrap(), TcpListener::bind("127.0.0.1:0").unwrap());
        let (vp, dp) = (view.local_addr().unwrap().port(), data.local_addr().unwrap().port());
        let server = std::thread::spawn(move || {
            let (mut d, _) = data.accept().unwrap();
            let (mut v, _) = view.accept().unwrap();
            let mut hello = [0u8; 28];
            d.read_exact(&mut hello).unwrap();
            assert_eq!(req(&mut v), 0x26);
            let mut b = [0u8; 12];
            b[..4].copy_from_slice(&0xAD5DE04Fu32.to_le_bytes());
            reply(&mut v, 0x05, &b);
            assert_eq!(req(&mut v), 0x1F);
            d.write_all(&[1, 0, 0, 0, 0]).unwrap();
            let mut ident = [0u8; 28];
            d.read_exact(&mut ident).unwrap();
            let mut list = vec![0u8; 0x148];
            (list[0], list[1]) = (3, listed);
            list[16..20].copy_from_slice(&7u32.to_le_bytes());
            d.write_all(&list).unwrap();
            let mut chars = vec![0u8; 4 + CHAR_INFO_LEN];
            chars[0] = 1;
            chars[4..8].copy_from_slice(&7u32.to_le_bytes());
            chars[4 + 12..4 + 16].copy_from_slice(b"Nine");
            reply(&mut v, 0x20, &chars);
            assert_eq!(req(&mut v), 0x24);
            reply(&mut v, 0x23, &[0u8; 4]);
            assert_eq!(req(&mut v), 0x07);
            d.write_all(&[2, 0, 0, 0, 0]).unwrap();
            let mut key = [0u8; 28];
            d.read_exact(&mut key).unwrap();
            reply(&mut v, 0x0B, &[0u8; 0x48 - 28]);
        });
        let mut l = Lobby::connect(
            "127.0.0.1",
            vp,
            dp,
            Session::Lsb { account_id: 1, hash, lobby_key: None },
            b"dll",
            "30261006_0",
            5,
            0,
            Default::default(),
        )
        .unwrap();
        let chars = l.characters().unwrap();
        l.worlds().unwrap();
        let m = l.select(&chars[0]);
        server.join().unwrap();
        m
    }

    /// LSB since xiloader 3.0: data and view are TLS with the login server's key. The lobby talks over both as before;
    /// a port that presents another key is refused before anything is sent.
    #[test]
    fn tls_lobby_holds_the_login_key() {
        use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
        use rustls::{ServerConfig, ServerConnection, StreamOwned};
        use std::net::TcpListener;
        const CERT: &[u8] = include_bytes!("testdata/lobby-v1.der");
        const KEY: &[u8] = include_bytes!("testdata/lobby-key.der");
        // As LSB's: an X.509 v1 certificate, which with_single_cert won't parse, so it is served as it is.
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let signer = provider
            .key_provider
            .load_private_key(PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(KEY.to_vec())))
            .unwrap();
        let certified = rustls::sign::CertifiedKey::new(vec![CertificateDer::from(CERT.to_vec())], signer);
        let config = Arc::new(
            ServerConfig::builder_with_provider(provider)
                .with_protocol_versions(&[&rustls::version::TLS13])
                .unwrap()
                .with_no_client_auth()
                .with_cert_resolver(Arc::new(rustls::sign::SingleCertAndKey::from(certified))),
        );
        let key = super::super::tls::fingerprint(super::super::tls::cert_spki(CERT).unwrap());
        // The server's end with its handshake run; none when the client never dialled.
        let accept = |l: &TcpListener| {
            let mut s = accept_by(l)?;
            let mut c = ServerConnection::new(config.clone()).unwrap();
            while c.is_handshaking() {
                if c.complete_io(&mut s).is_err() {
                    break;
                }
            }
            Some(StreamOwned::new(c, s))
        };

        let (view, data) = (TcpListener::bind("127.0.0.1:0").unwrap(), TcpListener::bind("127.0.0.1:0").unwrap());
        let (vp, dp) = (view.local_addr().unwrap().port(), data.local_addr().unwrap().port());
        let hash = [0x33u8; 16];
        std::thread::scope(|scope| {
            let server = scope.spawn(|| {
                let mut d = accept(&data).expect("no data connection");
                let mut v = accept(&view).expect("no view connection");
                let mut hello = [0u8; 28];
                d.read_exact(&mut hello).unwrap();
                assert_eq!((hello[0], &hello[12..]), (0xFE, &hash[..]));
                assert_eq!(req(&mut v), 0x26);
                reply(&mut v, 0x05, &[0u8; 12]);
                assert_eq!(req(&mut v), 0x1F);
                d.write_all(&[1, 0, 0, 0, 0]).unwrap();
                d.flush().unwrap();
                let mut ident = [0u8; 28];
                d.read_exact(&mut ident).unwrap();
                assert_eq!((ident[0], &ident[5..9]), (0xA1, &[127, 0, 0, 1][..]));
                let mut list = vec![0u8; 0x148];
                list[0] = 3;
                d.write_all(&list).unwrap();
                d.flush().unwrap();
                let mut chars = vec![0u8; 4 + CHAR_INFO_LEN];
                chars[0] = 1;
                chars[4..8].copy_from_slice(&7u32.to_le_bytes());
                chars[4 + 12..4 + 16].copy_from_slice(b"Nine");
                reply(&mut v, 0x20, &chars);
            });
            let mut l = Lobby::connect(
                "127.0.0.1",
                vp,
                dp,
                Session::Lsb { account_id: 1, hash, lobby_key: Some(key) },
                b"dll",
                "30261006_0",
                5,
                0,
                Default::default(),
            )
            .unwrap();
            let chars = l.characters().unwrap();
            assert_eq!(chars[0].name, "Nine");
            server.join().unwrap();
        });

        // Another key: refused, and nothing sent on either port (both are dialled at once).
        let other = [0u8; 32];
        let (refused, sent) = std::thread::scope(|scope| {
            let server = scope
                .spawn(|| [&data, &view].map(|l| accept(l).map_or(0, |mut s| s.read(&mut [0u8; 64]).unwrap_or(0))));
            let e = Lobby::connect(
                "127.0.0.1",
                vp,
                dp,
                Session::Lsb { account_id: 1, hash, lobby_key: Some(other) },
                b"dll",
                "30261006_0",
                5,
                0,
                Default::default(),
            )
            .err()
            .unwrap();
            (e, server.join().unwrap())
        });
        let e = format!("{refused:#}");
        assert!(e.contains("another certificate than the login server"), "{e}");
        assert_eq!(sent, [0, 0]);
    }

    /// A plain link to a lobby that hangs up unanswered, as a TLS one does: the error says it may be TLS.
    #[test]
    fn plain_link_dropped_names_tls() {
        use std::net::TcpListener;
        let (view, data) = (TcpListener::bind("127.0.0.1:0").unwrap(), TcpListener::bind("127.0.0.1:0").unwrap());
        let (vp, dp) = (view.local_addr().unwrap().port(), data.local_addr().unwrap().port());
        let server = std::thread::spawn(move || {
            let (_d, mut v) = (accept_by(&data).unwrap(), accept_by(&view).unwrap());
            req(&mut v);
        });
        let e = Lobby::connect(
            "127.0.0.1",
            vp,
            dp,
            Session::Lsb { account_id: 1, hash: [0; 16], lobby_key: None },
            b"dll",
            "30261006_0",
            5,
            0,
            Default::default(),
        )
        .err()
        .unwrap();
        server.join().unwrap();
        let e = format!("{e:#}");
        assert!(e.contains("If it is TLS"), "{e}");
    }

    /// PlayOnline's lobby hanging up on 0x26: the error says what to try.
    #[test]
    fn playonline_hang_up_says_what_to_try() {
        use std::net::TcpListener;
        let view = TcpListener::bind("127.0.0.1:0").unwrap();
        let vp = view.local_addr().unwrap().port();
        let server = std::thread::spawn(move || {
            let mut v = accept_by(&view).unwrap();
            req(&mut v);
        });
        let session = Session::PlayOnline { auth_code: [0; 64], k16: [0; 16] };
        let e =
            Lobby::connect("127.0.0.1", vp, 0, session, b"dll", "30261102_0", 5, 0, Default::default()).err().unwrap();
        server.join().unwrap();
        let e = format!("{e:#}");
        assert!(e.starts_with("The PlayOnline lobby hung up") && e.contains("PlayOnline Viewer"), "{e}");
    }

    /// A lobby whose replies stop at the header: each one is an error, not a panic.
    #[test]
    fn short_replies_are_errors() {
        use std::net::TcpListener;
        // Answers 0x26 with `first` (header and body), then each later request with the next reply.
        let lobby = |replies: Vec<(u8, Vec<u8>)>| {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let port = listener.local_addr().unwrap().port();
            let server = std::thread::spawn(move || {
                let (mut s, _) = listener.accept().unwrap();
                for (cmd, body) in replies {
                    let mut n = [0u8; 4];
                    if s.read_exact(&mut n).is_err() {
                        return;
                    }
                    let mut p = vec![0u8; u32::from_le_bytes(n) as usize - 4];
                    s.read_exact(&mut p).unwrap();
                    let mut r = packet(28 + body.len());
                    r[8] = cmd;
                    r[28..].copy_from_slice(&body);
                    let d = Md5::digest(&r);
                    r[12..28].copy_from_slice(&d);
                    s.write_all(&r).unwrap();
                }
            });
            let session = Session::PlayOnline { auth_code: [0; 64], k16: [0; 16] };
            (Lobby::connect("127.0.0.1", port, 0, session, b"dll", "30261006_0", 5, 0, Default::default()), server)
        };
        let ok05 = (0x05, vec![0u8; 12]);
        // 0x05 without its counter seed and masks.
        let (l, s) = lobby(vec![(0x05, vec![])]);
        assert!(l.is_err());
        s.join().unwrap();
        // A refusal without its code, to 0x26 and to 0x1F.
        let (l, s) = lobby(vec![(0x04, vec![0; 2])]);
        assert!(l.err().unwrap().downcast_ref::<Refused>().is_none());
        s.join().unwrap();
        let (l, s) = lobby(vec![ok05.clone(), (0x04, vec![])]);
        assert!(l.unwrap().characters().is_err());
        s.join().unwrap();
        // A whole refusal still carries its code.
        let (l, s) = lobby(vec![ok05.clone(), (0x04, 313u32.to_le_bytes().repeat(2))]);
        assert_eq!(refusal(l.unwrap().characters()).unwrap().unwrap_err(), 313);
        s.join().unwrap();
        // 0x20 and 0x23 without their counts.
        let (l, s) = lobby(vec![ok05.clone(), (0x20, vec![])]);
        assert!(l.unwrap().characters().is_err());
        s.join().unwrap();
        let (l, s) = lobby(vec![ok05.clone(), (0x23, vec![])]);
        assert!(l.unwrap().worlds().is_err());
        s.join().unwrap();
        // 0x0B without the search server.
        let mut list = vec![0u8; 4 + CHAR_INFO_LEN];
        list[0] = 1;
        list[4..8].copy_from_slice(&7u32.to_le_bytes());
        list[4 + 12..4 + 16].copy_from_slice(b"Nine");
        let (l, s) = lobby(vec![ok05.clone(), (0x20, list.clone()), (0x0B, vec![0; 0x40 - 28])]);
        let mut l = l.unwrap();
        let chars = l.characters().unwrap();
        assert!(l.select(&chars[0]).is_err());
        s.join().unwrap();
        // A character the held list lacks: nothing is sent, the link is kept, and the next log-in goes through.
        let (l, s) = lobby(vec![ok05.clone(), (0x20, list), (0x0B, vec![0; 0x48 - 28])]);
        let mut l = l.unwrap();
        let chars = l.characters().unwrap();
        let mut gone = chars[0].clone();
        gone.content_id = 8;
        let e = l.select(&gone).unwrap_err();
        assert_eq!((failure_code(&e), link_kept(&e)), (BROKEN_CODE, true));
        assert!(l.select(&chars[0]).is_ok());
        s.join().unwrap();
        // A 0x0B with no character list held (the 0x20's count 0): the request still goes, the answer is taken, and
        // the wait fails with the link's code 0x68 (FUN_10115ea0 case 5), the link kept.
        let (l, s) = lobby(vec![ok05, (0x20, vec![0; 4]), (0x0B, vec![0; 0x48 - 28])]);
        let mut l = l.unwrap();
        assert!(l.characters().unwrap().is_empty());
        let e = l.select(&parse_char(&[0; CHAR_INFO_LEN])).unwrap_err();
        assert_eq!((failure_code(&e), link_kept(&e)), (NO_LIST_CODE, true));
        s.join().unwrap();
    }

    /// A wait the run gave up (the 3600-call time-out) keeps the link and the bytes read so far; its reply, when it
    /// comes, is owed to the old request and dropped before the next one.
    #[test]
    fn a_given_up_wait_keeps_the_link() {
        use std::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let (go, wait) = std::sync::mpsc::channel::<()>();
        let server = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut answer = |cmd: u8, body: &[u8], hold: bool| {
                let mut n = [0u8; 4];
                s.read_exact(&mut n).unwrap();
                let mut p = vec![0u8; u32::from_le_bytes(n) as usize - 4];
                s.read_exact(&mut p).unwrap();
                let mut r = packet(28 + body.len());
                r[8] = cmd;
                r[28..].copy_from_slice(body);
                let d = Md5::digest(&r);
                r[12..28].copy_from_slice(&d);
                if hold {
                    // Half the reply, then nothing until the client has given up.
                    s.write_all(&r[..20]).unwrap();
                    wait.recv().unwrap();
                    s.write_all(&r[20..]).unwrap();
                } else {
                    s.write_all(&r).unwrap();
                }
            };
            answer(0x05, &[0u8; 12], false);
            answer(0x23, &[0u8; 4], true);
            answer(0x20, &[0u8; 4], false);
        });
        let watch: Arc<Watch> = Default::default();
        let session = Session::PlayOnline { auth_code: [0; 64], k16: [0; 16] };
        let mut l = Lobby::connect("127.0.0.1", port, 0, session, b"dll", "30261102_0", 5, 0, watch.clone()).unwrap();
        watch.start();
        let w = watch.clone();
        let giver = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(300));
            assert!(w.give_up());
        });
        let e = l.worlds().unwrap_err();
        assert!(e.downcast_ref::<Abandoned>().is_some(), "{e:#}");
        giver.join().unwrap();
        // The 0x23 comes late, ahead of the next request's 0x20: it is read whole and dropped, its key step kept,
        // and the netbar counts only the 0x20.
        watch.start();
        go.send(()).unwrap();
        let (key, read) = (l.key_counter, watch.replies.load(Ordering::Relaxed));
        assert!(l.characters().unwrap().is_empty());
        assert_eq!((l.key_counter - key, watch.replies.load(Ordering::Relaxed) - read), (3, 1));
        assert!(l.owed.is_empty());
        server.join().unwrap();
        assert_eq!(failure_code(&anyhow::Error::from(Refused(313)).context(InRefresh)), 313);
        assert_eq!(failure_code(&anyhow::anyhow!("closed").context(InRefresh)), BROKEN_CODE);
    }

    /// LSB: a list request given up while its data message 0x01 is late. The lobby sends 0x03 and 0x20 only after
    /// the loader's 0xA1, so the next request owes one 0x01 more; the late one is dropped.
    #[test]
    fn a_given_up_data_wait_drops_the_late_message() {
        use std::net::TcpListener;
        let (view, data) = (TcpListener::bind("127.0.0.1:0").unwrap(), TcpListener::bind("127.0.0.1:0").unwrap());
        let (vp, dp) = (view.local_addr().unwrap().port(), data.local_addr().unwrap().port());
        let (go, wait) = std::sync::mpsc::channel::<()>();
        let server = std::thread::spawn(move || {
            let (mut d, _) = data.accept().unwrap();
            let (mut v, _) = view.accept().unwrap();
            d.read_exact(&mut [0u8; 28]).unwrap();
            assert_eq!(req(&mut v), 0x26);
            reply(&mut v, 0x05, &[0u8; 12]);
            assert_eq!(req(&mut v), 0x1F);
            wait.recv().unwrap();
            d.write_all(&[1, 0, 0, 0, 0]).unwrap();
            assert_eq!(req(&mut v), 0x1F);
            d.write_all(&[1, 0, 0, 0, 0]).unwrap();
            let mut ident = [0u8; 28];
            d.read_exact(&mut ident).unwrap();
            assert_eq!(ident[0], 0xA1);
            let mut list = vec![0u8; 0x148];
            list[0] = 3;
            d.write_all(&list).unwrap();
            let mut chars = vec![0u8; 4 + CHAR_INFO_LEN];
            chars[0] = 1;
            chars[4..8].copy_from_slice(&7u32.to_le_bytes());
            chars[4 + 12..4 + 16].copy_from_slice(b"Nine");
            reply(&mut v, 0x20, &chars);
        });
        let watch: Arc<Watch> = Default::default();
        let session = Session::Lsb { account_id: 1, hash: [0x33; 16], lobby_key: None };
        let mut l = Lobby::connect("127.0.0.1", vp, dp, session, b"dll", "30261102_0", 5, 0, watch.clone()).unwrap();
        let w = watch.clone();
        let giver = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(300));
            assert!(w.give_up());
        });
        assert!(l.characters().unwrap_err().downcast_ref::<Abandoned>().is_some());
        giver.join().unwrap();
        assert_eq!(l.owed, [Owed { request: 0x1F, data: Some(0x01), view: false }]);
        watch.start();
        go.send(()).unwrap();
        assert_eq!(l.characters().unwrap()[0].name, "Nine");
        assert!(l.owed.is_empty());
        server.join().unwrap();
    }

    /// A scripted LSB lobby: the server's (data, view) ends run `script` after the 0x26 / 0x05.
    fn lsb_lobby(
        script: impl FnOnce(&mut TcpStream, &mut TcpStream) + Send + 'static,
    ) -> (Lobby, Arc<Watch>, std::thread::JoinHandle<()>) {
        use std::net::TcpListener;
        let (view, data) = (TcpListener::bind("127.0.0.1:0").unwrap(), TcpListener::bind("127.0.0.1:0").unwrap());
        let (vp, dp) = (view.local_addr().unwrap().port(), data.local_addr().unwrap().port());
        let server = std::thread::spawn(move || {
            let (mut d, mut v) = (accept_by(&data).unwrap(), accept_by(&view).unwrap());
            d.read_exact(&mut [0u8; 28]).unwrap();
            assert_eq!(req(&mut v), 0x26);
            reply(&mut v, 0x05, &[0u8; 12]);
            script(&mut d, &mut v);
        });
        let watch: Arc<Watch> = Default::default();
        let session = Session::Lsb { account_id: 1, hash: [0x33; 16], lobby_key: None };
        let l = Lobby::connect("127.0.0.1", vp, dp, session, b"dll", "30261102_0", 5, 0, watch.clone()).unwrap();
        (l, watch, server)
    }

    /// LSB's error reply (generateErrorMessage): view 0x04 with the code @0x20.
    fn refuse(v: &mut TcpStream, code: u32) {
        let mut body = vec![0u8; 8];
        body[4..].copy_from_slice(&code.to_le_bytes());
        reply(v, 0x04, &body);
    }

    /// The list as LSB sends it after 0xA1 (data 0x03, then view 0x20): one character, Nine, content id 7.
    fn send_list(d: &mut TcpStream, v: &mut TcpStream) {
        let mut ident = [0u8; 28];
        d.read_exact(&mut ident).unwrap();
        assert_eq!(ident[0], 0xA1);
        let mut list = vec![0u8; 0x148];
        (list[0], list[1]) = (3, 1);
        list[16..20].copy_from_slice(&7u32.to_le_bytes());
        d.write_all(&list).unwrap();
        let mut chars = vec![0u8; 4 + CHAR_INFO_LEN];
        chars[0] = 1;
        chars[4..8].copy_from_slice(&7u32.to_le_bytes());
        chars[4 + 12..4 + 16].copy_from_slice(b"Nine");
        reply(v, 0x20, &chars);
    }

    /// The run gives up its wait after `ms`.
    fn give_up_after(watch: &Arc<Watch>, ms: u64) -> std::thread::JoinHandle<()> {
        let w = watch.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(ms));
            assert!(w.give_up());
        })
    }

    /// LSB refusing the 0xA1 (maintenance with no character to list, data_session.cpp): view 0x04 and no data 0x03.
    /// The refusal ends the wait for the 0x03 at once and settles it; the next list goes through.
    #[test]
    fn a_refused_list_comes_without_its_data_message() {
        let (mut l, _, server) = lsb_lobby(|d, v| {
            assert_eq!(req(v), 0x1F);
            d.write_all(&[1, 0, 0, 0, 0]).unwrap();
            d.read_exact(&mut [0u8; 28]).unwrap();
            refuse(v, 332);
            assert_eq!(req(v), 0x1F);
            d.write_all(&[1, 0, 0, 0, 0]).unwrap();
            send_list(d, v);
        });
        assert_eq!(refusal(l.characters()).unwrap().unwrap_err(), 332);
        assert!(l.owed.is_empty());
        assert_eq!(l.characters().unwrap()[0].name, "Nine");
        assert!(l.owed.is_empty());
        server.join().unwrap();
    }

    /// The same refusal after the run gave up waiting for the 0x03: the late 0x04 settles the 0x03 it replaced, so
    /// the next list's 0x01, 0x03 and 0x20 go to the next list.
    #[test]
    fn a_refused_list_after_a_time_out_settles_its_data_message() {
        let (go, wait) = std::sync::mpsc::channel::<()>();
        let (mut l, watch, server) = lsb_lobby(move |d, v| {
            assert_eq!(req(v), 0x1F);
            d.write_all(&[1, 0, 0, 0, 0]).unwrap();
            d.read_exact(&mut [0u8; 28]).unwrap();
            wait.recv().unwrap();
            refuse(v, 332);
            assert_eq!(req(v), 0x1F);
            d.write_all(&[1, 0, 0, 0, 0]).unwrap();
            send_list(d, v);
        });
        let giver = give_up_after(&watch, 300);
        assert!(l.characters().unwrap_err().downcast_ref::<Abandoned>().is_some());
        giver.join().unwrap();
        assert_eq!(l.owed, [Owed { request: 0x1F, data: Some(0x03), view: true }]);
        watch.start();
        go.send(()).unwrap();
        let read = watch.replies.load(Ordering::Relaxed);
        assert_eq!(l.characters().unwrap()[0].name, "Nine");
        assert_eq!((l.owed.len(), watch.replies.load(Ordering::Relaxed) - read), (0, 1));
        server.join().unwrap();
    }

    /// LSB's 0x1F with no data session (view_session.cpp): view 0x04 in place of the data 0x01. Refused at once,
    /// and after a time-out the late 0x04 settles the 0x01 it replaced.
    #[test]
    fn a_list_refused_in_place_of_its_data_message() {
        let (go, wait) = std::sync::mpsc::channel::<()>();
        let (mut l, watch, server) = lsb_lobby(move |d, v| {
            assert_eq!(req(v), 0x1F);
            refuse(v, 332);
            assert_eq!(req(v), 0x1F);
            wait.recv().unwrap();
            refuse(v, 332);
            assert_eq!(req(v), 0x1F);
            d.write_all(&[1, 0, 0, 0, 0]).unwrap();
            send_list(d, v);
        });
        assert_eq!(refusal(l.characters()).unwrap().unwrap_err(), 332);
        assert!(l.owed.is_empty());
        let giver = give_up_after(&watch, 300);
        assert!(l.characters().unwrap_err().downcast_ref::<Abandoned>().is_some());
        giver.join().unwrap();
        watch.start();
        go.send(()).unwrap();
        assert_eq!(l.characters().unwrap()[0].name, "Nine");
        assert!(l.owed.is_empty());
        server.join().unwrap();
    }

    /// LSB refusing the 0xA2 (a character already logged in, the zone full, ...): view 0x04 in place of the 0x0B.
    /// After a time-out the late refusal settles the old 0x07, and the next log-in gets the next 0x0B.
    #[test]
    fn a_refused_log_in_after_a_time_out() {
        let (go, wait) = std::sync::mpsc::channel::<()>();
        let (mut l, watch, server) = lsb_lobby(move |d, v| {
            assert_eq!(req(v), 0x1F);
            d.write_all(&[1, 0, 0, 0, 0]).unwrap();
            send_list(d, v);
            assert_eq!(req(v), 0x07);
            d.write_all(&[2, 0, 0, 0, 0]).unwrap();
            d.read_exact(&mut [0u8; 28]).unwrap();
            wait.recv().unwrap();
            refuse(v, 201);
            assert_eq!(req(v), 0x07);
            d.write_all(&[2, 0, 0, 0, 0]).unwrap();
            d.read_exact(&mut [0u8; 28]).unwrap();
            reply(v, 0x0B, &[0u8; 0x48 - 28]);
        });
        let chars = l.characters().unwrap();
        let giver = give_up_after(&watch, 300);
        assert!(l.select(&chars[0]).unwrap_err().downcast_ref::<Abandoned>().is_some());
        giver.join().unwrap();
        assert_eq!(l.owed, [Owed { request: 0x07, data: None, view: true }]);
        watch.start();
        go.send(()).unwrap();
        assert!(l.select(&chars[0]).is_ok());
        assert!(l.owed.is_empty());
        server.join().unwrap();
    }

    /// The time-out and the worker's result race for the run's end: the first one wins.
    #[test]
    fn the_first_end_wins() {
        let w = Watch::default();
        assert!(w.finish() && !w.give_up() && !w.given_up() && w.finish());
        w.start();
        assert!(w.give_up() && w.given_up() && !w.finish() && w.give_up());
    }

    /// A lobby record whose model ids carry their slot nibble parses to bare ids every part file resolves from.
    #[test]
    fn looks_lose_their_slot_nibble() {
        let mut rec = [0u8; CHAR_INFO_LEN];
        rec[12..16].copy_from_slice(b"Nine");
        let info = 44;
        rec[info..info + 2].copy_from_slice(&3u16.to_le_bytes());
        for (i, id) in [0u16, 0x1130, 0x2130, 0x3130, 0x4130, 0x5130, 0x6010, 0x7000].iter().enumerate() {
            rec[info + 12 + i * 2..info + 14 + i * 2].copy_from_slice(&id.to_le_bytes());
        }
        let c = parse_char(&rec);
        assert_eq!(c.looks, [0, 0x130, 0x130, 0x130, 0x130, 0x130, 0x010, 0]);
        let l = &c.looks;
        let look = crate::dat::character::Look {
            race: c.race as u8,
            face: c.face,
            head: l[1],
            body: l[2],
            hands: l[3],
            legs: l[4],
            feet: l[5],
            main: l[6],
            sub: l[7],
            range: 0,
        };
        assert!(crate::dat::character::file_ids(&look).is_ok());
    }

    #[test]
    fn checksum_matches_the_games() {
        // FUN_100185a0: signed bytes, the shift cycling 0, 4, .. 76 (masked to 31).
        let d: Vec<u8> = (0..45u32).map(|i| (i * 37 + 200) as u8).collect();
        let mut s = 0u32;
        for (i, &b) in d.iter().enumerate() {
            s = s.wrapping_add(((b as i8 as i32) << (((i as u32 % 20) * 4) & 31)) as u32);
        }
        assert_eq!(ffximain_checksum(&d), s);
        // The installed 30261006_0 (its value in MODLOG "PlayOnline sign-in"), when present.
        let dll = crate::dat::ffximain(&crate::config::Config::load().ffxi_dir());
        if let Ok(b) = std::fs::read(dll)
            && b.len() == 2_901_584
        {
            assert_eq!(ffximain_checksum(&b), 0x43FA_0718);
        }
    }
}
