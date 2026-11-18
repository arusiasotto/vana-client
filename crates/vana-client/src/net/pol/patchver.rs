//! patch.ver: the version string a PlayOnline title's folder keeps, 0x120 bytes under polcore's *5-chain cipher
//! (table 0x493: FUN_10048380 / FUN_10048410, 1.18.00n addresses). MODLOG "PlayOnline: the Viewer's version check".

use super::polpro::C5;

/// The file's length: 0x118 bytes of data and the cipher's 8-byte tag.
pub const LEN: usize = 0x120;
/// Where the version string starts in the data (the 0x18 bytes before it are not read).
const AT: usize = 0x18;

/// Titles: the game (registry value "0001") and the Viewer ("1000").
pub const GAME: u32 = 1;
pub const VIEWER: u32 = 1000;

/// The key (FUN_10048330 / FUN_10048200): the registry value's bytes summed into 8 lanes, plus the title. A folder
/// with no registry value (polcore's fallback, and every install this client makes) has the title alone.
fn key(title: u32, registry: Option<&str>) -> [u8; 8] {
    let mut lanes = [0u8; 8];
    for (i, b) in registry.unwrap_or("").bytes().enumerate() {
        lanes[i & 7] = lanes[i & 7].wrapping_add(b);
    }
    u64::from_le_bytes(lanes).wrapping_add(title as u64).to_le_bytes()
}

/// The version string, as polcore reads it: with the registry value's key, else the title's (None: neither opens it).
pub fn read(coded: &[u8], title: u32, registry: Option<&str>) -> Option<String> {
    let coded = coded.get(..LEN)?;
    let data = registry
        .and_then(|r| C5::decrypt(key(title, Some(r)), coded))
        .or_else(|| C5::decrypt(key(title, None), coded))?;
    let s = &data[AT..LEN - 8];
    let end = s.iter().position(|&b| b == 0)?;
    String::from_utf8(s[..end].to_vec()).ok()
}

/// A patch.ver holding `version`, under the title's key (polcore's no-registry fallback reads it).
pub fn write(version: &str, title: u32) -> Vec<u8> {
    let mut data = vec![0u8; LEN - 8];
    let n = version.len().min(LEN - 8 - AT - 1);
    data[AT..AT + n].copy_from_slice(&version.as_bytes()[..n]);
    C5::encrypt(key(title, None), &data)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The 2026-11-16 installs' files and their registry values, as the Viewer and FFXiMain read them.
    #[test]
    fn reads_the_viewers_files() {
        let game = hex::decode(GAME_1116).unwrap();
        assert_eq!(read(&game, GAME, Some("0")).as_deref(), Some("30261102_0"));
        let viewer = hex::decode(VIEWER_1116).unwrap();
        assert_eq!(read(&viewer, VIEWER, Some("001b1394")).as_deref(), Some("20261022_0"));
        // The wrong title's key does not open it.
        assert_eq!(read(&viewer, GAME, Some("001b1394")), None);
    }

    /// Ours, read back here and (checked 2026-11-16) by polcore's table 0x493 for both titles.
    #[test]
    fn writes_what_it_reads() {
        let f = write("20261022_0", VIEWER);
        assert_eq!(f.len(), LEN);
        assert_eq!(read(&f, VIEWER, None).as_deref(), Some("20261022_0"));
        // A registry value that does not fit falls back to the title's key, as polcore does.
        assert_eq!(read(&f, VIEWER, Some("001b1394")).as_deref(), Some("20261022_0"));
        assert_eq!(read(&f, GAME, None), None);
    }

    const GAME_1116: &str = "23f1451d97e2aea05c60a225e0b9326647927c5a874e883c1d0dfcd6575a5ad8cb8d145ac111a353ce8cb57eedfc72b16dd796f9ee8d5b8692b6fce928d7e8b72bf1c9219790d831582836c83f1266fc20733c53f1025143db12ee518f5ff298697c3c1c243b4b6bb59cf87e95387ac99c183ee1107e2ba6e83ec4d496ad6dba1431208c4175b9fb0da02135717d7a291e8029fc0a5a6cde8555e9961c829a1ec7f4f229694dca6a9b24c7cf68af192c355691bd16ef4a6ab5be6a5245a9e04e0158593b62c8b2c6b8c4c0032446287cdaafe5cb6897aa11591741796777348e05cb56b2fd9dc27146d2aab584628006dfed2a2c51c2bc0ea03478708963e26703d07810daafe3ed7c43fd8a8fd65d0967b55741dc15d367cf2efbf3d925cb5f";
    const VIEWER_1116: &str = "9ee97096262464652b78c1d0abb3e3f2773300a6d551cbab34e4ff0e328cc20ff9049e6a1277eb1f03e45a3a643c20f557ff0c5da266feca0efe4a3922c0c5d549a1d5379aedc89576b0f1e5c897528964739e45e804e2b48f119b619832bc01c5d44f43184796562d6778a61ef6d4040a57a7f66ef9435fe131458449b4188f3330f68b656011167fefec221a347e4b88035c9725d6a8be90ea243d7daf2659f9a48cb10a239c10bf7bac2733eb23e42070839d0743bb48798692cab7d23eef3f10477f4f45e9ce4d45eb3b66583fee3bfe32d9ace0f9d2841731d8db5cdb3e5e843ede348429aa894e44f6ca4c399a04288bc5903e675819e07acf8cfe357dbec04d9bebe9a9a80b5de8e9d2ca9a8b57142bbd8e0a90f0c35baa64c66b778c";
}
