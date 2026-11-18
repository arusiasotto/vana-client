## PlayOnline: the Viewer's version check and update, patch.ver, the 2026-09-28 Viewer rebuild (2026-11-16)

Addresses are the rebuilt Viewer's (polcore.dll 3c07c1a3, app.dll 97f99a0a) unless marked 1.18.15e.

- The rebuild: polcore.dll and app.dll built 2026-09-28 with another compiler, no POL1 packer, code-signed; FileVersion
  still 1.18.12 / 1.18.13 (version.dat "1.18.15f", for show only). Its polcore, driven through its function table as
  app.dll drives it against a mock chat / profile server, sends the same 22 chat lines and profile frames as 1.18.15e
  (member login 4/7, both ChangeMyStatus, 4/6, 0/9, 1/3) and makes the same authCode (table 0x3a8) from the same
  inputs: net/pol needed no change for it.
- app.dll's sign-in uses the same polcore transactions, order and arguments as 1.18.15e: the login state machine
  FUN_1013fb5c (1.18.15e FUN_101aacd4) differs only by compiler. Its LoadMyStatus success handler (vtable 0x104bac48
  slot 4, 0x102df51e; 1.18.15e 0x10040650) queues Get Friend List 2/3, Get Handle List 0/9, Get Chr List 1/3 and Get Grp
  List 7/c (polcore table 0xa3/0xa4, 0xab/0xac, 0xaf/0xb0, 0x17f/0x180); the content window task (FUN_102e3194) then
  sends ChangeMyStatus (handle, -2, 1, 2, 0, -2). 2/3 and 7/c have no body (header only).
- The Viewer's version check: app.dll's start-up flow runs it at step 8 (FUN_10149792(1000) -> FUN_1014d934), before
  the sign-in (step 0x23, CLoginConnectionPolFrame), and the reconnect flow at step 5 (CReconnectionVersionCheck,
  FUN_1012de94 / FUN_10131a26, "Checking PlayOnline Viewer version..." 0x5670).
  - Server: env.dat's PATCH_SERVER_DOMAIN (decrypted by polcore table 0x400): pt008.pol.com; port 53000 + title, the
    Viewer's title 1000: TCP 54000 (FUN_1001795d).
  - Request: frame kind 7, 0x58 bytes: `58000000 <MD5(frame[8..])[0..4]> "POLP" 07000000 "W20\0" "1000" <0x40-byte
    version block>`. The reconnect check sends the block zero; the start-up check puts the local version string in it.
    The platform tag comes from {"W20", "DWJ", "W2U", "DWU"} (0x104be4d4, FUN_102fb06e; "W20" on a US install,
    *inferred*). Nothing of the member goes with it.
  - Reply: kind 8, the same layout the FFXI check reads (+0x58 u32 length, +0x5c the version string); a label
    "unknown" at +0x18 fails the start-up check (0xfffffb71).
  - Decision (FUN_10017ec7 / FUN_10017f3a): current only when the local string is as long as the server's and its
    value (polcore FUN_10048560: base 37 to the first NUL or space, '0'..'9' 0..9, 'A'..'Z' 10..35, '_' skipped, any
    other character a 0 digit, 64-bit) is not lower. Else string 0x36c5 "Please update %s in order to proceed." and the
    update steps; a failed connection is 0x5654 "Network Connection Error"; the reconnect flow disconnects and ends
    with 0x5a19.
  - The local version: the Viewer folder's patch.ver, decrypted by polcore table 0x493 (FUN_10045410(in, out, 0x100,
    1000)) with the key in registry SOFTWARE\PlayOnlineUS\Interface value "1000" (value names are the title as %04d);
    20261022_0 after the 2026-11-16 update, the same as patch.cfg's newest stamp.
- The game's patch.ver decrypts the same way with title 1 (Interface "0001"): 30261102_0 for the November update, the
  version the client already sends in 0x26 (from the applied manifest). FFXiMain copies the string with its 4 bytes
  after the NUL (stale bytes, e.g. "LAUD" ff); the lobby takes zeros there.
- Seen 2026-11-16: with the Viewer folder's install not yet updated, ffxi00.pol.com closed the view link right after
  0x26 three times (no reply, no 0x04), though chat and profile had answered every step. After the Viewer was updated
  and a sign-in made with it, the same client's 0x26 was answered. The cause is not known *(inferred: something the
  server keeps for the member or the address)*.
- The Viewer's update (app.dll sqPatchMain FUN_10018bca, unchanged since 1.18.15e), one pass on the same service, every
  frame tagged "W20\0" "1000", no login: mode 100 version (kind 7 with the local version in the block), 200 prepare
  (kind 1 hello, kind 2 manifest, saved as the folder's patch.cfg; the to-do list in patch2.cfg), 300 download (kind 3
  / 4 as for the game: whole files or .olc chains, staged as `<p>.tmp2`, each checked), 400 install (renames, then
  patch.ver with the server's version under table 0x492, then patch.rst). Paths are relative to the Viewer folder.
  - The manifest wraps file blocks in attribute blocks (line parser FUN_1002823c): `Reset2 {` (0x80, in use: renamed
    at the next start through patch.ini and util\startpol.exe /REPLACEPOLEXE), `Option {` (0x40, only when the file
    is there: EU/option.bin, EU/env.dat, patchfiles/PlayOnlineViewer/viewer/com/{app,appEU,polcore,polcoreEU}.dll),
    `Reset {` (2, a Windows restart), `Select {` (4). A path with `__XYZ__` is kept only for platform XYZ, the
    marker taken out (FUN_10021a5c / FUN_10021af3).
  - app.dll and polcore.dll are fetched only as the patchfiles/ copies; pol.exe copies them into viewer\com at its
    next start (FUN_0042bbf0 / FUN_00425220) *(inferred: the copy)*.
  - Size, 20261022_0: 486 files, 255.8 MB installed, 209.8 MB of .slc (204.1 without the Option files); the last
    step 14 files, 8.3 MB.
- patch.ver (net/pol/patchver.rs): the *5-chain cipher of the authCode (polcore 1.18.00n FUN_100081b0: FUN_10007f30's
  schedule, FUN_10008100 = blocks then the {length, checksum} tag), 0x120 bytes = 0x118 of data and the tag. The data
  is zero but for the version string at +0x18. The key (FUN_10048410): the registry value's bytes summed into 8 lanes
  (FUN_10048330) plus the title as a 64-bit add (FUN_10048200); with no value, or when it does not open the file, the
  title alone. Checked 2026-11-16: the Wine install's two files read as above, and files written with the title's
  key are read by polcore's table 0x493 for both titles.
- Ours: the Update window's PlayOnline Viewer row (for a player with a PlayOnline log-in) runs the Viewer's update
  into config::viewer_dir (patch.rs VIEWER: every file written at its path, code included, never run; an absent
  Option file left away; staged and renamed as the game's files are; no patch.ini or patch.rst), then our stamp and
  patch.ver last. The row's check asks with the local version (the start-up form); a PlayOnline log-in first runs
  the reconnect form (a blank block, 15 s to connect, 30 s to answer) against that patch.ver; out of date or
  missing, or no answer, stops it before the sign-in with the Viewer's strings 0x36c5 / 0x5654. The game's update
  writes no patch.ver: its code files stay behind, so a real install's patch.ver must keep telling the Viewer to
  patch them. The game's applied version is the newer of our stamp's and a patch.ver the Viewer wrote (installer
  key "0"). The sign-in sends 2/3 and 7/c where app.dll does, the replies read past
  (ReplyBody::Sized, the length in the reply header) and a failure only logged. A lobby hang-up on 0x26 says to sign
  in once with the PlayOnline Viewer.
