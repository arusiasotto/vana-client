//! FFXI's packet compression: a fixed per-byte prefix code, bits packed LSB-first,
//! behind a leading 0x01 byte. The table holds 512 little-endian u32s indexed by the
//! byte as a signed char: codes at `b + 0x80`, code lengths at `b + 0x180`.

use anyhow::{Result, bail};

#[derive(Clone)]
pub struct Codec {
    codes: [u32; 256],
    lens: [u8; 256],
    /// Binary trie; a child >= 0 is a node index, < 0 is `-(symbol + 1)`.
    tree: Vec<[i32; 2]>,
}

fn signed_index(b: u8, base: i32) -> usize {
    (b as i8 as i32 + base) as usize
}

/// FFXiMain.dll keeps the code as 256 packed records `{u8 sym, u32 code, u32 bits}`,
/// ordered by sym as a signed char (0x80, 0x81, .. 0x7F).
const RECORDS: usize = 256 * 9;
const KNOWN_OFFSET: usize = 0x37EA8;
/// FUN_100fa710 unpacks into 10000 bytes less the header; FUN_100df5d0 fails once the output reaches that.
const OUT_ROOM: usize = 10000 - 0x1c;

fn records_at(dll: &[u8], at: usize) -> bool {
    dll.len() >= at + RECORDS && (0..256).all(|i| dll[at + i * 9] == (i as u8).wrapping_sub(0x80))
}

impl Codec {
    /// Reads the code table out of the game's FFXiMain.dll.
    pub fn from_ffximain(dll: &[u8]) -> Result<Self> {
        let at = if records_at(dll, KNOWN_OFFSET) {
            KNOWN_OFFSET
        } else {
            (0..dll.len().saturating_sub(RECORDS))
                .find(|&o| records_at(dll, o))
                .ok_or_else(|| anyhow::anyhow!("no compression table in FFXiMain.dll"))?
        };
        let field =
            |i: usize, o: usize| u32::from_le_bytes(dll[at + i * 9 + o..at + i * 9 + o + 4].try_into().unwrap());
        let mut table = vec![0u8; 2048];
        for i in 0..256 {
            table[i * 4..i * 4 + 4].copy_from_slice(&field(i, 1).to_le_bytes());
            table[(0x100 + i) * 4..(0x100 + i) * 4 + 4].copy_from_slice(&field(i, 5).to_le_bytes());
        }
        Self::from_table(&table)
    }

    /// From the server's 512-u32 layout (LandSandBoat's res/compress.dat).
    pub fn from_table(table: &[u8]) -> Result<Self> {
        if table.len() != 2048 {
            bail!("compression table must be 2048 bytes, got {}", table.len());
        }
        let word = |i: usize| u32::from_le_bytes(table[i * 4..i * 4 + 4].try_into().unwrap());
        let mut codec = Codec { codes: [0; 256], lens: [0; 256], tree: vec![[0, 0]] };
        for b in 0..=255u8 {
            let len = word(signed_index(b, 0x180));
            if !(1..=32).contains(&len) {
                bail!("bad code length {len} for byte {b:#04x}");
            }
            codec.codes[b as usize] = word(signed_index(b, 0x80));
            codec.lens[b as usize] = len as u8;
        }
        for b in 0..=255u8 {
            let (code, len) = (codec.codes[b as usize], codec.lens[b as usize] as u32);
            let mut node = 0usize;
            for k in 0..len {
                let bit = ((code >> k) & 1) as usize;
                if k + 1 == len {
                    if codec.tree[node][bit] != 0 {
                        bail!("compression table is not a prefix code (byte {b:#04x})");
                    }
                    codec.tree[node][bit] = -(b as i32 + 1);
                } else {
                    match codec.tree[node][bit] {
                        0 => {
                            codec.tree.push([0, 0]);
                            let next = codec.tree.len() - 1;
                            codec.tree[node][bit] = next as i32;
                            node = next;
                        }
                        n if n > 0 => node = n as usize,
                        _ => bail!("compression table is not a prefix code (byte {b:#04x})"),
                    }
                }
            }
        }
        Ok(codec)
    }

    /// The payload bits `input` compresses to (`compress`'s size field less 8), without compressing it.
    pub fn bits(&self, input: &[u8]) -> u32 {
        input.iter().map(|&b| self.lens[b as usize] as u32).sum()
    }

    /// Returns the compressed bytes and the size field the protocol carries (payload bits + 8).
    pub fn compress(&self, input: &[u8]) -> (Vec<u8>, u32) {
        let mut out = vec![1u8];
        let (mut acc, mut acc_bits, mut bits) = (0u64, 0u32, 0u32);
        for &b in input {
            let len = self.lens[b as usize] as u32;
            let code = if len >= 32 { self.codes[b as usize] } else { self.codes[b as usize] & ((1 << len) - 1) };
            acc |= (code as u64) << acc_bits;
            acc_bits += len;
            bits += len;
            while acc_bits >= 8 {
                out.push(acc as u8);
                acc >>= 8;
                acc_bits -= 8;
            }
        }
        if acc_bits > 0 {
            out.push(acc as u8);
        }
        (out, bits + 8)
    }

    /// FUN_100df7c0, the body a datagram carries and its size field in bits. The codes go behind a leading 1 while
    /// they stay under `room - 1` bytes; once a byte's code would reach that, the input goes as it is behind a leading
    /// 0 (the field is then its bytes + 1, times 8) when that fits `room`, and nothing is made when it does not.
    pub fn pack(&self, input: &[u8], room: usize) -> Option<(Vec<u8>, u32)> {
        if (self.bits(input) as usize) < room.saturating_sub(1) * 8 {
            return Some(self.compress(input));
        }
        (input.len() < room).then(|| {
            let mut out = vec![0u8];
            out.extend_from_slice(input);
            let bits = out.len() as u32 * 8;
            (out, bits)
        })
    }

    /// FUN_100df5d0. `data` starts at the leading byte: 1 has the codes behind it, anything else the plain bytes
    /// (the size field less 8, in whole bytes). A code cut short by the bit count is left out. Retail takes the field
    /// less 8 unsigned and reads past the datagram when the count says so; ours refuses a field under 8 and reads no
    /// further than `data`.
    pub fn decompress(&self, data: &[u8], size_field: u32) -> Result<Vec<u8>> {
        let Some((&form, payload)) = data.split_first() else { bail!("no compressed data") };
        let Some(bits) = size_field.checked_sub(8) else { bail!("size field {size_field} is under 8 bits") };
        let bits = (bits as usize).min(payload.len() * 8);
        if form != 1 {
            return Ok(payload[..bits / 8].to_vec());
        }
        let mut out = Vec::with_capacity(bits / 4);
        let (mut pos, mut node) = (0usize, 0usize);
        while pos < bits {
            let bit = ((payload[pos >> 3] >> (pos & 7)) & 1) as usize;
            pos += 1;
            match self.tree[node][bit] {
                0 => bail!("invalid code in compressed data"),
                n if n < 0 => {
                    out.push((-n - 1) as u8);
                    if out.len() >= OUT_ROOM {
                        bail!("compressed data unpacks to {OUT_ROOM} bytes or more");
                    }
                    node = 0;
                }
                n => node = n as usize,
            }
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Set FFXI_COMPRESS_TABLE (and FFXI_DECOMPRESS_TABLE for the tree check) to run.
    fn codec() -> Option<Codec> {
        let path = std::env::var("FFXI_COMPRESS_TABLE").ok()?;
        Some(Codec::from_table(&std::fs::read(path).unwrap()).unwrap())
    }

    /// Set FFXI_MAIN_DLL to the game's FFXiMain.dll: its table must equal the server's.
    #[test]
    fn game_table_matches_server_table() {
        let (Some(server), Ok(dll)) = (codec(), std::env::var("FFXI_MAIN_DLL")) else { return };
        let game = Codec::from_ffximain(&std::fs::read(dll).unwrap()).unwrap();
        assert_eq!(game.codes, server.codes);
        assert_eq!(game.lens, server.lens);
    }

    #[test]
    fn round_trip() {
        let Some(c) = codec() else { return };
        let input: Vec<u8> = (0..4000u32).map(|i| (i.wrapping_mul(2654435761) >> 13) as u8).collect();
        let (packed, size) = c.compress(&input);
        assert_eq!(c.decompress(&packed, size).unwrap(), input);
        assert_eq!(size, c.bits(&input) + 8);
    }

    /// Plain 8-bit codes (each byte its code) but 0xFF, which takes 32 bits.
    fn long_codec() -> Codec {
        let mut table = vec![0u8; 2048];
        for b in 0..=255u8 {
            let i = (b as i8 as i32 + 0x80) as usize;
            table[i * 4..i * 4 + 4].copy_from_slice(&(b as u32).to_le_bytes());
            let len = if b == 0xFF { 32u32 } else { 8 };
            table[(i + 0x100) * 4..(i + 0x100) * 4 + 4].copy_from_slice(&len.to_le_bytes());
        }
        Codec::from_table(&table).unwrap()
    }

    /// FUN_100df7c0: codes under room - 1 bytes go compressed, at or past it the input goes plain behind a 0 when
    /// that fits the room; FUN_100df5d0 reads both forms.
    #[test]
    fn stored_form() {
        let c = long_codec();
        // 31 bytes of 8-bit codes in a 33-byte room: 248 bits, under 32 x 8.
        let (body, bits) = c.pack(&[7; 31], 33).unwrap();
        assert_eq!((body[0], body.len(), bits), (1, 32, 256));
        // 32 bytes reach 256 bits: plain, behind a 0.
        let (body, bits) = c.pack(&[7; 32], 33).unwrap();
        assert_eq!((body[0], body.len(), bits), (0, 33, 264));
        assert_eq!(c.decompress(&body, bits).unwrap(), [7; 32]);
        // 33 bytes do not fit either way; 8 long codes do, plain.
        assert!(c.pack(&[7; 33], 33).is_none());
        let (body, bits) = c.pack(&[0xFF; 8], 33).unwrap();
        assert_eq!((body[0], bits), (0, 72));
        assert_eq!(c.decompress(&body, bits).unwrap(), [0xFF; 8]);
        // Any leading byte but 1 is the plain form; the count is whole bytes of the field less 8.
        assert_eq!(c.decompress(&[2, 9, 8, 7], 8 + 23).unwrap(), [9, 8]);
        assert!(c.pack(&[], 33).is_some_and(|(body, bits)| body == [1] && bits == 8));
    }

    /// FUN_100df5d0's ends: a code cut short is left out, a field under 8 and an output at the limit fail.
    #[test]
    fn decompress_limits() {
        let c = long_codec();
        assert_eq!(c.decompress(&[1, 5, 6, 0xFF, 0], 8 + 16 + 12).unwrap(), [5, 6]);
        assert!(c.decompress(&[1, 5], 7).is_err());
        assert!(c.decompress(&[], 8).is_err());
        let full = [vec![1u8], vec![3u8; OUT_ROOM]].concat();
        assert_eq!(c.decompress(&full, 8 + (OUT_ROOM as u32 - 1) * 8).unwrap().len(), OUT_ROOM - 1);
        assert!(c.decompress(&full, 8 + OUT_ROOM as u32 * 8).is_err());
    }

    /// Our trie must decode every code exactly as the decompress.dat tree used by LSB does.
    #[test]
    fn matches_server_tree() {
        let (Some(c), Ok(path)) = (codec(), std::env::var("FFXI_DECOMPRESS_TABLE")) else { return };
        let raw = std::fs::read(path).unwrap();
        let dec: Vec<u32> = raw.chunks(4).map(|w| u32::from_le_bytes(w.try_into().unwrap())).collect();
        let base = dec[0] - 4;
        for b in 0..=255u8 {
            let (code, len) = (c.codes[b as usize], c.lens[b as usize]);
            let mut node = ((dec[0] - base) / 4) as usize;
            for k in 0..len {
                let next = dec[node + ((code >> k) & 1) as usize];
                assert!(next > 0xff, "byte {b:#04x} leaves the tree early");
                node = ((next - base) / 4) as usize;
            }
            assert!(dec[node] == 0 && dec[node + 1] == 0, "byte {b:#04x} does not end on a leaf");
            assert_eq!(dec[node + 3], b as u32, "byte {b:#04x} decodes differently");
        }
    }
}
