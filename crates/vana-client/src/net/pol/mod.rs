//! Signing in to PlayOnline in place of the Viewer: the chat service's key agreement, then the profile
//! service's member login and the game's session (the lobby's authCode and 16-byte value).
//! MODLOG "PlayOnline sign-in".

pub mod chat;
pub mod cipher;
pub mod patchver;
pub mod polpro;

use super::lobby::{Failed, Session};
use anyhow::{Context, Result, bail};
use polpro::{ReplyBody, Status};
use std::net::{Shutdown, SocketAddr, TcpStream};

/// The lobby FFXiMain's -net 3 path uses (`ffxi00.pol.com`, `-port 54001`).
pub const LOBBY_HOST: &str = "ffxi00.pol.com";
pub const LOBBY_PORT: u16 = 54001;

/// What the player types: the PlayOnline member and the Square Enix account it is registered to.
pub struct Credentials {
    pub pol_id: String,
    pub pol_password: String,
    pub se_id: String,
    pub se_password: String,
    pub otp: Option<String>,
}

/// Where the services are: polcore's host names, or a test server's (the profile host then fixed, not routed).
pub struct Servers {
    pub chat: (String, u16),
    pub profile: Option<SocketAddr>,
}

/// The profile service's side of a signed-in member: what polcore keeps between transactions.
pub struct Profile {
    cipher: cipher::PolBlowfish,
    member: polpro::Member,
    server: Option<SocketAddr>,
    status: Status,
    /// polcore's handle and character tables, from the lists (0/9, 1/3).
    tables: polpro::Tables,
}

impl Profile {
    fn transact(&mut self, category: u8, opcode: u8, payload: Option<&[u8]>, reply: ReplyBody) -> Result<Vec<u8>> {
        polpro::transact(&mut self.cipher, &mut self.member, &mut self.server, category, opcode, payload, reply)
    }

    /// ChangeMyStatus (4/5) with polcore's arguments; the reply's first 16 bytes are the session value.
    fn change_status(&mut self, args: [i32; 6]) -> Result<[u8; 16]> {
        let slots = &self.tables.slots;
        let (body, status) =
            polpro::change_my_status(&self.status, args, |c| slots.get(c as usize).copied().unwrap_or_default());
        let r = self.transact(4, 5, Some(&body), ReplyBody::Fixed(0x20))?;
        self.status = status;
        Ok(r[..16].try_into().unwrap())
    }

    /// LoadMyStatus (4/6, 0x1001d490 state 6): the content and presence ([6] - 1, none: 4), the character from the
    /// handle's slot [2] when [1], the flag, activity and p5.
    fn load_status(&mut self) -> Result<()> {
        let s = self.transact(4, 6, Some(&[0; 0x14]), ReplyBody::Fixed(0x80))?;
        let st = &mut self.status;
        if s[6] == 0 {
            (st.content, st.presence) = (-1, 4);
        } else {
            if s[0] < 0x40 {
                st.content = s[0] as i32;
            }
            st.presence = s[6] as i32 - 1;
        }
        if s[1] == 0 || st.content < 0 {
            st.service = -1;
        } else if s[2] < 8 {
            st.service = (self.tables.slots[st.content as usize][s[2] as usize] >> 1 & 0x3f) as i32;
        }
        st.flag = (s[3] == 1) as i32;
        st.activity = u16::from_le_bytes([s[4], s[5]]) as i32;
        st.p5 = s[7] as i32;
        Ok(())
    }

    /// A list the Viewer loads that the game never reads (the friend and group lists): asked for as the Viewer does,
    /// the reply read past; a failure is only logged.
    fn read_past(&mut self, category: u8, opcode: u8) {
        if let Err(e) = self.transact(category, opcode, None, ReplyBody::Sized) {
            log::warn!("PlayOnline {category}/{opcode}: {e:#}");
        }
    }

    /// LoadCharacterList (1/3, 0x100217a0): a linked record fills its handle's slot byte.
    fn load_characters(&mut self) -> Result<()> {
        let r = self.transact(1, 3, None, ReplyBody::Records(0x68))?;
        self.tables.load_characters(&r[8..].as_chunks::<0x68>().0[..r[0] as usize]);
        Ok(())
    }

    /// At character select (FFXiMain step 3, subs 0xE..0x15): the PlayOnline entry with the lobby record's content id
    /// and world key, product 1, and +0x14 zero. One not registered to a handle yet is registered first (`register`);
    /// then it becomes the active character `(its handle, its index, 0, -2, -1, 1)`.
    pub fn select(&mut self, content_id: u32, world_key: u32) -> Result<()> {
        // A failed step leaves polcore's code in the state's +0x136ac.
        let coded = |e: anyhow::Error| match polpro::local_code(&e) {
            Some(c) => e.context(Failed(c)),
            None => e,
        };
        let Some(index) = self.tables.find(world_key, content_id) else {
            // FUN_100eff30: no entry, the state's +0x136ac = -1.
            return Err(anyhow::Error::from(Failed(-1)).context("PlayOnline has no entry for this character."));
        };
        if !self.tables.entries[index].linked {
            self.register(index).map_err(coded)?;
        }
        let e = self.tables.entries[index];
        // Subs 0xe / 0xf (0x14 / 0x15 after a registration).
        self.change_status([e.handle as i32, index as i32, 0, -2, -1, 1]).map_err(coded)?;
        Ok(())
    }

    /// The lobby's step 0x13 (FUN_100ee1e0), after a character was made, deleted or renamed: polcore loads the
    /// character list again (table slots 0xaf / 0xb0, the same 1/3), so a new character has its entry, registered to
    /// no handle until its first log-in. A failure is the step's code.
    pub fn reload_characters(&mut self) -> Result<()> {
        self.load_characters().map_err(|e| match polpro::local_code(&e) {
            Some(c) => e.context(Failed(c)),
            None => e,
        })
    }

    /// Whether `select` would register the character first: PlayOnline lists it and no handle holds it.
    pub fn unlinked(&self, content_id: u32, world_key: u32) -> bool {
        self.tables.find(world_key, content_id).is_some_and(|i| !self.tables.entries[i].linked)
    }

    /// Subs 0x10..0x13: links a character no handle holds yet to the first handle with a free slot (FUN_100efe60),
    /// then stores the character list (1/10); the link stays if the store fails (docs/modlog row 146).
    fn register(&mut self, index: usize) -> Result<()> {
        let Some(handle) = self.tables.free_handle() else {
            return Err(anyhow::Error::from(Failed(-1)).context("No PlayOnline handle has a free character slot."));
        };
        self.tables.unlink(index, handle);
        let code = self.tables.link(index, handle);
        if code < 0 {
            return Err(anyhow::Error::from(Failed(code)).context("PlayOnline could not register the character."));
        }
        log::info!("PlayOnline: registering character entry {index} to handle {handle}");
        if let Some(body) = self.tables.store_body() {
            self.transact(1, 10, Some(&body), ReplyBody::None).context("storing PlayOnline's character list")?;
        }
        self.tables.stored();
        Ok(())
    }
}

/// A signed-in member: the chat link and the profile service.
pub struct Pol {
    chat: chat::Chat,
    pub profile: Profile,
}

impl Pol {
    /// The link the game keeps: the chat answers the server's PINGs until the session ends.
    pub fn into_link(self) -> Link {
        let sock = self.chat.socket();
        self.chat.keep_alive();
        Link { chat: sock, profile: Some(self.profile) }
    }
}

/// The PlayOnline session kept for the game. Dropping it does what FFXiMain does at logout, ChangeMyStatus
/// `(-2, -1, -2, -2, -1, -2)` (no active character, FUN_100ef680), then closes the chat (the Viewer sends no QUIT).
pub struct Link {
    chat: Option<TcpStream>,
    profile: Option<Profile>,
}

impl Drop for Link {
    fn drop(&mut self) {
        let (chat, profile) = (self.chat.take(), self.profile.take());
        std::thread::spawn(move || {
            if let Some(mut p) = profile
                && let Err(e) = p.change_status([-2, -1, -2, -2, -1, -2])
            {
                log::warn!("PlayOnline: clearing the active character: {e:#}");
            }
            if let Some(s) = chat {
                let _ = s.shutdown(Shutdown::Both);
            }
        });
    }
}

impl std::fmt::Debug for Link {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("pol::Link")
    }
}

/// The Viewer's start-up check (app.dll FUN_1013fb5c: step 8, before the sign-in at step 0x23): the Viewer kept in
/// `root` (config::viewer_dir) against the patch server's. Out of date or missing, or no answer, stops the log-in
/// there, as the Viewer goes no further until it is updated.
pub fn viewer_check(root: &std::path::Path) -> Result<()> {
    let server = crate::patch::viewer_version().map(|v| v.version);
    let local = crate::patch::installed_version(root, crate::patch::VIEWER);
    if let Ok(v) = &server {
        log::info!("PlayOnline Viewer {v}; here {}", local.as_deref().unwrap_or("none"));
    }
    viewer_verdict(local.as_deref(), server)
}

/// The Viewer's strings 0x5654 (no answer) and 0x36c5 (out of date).
fn viewer_verdict(local: Option<&str>, server: Result<String>) -> Result<()> {
    let server = server.context("Network Connection Error: the PlayOnline Viewer's version could not be checked")?;
    if !local.is_some_and(|l| crate::patch::up_to_date(&server, l)) {
        bail!("Please update PlayOnline Viewer in order to proceed. Select \"Update\" to begin ({server}).");
    }
    Ok(())
}

/// Signs the member in at polcore's hosts.
pub fn sign_in(c: &Credentials) -> Result<(Session, Pol)> {
    sign_in_at(c, &Servers { chat: (chat::HOST.to_string(), chat::PORT), profile: None })
}

/// Signs the member in as Viewer 1.18.15e and FFXiMain do: the chat login; polcore's connect, the member login (4/7)
/// and its ChangeMyStatus `(-2, -2, 1, -2, -1, -2)` (POLCON 0x1b, 0x28; both skipped when the chat said so);
/// app.dll's LoadMyStatus (4/6), friend, handle, character and group lists (2/3, 0/9, 1/3, 7/c) and ChangeMyStatus
/// `(handle, -2, 1, 2, 0, -2)`;
/// then FFXiMain's `(-2, -1, 0, -2, -1, 1)`, whose reply makes the lobby's session.
pub fn sign_in_at(c: &Credentials, servers: &Servers) -> Result<(Session, Pol)> {
    let chat = chat::Chat::sign_in(&servers.chat.0, servers.chat.1, &c.pol_id, &c.pol_password)?;
    log::info!("PlayOnline: chat signed in, profile host {}", polpro::host(chat.host_byte));
    let member = polpro::Member {
        pol_id: c.pol_id.clone(),
        pol_password: c.pol_password.clone(),
        addr20: chat.addr20,
        host_byte: chat.host_byte,
        fixed: servers.profile,
        residue: [0; 12],
    };
    // polcore's starting status (0x1007541c..: no handle or character, presence 4, activity 1000).
    let status = Status { content: -1, service: -1, flag: 0, presence: 4, p5: 0, activity: 1000, changed: false };
    let mut p =
        Profile { cipher: chat.cipher.clone(), member, server: None, status, tables: polpro::Tables::default() };
    if !chat.skip_member_login {
        let secret = polpro::secret20(&c.se_password);
        let body = polpro::member_login(&c.se_id, &secret, c.otp.as_deref(), chat.now());
        p.transact(4, 7, Some(&body), ReplyBody::None).context("signing in the Square Enix account")?;
        p.change_status([-2, -2, 1, -2, -1, -2])?;
    }
    p.load_status()?;
    // app.dll's LoadMyStatus handler (0x102df51e in the 2026-09-28 build) asks for the friend list (2/3), the handle and character lists and
    // the group list (7/c), in that order.
    p.read_past(2, 3);
    let handles = p.transact(0, 9, None, ReplyBody::Records(0x88))?;
    p.tables.load_handles(&handles[8..].as_chunks::<0x88>().0[..handles[0] as usize]);
    p.load_characters()?;
    p.read_past(7, 0xc);
    // The handle the Viewer plays with: the current one, else the account's first (0/9 records: [0] handle index).
    let content = if p.status.content >= 0 {
        p.status.content
    } else if handles[0] > 0 {
        (handles[8] & 0x3f) as i32
    } else {
        bail!("This PlayOnline member has no handle.")
    };
    p.change_status([content, -2, 1, 2, 0, -2])?;
    let value = p.change_status([-2, -1, 0, -2, -1, 1])?;
    let auth = polpro::auth_code(&value, &p.member.addr20, chat.clock, &chat.key, p.member.host_byte);
    let mut auth_code = [0u8; 64];
    auth_code[..auth.len()].copy_from_slice(&auth);
    Ok((Session::PlayOnline { auth_code, k16: value }, Pol { chat, profile: p }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use polpro::Stream;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    /// A profile server for `n` transactions: answers each handshake and request with a clean header (and a 0x20-byte
    /// body for ChangeMyStatus) and gives back what it was sent as (category, opcode, payload).
    fn server(
        n: usize,
        mut cipher: cipher::PolBlowfish,
    ) -> (SocketAddr, std::thread::JoinHandle<Vec<(u8, u8, Vec<u8>)>>) {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = l.local_addr().unwrap();
        let t = std::thread::spawn(move || {
            let mut seen = Vec::new();
            for _ in 0..n {
                let (mut s, _) = l.accept().unwrap();
                let mut hs = [0u8; 0x28];
                s.read_exact(&mut hs).unwrap();
                let mut answer = [0u8; 0x18];
                answer[0x14..].copy_from_slice(&[1, 2, 3, 4]);
                s.write_all(&answer).unwrap();
                let mut head = [0u8; 0x28];
                s.read_exact(&mut head).unwrap();
                cipher.apply(&mut head, true);
                let mut body = vec![0u8; u32::from_le_bytes(head[4..8].try_into().unwrap()) as usize];
                s.read_exact(&mut body).unwrap();
                cipher.apply(&mut body, false);
                let payload = body.len().checked_sub(4).map_or(&[][..], |n| {
                    assert_eq!(polpro::checksum(&body[..n]).to_le_bytes(), body[n..]);
                    &body[..n]
                });
                seen.push((head[1], head[2], payload.to_vec()));
                let mut rh = [0u8; 0x18];
                cipher.apply(&mut rh, true);
                s.write_all(&rh).unwrap();
                let mut rb = match (head[1], head[2]) {
                    (4, 5) => polpro::body(&[0x5a; 0x1c]),
                    // The character list: the first entry linked as `lists` has it, and a new one at index 6.
                    (1, 3) => {
                        let mut b = vec![2u8, 0, 0, 0, 0, 0, 0, 0];
                        b.extend(character(4, true, 0x1234));
                        b.extend(character(6, false, 0x1299));
                        b
                    }
                    _ => Vec::new(),
                };
                cipher.apply(&mut rb, false);
                s.write_all(&rb).unwrap();
            }
            seen
        });
        (addr, t)
    }

    fn profile(fixed: SocketAddr, cipher: cipher::PolBlowfish) -> Profile {
        let member = polpro::Member {
            pol_id: "EFKAOYMJ".into(),
            pol_password: "hunter2".into(),
            addr20: [0; 20],
            host_byte: 0,
            fixed: Some(fixed),
            residue: [0; 12],
        };
        let status = Status { content: 0, service: -1, flag: 0, presence: 2, p5: 0, activity: 1, changed: true };
        Profile { cipher, member, server: None, status, tables: polpro::Tables::default() }
    }

    fn character(index: u8, linked: bool, content_id: u32) -> [u8; 0x68] {
        let mut c = [0u8; 0x68];
        (c[0], c[1], c[8]) = (index, index, 1);
        if linked {
            (c[4], c[5], c[6]) = (1, 1, 3);
        }
        c[0xc..0x10].copy_from_slice(&0x7f00_0102u32.to_le_bytes());
        c[0x10..0x14].copy_from_slice(&content_id.to_le_bytes());
        c
    }

    fn lists(p: &mut Profile, linked: bool) {
        let mut handle = [0u8; 0x88];
        handle[0] = 1;
        p.tables.load_handles(&[handle]);
        p.tables.load_characters(&[character(4, linked, 0x1234)]);
    }

    /// A character no handle holds is registered on the way in (FFXiMain step 3, subs 0x10..0x15): the character
    /// list's store, 1/10, then ChangeMyStatus naming the slot it took. A linked one sends ChangeMyStatus alone.
    #[test]
    fn select_registers_an_unlinked_character() {
        let cipher = cipher::PolBlowfish::new(&[1, 2, 3, 4, 5, 6, 7, 8], [8, 7, 6, 5, 4, 3, 2, 1]);
        let (addr, t) = server(2, cipher.clone());
        let mut p = profile(addr, cipher.clone());
        lists(&mut p, false);
        p.select(0x1234, 0x7f00_0102).unwrap();
        let seen = t.join().unwrap();
        assert_eq!((seen[0].0, seen[0].1, seen[0].2.len()), (1, 10, 0x244));
        let store = &seen[0].2;
        assert_eq!(store[..6], [0, 1, 2, 3, 4, 5]);
        assert_eq!(store[0x40 + 4 * 8..][..8], [1, 1, 0, 0, 0, 0, 0, 0]);
        assert_eq!(store.iter().filter(|&&b| b != 0).count(), 63 + 2);
        assert_eq!((seen[1].0, seen[1].1), (4, 5));
        // ChangeMyStatus: handle 1, the character found in the handle's slot 0.
        assert_eq!(seen[1].2[0x10..0x13], [1, 1, 0]);
        assert_eq!((p.status.content, p.status.service), (1, 4));
        assert!(p.tables.entries[4].linked);

        let (addr, t) = server(1, cipher.clone());
        let mut p = profile(addr, cipher);
        lists(&mut p, true);
        p.select(0x1234, 0x7f00_0102).unwrap();
        let seen = t.join().unwrap();
        assert_eq!((seen[0].0, seen[0].1), (4, 5));
        assert_eq!(seen[0].2[0x10..0x13], [1, 1, 3]);
    }

    /// A character made in this session: the lobby's step 0x13 loads PlayOnline's list again, the new entry is
    /// there unregistered, and its first log-in takes the handle's first free slot.
    #[test]
    fn a_new_character_is_listed_then_registered() {
        let cipher = cipher::PolBlowfish::new(&[1, 2, 3, 4, 5, 6, 7, 8], [8, 7, 6, 5, 4, 3, 2, 1]);
        let (addr, t) = server(3, cipher.clone());
        let mut p = profile(addr, cipher);
        lists(&mut p, true);
        assert!(!p.unlinked(0x1299, 0x7f00_0102));
        p.reload_characters().unwrap();
        assert!(p.unlinked(0x1299, 0x7f00_0102));
        assert!(!p.unlinked(0x1234, 0x7f00_0102));
        p.select(0x1299, 0x7f00_0102).unwrap();
        let seen = t.join().unwrap();
        assert_eq!(seen.iter().map(|s| (s.0, s.1)).collect::<Vec<_>>(), [(1, 3), (1, 10), (4, 5)]);
        assert_eq!(seen[1].2[0x40 + 6 * 8..][..3], [1, 1, 0]);
        assert_eq!(seen[1].2[0x40 + 4 * 8..][..3], [0, 0, 0]);
        assert_eq!(seen[2].2[0x10..0x13], [1, 1, 0]);
        assert_eq!(p.tables.slots[1], [6 << 1 | 1, 0, 0, 4 << 1 | 1, 0, 0, 0, 0]);
    }

    /// The Viewer check lets a log-in on only with the Viewer kept here current, as the Viewer goes on only then.
    #[test]
    fn viewer_verdicts() {
        assert!(viewer_verdict(Some("20261022_0"), Ok("20261022_0".into())).is_ok());
        assert!(viewer_verdict(Some("20261201_0"), Ok("20261022_0".into())).is_ok());
        let e = format!("{:#}", viewer_verdict(Some("20261022_0"), Ok("20271231_0".into())).unwrap_err());
        assert!(e.starts_with("Please update PlayOnline Viewer") && e.contains("20271231_0"), "{e}");
        assert!(viewer_verdict(None, Ok("20261022_0".into())).is_err());
        let e = format!("{:#}", viewer_verdict(Some("20261022_0"), Err(anyhow::anyhow!("refused"))).unwrap_err());
        assert!(e.starts_with("Network Connection Error"), "{e}");
    }

    /// No handle with a free slot, or no entry: the code is -1 and nothing is sent. A refused store is polcore's code
    /// for the refusal, and the link stays.
    #[test]
    fn select_failures() {
        let cipher = cipher::PolBlowfish::new(&[1, 2, 3, 4, 5, 6, 7, 8], [8, 7, 6, 5, 4, 3, 2, 1]);
        let nowhere: SocketAddr = "127.0.0.1:1".parse().unwrap();
        let code = |e: anyhow::Error| e.downcast_ref::<Failed>().map(|f| f.0);
        let mut p = profile(nowhere, cipher.clone());
        lists(&mut p, false);
        assert_eq!(code(p.select(0x1235, 0x7f00_0102).unwrap_err()), Some(-1));
        p.tables.slots[1] = [1; 8];
        assert_eq!(code(p.select(0x1234, 0x7f00_0102).unwrap_err()), Some(-1));
        assert!(!p.tables.entries[4].linked);

        // The handshake refused with status 0x7b.
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = l.local_addr().unwrap();
        let t = std::thread::spawn(move || {
            let (mut s, _) = l.accept().unwrap();
            let mut hs = [0u8; 0x28];
            s.read_exact(&mut hs).unwrap();
            let mut answer = [0u8; 0x18];
            answer[1] = 0x7b;
            s.write_all(&answer).unwrap();
        });
        let mut p = profile(addr, cipher);
        lists(&mut p, false);
        assert_eq!(code(p.select(0x1234, 0x7f00_0102).unwrap_err()), Some(polpro::error_code(0x7b)));
        t.join().unwrap();
        assert!(p.tables.entries[4].linked);
    }
}
