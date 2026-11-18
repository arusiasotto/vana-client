## PlayOnline patch client: what the Viewer does beyond the frames (src/patch.rs) (2026-11-15)

Queue row 148, the "Not yet" of "Game file updates (PlayOnline patch protocol; src/patch.rs)" (2026-10-22): the
protocol facts there were Kuluu's notes, not checked against a decompile. Read now from the Viewer installed here
(self-updated, PlayOnlineViewer/viewer/com): **app.dll, file version 1.18.13**, holds the patch client the live
server talks to (state machine FUN_10018bca, 2,643 decompiled lines; its state is at +0x466a4c, its pass at
+0x466a50). **polcore.dll 1.18.12** holds an older copy of the same machine (FUN_1002d22e, state +0x469a4c) with no
zlib and a size-only file check; it is not the one that runs. Addresses below are app.dll's unless marked
*polcore*. Live checks are against pc001.pol.com:53001 on 2026-11-15 (read-only requests).

Confirmed as the 2026-10-22 entry had them: the frame (length, MD5 word, "POLP", kind; builders FUN_10017535 hello,
FUN_100175cd file request, FUN_100176fa version; checks FUN_10017759 / FUN_10017827 -> -0x48a), the tags, the
manifest reply (status byte 2 at +0x10, else -0x482; the frame's MD5 word is checked over the whole stream, -0x48a),
the chunk layout (+0x10 offset, +0x14 length, +0x18 extra length, extra = the path echoed back, then data), the
signature (worker op 0x10: signed byte sum, MD5 word 0, length), the download flag byte (state 0x5df: 1 stored,
3 zlib, else `.slc`; live: every Direct file sampled starts 03 78 9c), `.slc` (*polcore* FUN_1003d8a5: flag bit,
then u16 distance + u8 length, or a literal byte) and `.olc` (*polcore* FUN_1003de31: 0 literal, 10 output copy,
11 copy from the base at output position + i16). Paths with spaces: FUN_10027b95 protects the spaces of a `file`
line's name and of the last path component before `.slc` / `.olc`, so they are read as ours reads them (polcore's
older lexer split them).

**The version check (states 0x26a .. 0x26e).**
- The 0x40-byte block is the version in patch.ver (+0x446348; blank without the file), not always zero. Live: a
  blank block is answered with the label "empty", a version-shaped one ("30261006_0", also "99999999_9") with
  "registered", anything else with "unknown".
- "unknown" ends the update with -0x48f and deletes patch.ver (states 0x26c / 0x26d), so the next run asks blank.
- The reply's 0x40-byte field holds more strings after the label (FUN_10021fe3 steps over a NUL): the host to
  download from, which retail resolves and, when it resolves, uses for every later connection (FUN_100220a0 ->
  DAT_109bf6a0, read at the connect, 0x100225e4), then a number only titles 0 and 1000 (the Viewer itself) pass on.
  Live: the host is the address pc001.pol.com resolves to, the number "0".
- Nothing to fetch (state 0x26e): the server's string and the applied one are as long, and the server's is not
  the newer by FUN_10017f3a (base 37: digits, A-Z = 10..35, `_` skipped, any other character 0, stops at a space).
- Any other tags than "W20\0" "0001" are answered with frame 5 (live: W10, WIN, PS2, X36, title "FFXI").

**The passes.** 100 the version check; 200 the manifest and the check of every file (sizes summed, a work list
written as patch2.cfg, state 0x834..0x83d); 300 the downloads, read back from patch2.cfg; 400 the renames; 500
done. The manifest is fetched as patch.cfg.tmp1, decoded to patch.cfg.tmp2, renamed to patch.cfg, and patch.ver is
deleted right after (state 0x2cf); it is written again (encrypted with a registry key, 0x120 bytes) only when a
pass ends with nothing left to do (state 0x6a4..0x6a9).
- With a version applied, a file whose newest line is not newer than it (FUN_10017f3a on the line's stamp) is not
  read at all, in pass 200 (state 0x385) and in pass 400 (state 1000).
- Else the signature of `<name>.tmp2` is taken, then the file's (states 0x387 .. 0x389). The last line that
  matches all three numbers decides (state 0x44c): the newest = current; an older one = the deltas after it when
  a version is applied, every later line has one and their sum is smaller than the newest whole file, else the
  whole file. No local file: the whole file, except in an `option` block, where it is left out (state 0x4b0).
- A `.tmp2` that matches no line is deleted and the file checked again ("illegal tmp2 file rollback", 0x44d).
- A download goes to `<name>.tmp`, is decoded to `<name>.tmp2` and checked against the newest line (-0x48c, the
  `.tmp2` deleted). A delta goes to `.tmp`, is applied to the file (or to the `.tmp2` when that was the match,
  state 0x649) into `.tmp3`, which becomes `.tmp2`, checked against its own line (-0x48d).
- Pass 400 renames every `.tmp2` over its file. So the game's files stay as they were until everything is
  fetched, and a stopped update is picked up from the `.tmp2` files.
- Before each file of pass 300, when the last request is more than 60 s old (FUN_10021f15), a version frame
  goes out and its reply is awaited (states 2000 / 0x7d1).
- Requests are 0x10000 bytes at most; a longer chunk is -0x489. A reply later than the caller's timeout
  (+0x777a48, 0 = none) reconnects and asks again up to the caller's retry count (+0x777a4c), then -0x489.
- Manifest blocks (first word in lower case, FUN_10027abc): `reset {`, `reset2 {`, `select {`, `option {` around
  `file` blocks, `end`. A replaced `reset` file ends the run with result 2 and a `reset2` one with 4 (the Viewer
  restarts), the first `reset2` name of each block listed in patch.rst. FFXI's manifest has none: 49,427 `file`
  blocks, 5,538 lines with a delta, 20 lines with spaces in a path.
- A name holding `__XXX__` is left out unless XXX is the caller's three-letter code, which is then cut from the
  name (FUN_10021a5c / FUN_10021af3). FFXI's manifest has no such name.

**Ours now.**
- `Session::version` sends the version applied here (the newest stamp in vana-update.cfg); the reply's host is
  kept (`ServerVersion::host`) and the manifest and file connections go there (`Session::connect_to`), falling
  back to pc001.pol.com when it does not resolve.
- `behind` uses retail's test (`up_to_date`, `stamp_num`). `plan` skips files with no line newer than the
  applied version (`check`), reads `<name>.tmp2` first, takes deltas only with a version applied, leaves a
  missing `option` file out, and lists `.tmp2` files that match nothing for `apply` to delete.
  `vana-client update --full` asks blank and reads every file, as retail does without its patch.ver.
- `apply` stages every file as `<name>.tmp2` (through `<name>.tmp`), then renames them all, then writes the
  stamp. A staged current version (`Action::Staged`) only moves; a staged older one is the delta base
  (`Action::StagedDeltas`). Connections open at the first file to fetch.
- Keep-alive after 60 s without a request; a chunk longer than 64 KiB is refused; manifest blocks parsed
  (`Attr`).
- Live: `update --dry-run` is answered "registered" and finds 49,427 files current; a scratch folder holding
  ROM/21/40.DAT one version back, ROM/24/48.DAT two versions back, a staged old ROM/82/64.DAT beside a wrong
  file, and no patch.sin came out matching the manifest (deltas in one and two steps, a whole file).
- Not retail: an "unknown" answer is followed by a blank check in the same run, and vana-update.cfg is kept (it is
  also what FFXiMain.dll is matched against), so a stopped run still takes deltas. FFXiMain.dll is read past the
  version skip, and the start-up check offers an update, while the copy the client reads lags (`code_lags`): it
  misses the stamped manifest (a `--data-only` run, an install patched before the copy existed), or the Viewer
  patched the folder past the stamp and our copy differs from the folder's. Retail keeps no such copy. No patch.cfg /
  patch2.cfg / patch.ver / patch.rst files: the manifest and the work list stay in memory, and nothing of this client
  restarts on a `reset` file (the count is logged). Several download connections where retail has one. No caller
  timeout or retry count: 120 s socket timeouts end the run.
- A back copy longer than its distance repeats the bytes in ours; retail copies with memmove (*polcore*
  FUN_10056d30), which would read bytes not written yet. None of the 626,851 copies in the live manifest stream is
  one, and every result is checked against its signature.
- Open: the `__XXX__` name code (the caller's value is not known; such names are not filtered), and the free-space
  check (pass 200 sums the largest version of every file to change at +0x466a68 and state 0x76d reads the free
  space into +0x466a60; the comparison is in the caller, not read).
