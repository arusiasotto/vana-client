## Map datagrams: the coder's plain form and size limits (2026-11-15)

<!-- dll-build: 30261102_0 -->

Queue row 149. The row quoted the Zone notes' "Later: Huffman-compressed payload ... MD5, then Blowfish over whole
8-byte blocks" as not built. "Later" there meant the datagrams after the first one: the compression, the MD5 and the
cipher were already built and every session uses them. So this was an audit of net/map against the coder, and
it turned up the differences below. All addresses are build 30261102_0 (the Zone notes' 0x100dcae0 / 0x100dcb90 /
0x100dcc90 are from an older build).

**The functions.**
- FUN_100dd590 (out, room 0x550, cipher or 0, header + sub-packets, length, code table): the datagram a send makes.
  FUN_100fab40 calls it with no cipher in connection states 1 and 2 (the login) and the send cipher in state 3.
- FUN_100dd6c0 (out, room 10000, cipher, tree, datagram, length): the datagram a read takes. FUN_100fa710 calls it.
- FUN_100df7c0 compresses, FUN_100df5d0 decompresses, FUN_100df780 is the compressed length in bytes of some input,
  FUN_100df6e0 writes one code's bits.
- FUN_100dd520 keys a cipher: the key is strncpy'd (0x50) into the context, its length is fixed at 0x10, and
  FUN_100dc710 is the key schedule. FUN_100fa000 keys two contexts from the same string, +0x2020 for reads and
  +0x30c0 for sends. FUN_100dd570 counts datagrams at context +0x109c; nothing reads the count, so the key never
  changes during a session.
- FUN_100dca00 / FUN_100dcf60 encipher / decipher `length >> 3` blocks; FUN_100dc8e0 / FUN_100dc970 are the single
  block forms. FUN_100dde90 / FUN_100ddec0 / FUN_100ddf60 are MD5 init / update / final.

**Sending (FUN_100dd590).**
1. The 28-byte header is copied.
2. With no cipher and a body, the body is copied as it is (the first 0x00A). Otherwise FUN_100df7c0 compresses it
   into the room less 0x2c (0x524 bytes) and the size field, a u32 of bits, goes behind `(bits + 7) / 8` bytes.
3. If body + field + 0x2c passes the room the datagram is not made (-1). FUN_100fab40 then sends nothing and the
   sequence does not move.
4. MD5 over body + field goes behind the field; with a cipher, body + field + MD5 are enciphered in whole blocks.

**The compressor (FUN_100df7c0).** Byte by byte it adds the code's length (table +0x600, indexed by the byte as a
signed char) and writes the code's bits (+0x200) LSB first behind the leading byte. Before each write it tests
`(room - 1) * 8 <= bits so far + this code`:
- never true: the leading byte is 1 and the result is the bits + 8.
- true: the output is zeroed, the input is copied behind a leading **0** and the result is `(length + 1) * 8`,
  if `length + 1 <= room`; if not, -1.

With the room at 0x524 the plain form starts at 10,520 code bits. The compressed form only leaves FUN_100dd590 up to
10,488 bits (1 + 1311 bytes, + 4 + 0x2c = 0x550), so code lengths of 10,489..10,519 bits make no datagram at all, and
from 10,520 the body goes plain if it is at most 1311 bytes. The retail table's codes are 1 to 12 bits (232 of the
256 are over 8), so bodies that are mostly rare bytes reach the plain form.

**Reading (FUN_100dd6c0).**
1. Refused (-1) when the length is over 0x550 or under 0x2d. (FUN_100dc670 reads the socket into 0x550 bytes, so a
   longer datagram already fails the read.)
2. Deciphered from the header on, `(length - 0x1c) >> 3` blocks. This is done in every connection state.
3. MD5 over `[0x1c, length - 0x10)` against the last 16 bytes: a mismatch returns 0.
4. FUN_100df5d0 gets the body, the u32 at `length - 0x14` as the bit count, and 10000 - 0x1c bytes of output.

**The decompressor (FUN_100df5d0).**
- Leading byte not 1: `(bits - 8) >> 3` bytes are copied from behind it. That is the plain form above.
- Leading byte 1: `bits - 8` bits are walked through the tree, LSB first; a leaf (both children null) gives its byte
  and the walk restarts at the root. A code the count cuts short gives nothing. When the output count reaches the
  room the result is -1.
- `bits - 8` is unsigned and not compared with the datagram's length: a field under 8, or one past the data, reads
  whatever lies behind the datagram on the stack.

**What FUN_100fa710 does with the result.** 0 (MD5): counter slot 0 (FUN_100fab10, session +0x40ea4), dropped. Below
0: slot 1, dropped. Neither ends the session; nothing in the read path does.

**What matched already.** The cipher (round function, the sign-extended key bytes, key = MD5 of the 20 bytes cut at
its first zero, 16 bytes always), the block counts, the MD5 ranges, the raw first 0x00A, the code table and bit
order, the 0x550 send limit and the 3999-byte build limit (FUN_100fdd40). FUN_100fdd40 also stops at a compressed
size, `config +0x448 - 0x31`, but nothing writes +0x448 (the config is zeroed at start and no instruction in any
function that uses its pointer stores there), so the unsigned test never trips.

**What changed in ours.**
- `Codec::pack` is FUN_100df7c0 with its room: compressed, plain behind a 0, or nothing. `MapSession` sends through
  it, and `sendable` is FUN_100dd590's whole rule (compressed up to 10,488 bits, plain from 10,520 up to 1311 bytes),
  used when choosing how many waiting sub-packets a datagram takes. Before, anything over 10,488 bits was split
  over several datagrams.
- `Codec::decompress` reads the plain form (before: an error, the datagram dropped), fails at 9972 output bytes, and
  fails on a field under 8.
- A read takes 0x2d..=0x550 bytes (before: 48 and up, no upper limit) and takes the size field from 20 bytes before
  the end wherever that falls, with everything behind the header as the compressor's input. On Windows a datagram
  longer than our buffer fails the read (WSAEMSGSIZE); that is a drop now, not the end of the session.

**Ours, kept on purpose.**
- A field past the data is cut to the data; retail reads its stack.
- When the waiting sub-packets do not fit one datagram, the newest wait for the next one. Retail builds the same
  oversized body again each time and sends nothing.
- 50 unreadable datagrams in a row end the session with the reason ("Map session: unreadable datagrams",
  2026-11-02); retail only counts them.

**Tests.** `stored_form`, `decompress_limits` (compress.rs); `sendable_forms`, `plain_form_both_ways`,
`datagram_size_bounds`, and `datagram_size_limit` / `bad_datagram_dropped` updated (session.rs).
