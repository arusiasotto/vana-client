## Auto-translate: the Items and Key Items groups, variable blocks (2026-11-11)

<!-- dll-build: 30261102_0 -->

Modlog-gaps item 138 ("Auto-translate: the item / key item groups built at run time (the 200-record item cache);
kind 6; the nested FD 06 block"). Addresses are 30261102_0 (MODLOG "Auto-translate: the dictionary" + 0x15d0 here:
FUN_101bb2b0 -> FUN_101bc880, FUN_101bb680 -> FUN_101bcc50, FUN_101bb740 -> FUN_101bcd10, FUN_101bc100 ->
FUN_101bd6d0, FUN_101ac5e0 -> FUN_101adbb0, FUN_101ac990 -> FUN_101adf60).

- The item record cache (DAT_10602620, 200 records of 0x294 bytes; id +0, lock byte +0x1b3, name +0x1b4). A lookup
  through FUN_1015d210(id) answers a held id from the cache (FUN_1015b580), else the record is read from its file
  into the next slot (FUN_1015b5c0: the index DAT_106229cc steps first and skips locked slots, so slot 1 fills first
  and slot 0 last). The name is the record's first string (parser field +0x14c8 = FUN_10258b20(rec, 0)), copied with
  strncpy(.., 0x20) and cut at +0x1d2: 30 bytes. About 35 functions call it (bags, equipment, shops, the auction
  house, /translate, /itemsearch, the phrase resolver itself).
- Not every record read takes a slot. In 30261006_0 the cache is filled only by FUN_10159ff0, called only from
  FUN_1015bc40 (= FUN_1015d210 above). A second path, FUN_1015b9e0, reads a record into a pool of 100 raw record
  buffers (FUN_1015b970 finds a loaded one, FUN_1015baf0 a free one) and never touches the cache. Message text takes
  that path: FUN_100be760's item cases 0x20..0x2a go through FUN_100be6a0 -> FUN_1015b9e0, and the RoE objective
  names through FUN_1015b9e0(id + 0xe000). FUN_100bdc50 .. FUN_100bf790, the event and battle message formatter,
  makes no FUN_1015bc40 call at all. So items named in battle or event messages do not join the Items group.
- Ours: `dat::items::Items` keeps the ring (`Recent`, ids and names only). `Items::item` takes a slot, and
  `Items::touch(id, name)` counts a lookup that `client::items::ItemCache::item` answered. `Items::peek` and
  `Items::noun` read without a slot. `noun` is the message text path (dialog, battle and system lines). `peek` covers
  the GM picker's scan over every id and every read a mod makes: `ItemCache::peek`, `peek_name`, `names::Peek` behind
  `text.plain`, mod window icons. `ItemCache` keeps the insertion that gave an id its slot and skips the lock while
  fewer than 200 insertions have passed (a slot is reused exactly 200 insertions later). Ours counts every
  `ItemCache::item` call, and about 40 retail functions read through the pool instead (some window code among
  them), so the cache's contents can differ from retail's in detail.
- One item reader: `dat::battle::BattleText` no longer holds a second `Items`. Battle and system lines read items,
  objectives and key items from the client's name tables passed in `battle::Ctx::names` (`battle::Tables`).
- An item phrase's text is that cache name: "Bronze Sword", not the log noun "bronze sword" ours showed
  (`NameSource::item_name`). Resolving one takes a cache slot (30261006_0: the resolver FUN_101bc100, case 7, calls
  FUN_1015bc40), so an item seen in chat joins the Items group.
- An item phrase's text is that cache name: "Bronze Sword", not the log noun "bronze sword" ours showed
  (`NameSource::item_name`). Resolving one takes a cache slot, so an item seen in chat joins the Items group.
- FUN_101bcd10 builds both groups again whenever the root category list opens: FUN_101bd060 (the query) calls it
  only with no word and no category, so a typed word completes against the groups as they stood at the last such
  open, and before the first one there are none. The group count D+0x224 goes back to the file's count D+0x228,
  then Key Items (FUN_101bcc50, slot D+0x218) and then Items (FUN_101bc880, slot D+0x214) each take the next slot
  when they have an entry. So the categories are the 42 file groups, Key Items, Items; a group with no entry is not
  listed. (This settles the order MODLOG left inferred.)
  - Items: every cache slot with an id, minus names starting '.' and ids 0x7400..0xfffe (FUN_101bc6d0); entry =
    4-byte id, length, name; the word's key is its text. Header kind 7, title / key group 0xb 0x91 / 0x92.
    FUN_101bc770 writes the block from the id's low 16 bits (a short read of record +0), so a cached id over 0xffff
    (it passes the filter) would name another item; ours does the same. No record over 0xffff exists in the files
    now (ours reads none: a record's id must match).
  - Ours leaves a group out when its title (group 0xb) did not load, so no blank category or empty brackets show.
  - Key Items: the key item table in file order (FUN_10155fb0 count, FUN_10155fc0(i) id, FUN_10155b20(i) name), the
    owned ones (FUN_1022c600 -> FUN_10097e50: bit id & 31 of DAT_10481068[id >> 5], the s2c 0x055 bits), ending at
    the first owned id 0x181..0x183, 0xfe at most. Header kind 0x13, title / key 0x93 / 0x94.
  - Ids never hold a 00 byte: base kind, + 1 for id 0 (FF FF), + 2 when the high byte is 0 (FF lo), + 3 when the
    low byte is 0 (hi FF).
- A category is found by FUN_101bc640: a file group by its group byte, else a built group by its raw kind byte (7 /
  0x13). The list's Enter (FUN_101ae200) treats a candidate as a category when its id's last byte is 0, which the
  00-free ids above never are. Ours tested `kind < 7` as well, which kept the two built categories from opening.
- Resolver FUN_101bd6d0: the kind is folded to 7 (7..0x12) or 0x13 (0x13..) first (checked in Rizin at 0x101bd73f;
  the jump table's cases 0xb / 0xf with slots D+0x220 / D+0x21c are dead). The id comes from the raw kind: 7 / 0xb /
  0xf / 0x13 both bytes, 9 / 0xd / 0x11 / 0x15 the low byte, 0xa / 0xe / 0x12 / 0x16 the high byte, any other kind 0.
  Item id 0 is the Items group's title only while that group stands, else nothing (the line ends); key item id 0
  the Key Items title while that stands, else key item 0's name. Ours gave the titles always and read kinds past
  0x16 as ids.
- Variable blocks (kind 6), FUN_101adbb0: `FD 06 x x x nn <nn bytes> x`, nn + 7 bytes, nn a signed byte (over 0x7f
  the line ends). The nn bytes are a template copied out as they are; each FD in it starts a 6-byte place. For a
  place the function calls itself on the bytes after the variable block (0x101add61: source + consumed): a block
  there is expanded without brackets or colour in the place and used up; a 6-byte block of kind 6 there is read as
  a variable block whose length byte is FD (negative), so it fails. With no block there the place's four id bytes
  go to the resolver, which reads kind 6 (as any kind under 7) as a phrase by its group and id bytes. A following
  block that fails ends the line, and the template's text before it goes too: the call builds its text in a stack
  buffer and copies it out only when it succeeds, and the expander copies nothing of a failed call. A place's id
  that fails adds the resolver's -1 to that buffer's length (the byte before it in this call's text goes; ours
  removes nothing when the text is still empty, where retail's length wraps and the next byte lands outside the
  buffer). The variable block itself gets no brackets. No code in the DLL writes one (no FD / 06 pair among its
  seven 0xFD stores).
- Ours: `font::decode_sjis` keeps a variable block's bytes one char a byte (so `encode_sjis` gives them back),
  `autotrans::Dictionary::expand` / `variable` expand it; `Dictionary::rebuild` / `built` are the two groups, rebuilt
  by `fep`'s query on the root list.
- Not built: the cache's lock byte (transient, during the scans) and FUN_1015b5c0's second argument (a record handed
  in by the caller reuses its slot). The Japanese / French second keys do not apply to these groups (entries of
  kinds 7..0x12 never have one; key item entries are loaded by FUN_101bbcb0 with the name as text and key).
- Tests: `dat::autotrans::tests::built_groups`, `untitled_groups`, `variable_block`, `english_dictionary` (Bronze
  Sword, the group from the cache), `dat::items::tests::record_cache_ring`, `stamps`, `client::items::peek_tests`,
  `dat::battle::tests::items_from_shared_names`. Not checked live.
