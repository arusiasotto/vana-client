## Battle messages name merit, job point and alter ego point entries; modern Status says alter ego points (2026-11-18)

<!-- dll-build: 30261102_0 -->

**Retail.** Battle message 828 (file 7027, language slot 0x63) is `7f b7 00 attribute increased to 12 01.`: retail
answers each alter ego point upgrade with s2c 0x029, Data the attribute id (8 Max HP .. 18 Magic Skills), Data2 the
new level (checked against retail captures), and FUN_100c1650 prints `7f b7 n` as the name of work[n] from the alter
ego point names (language slot 0x20, entry 2 * id), `7f b0` / `b1` the same way from the merit and job point names.
So retail logs "Max HP attribute increased to 2." Our battle expander skipped those codes and logged
" attribute increased to 2."

**Ours.** `battle::Ctx::texts` carries the point names (`event::point_texts`, the tables dialogue lines already use)
and `7f b0` / `b1` / `b7` read them as `dialog::expand` does; `7f b5` reads the Monstrosity names the same way.
Every battle line in the client, and the mods' battle message expand, takes its context from `combat::ctx`, which
fills the name tables and our name. World keeps one copy of the tables while the game data stays the same, so each
point, Monstrosity or grammar table is read from disk once.

**Modern Status page.** Row 13's English help since build 30261102 (menu message file 55651) is "View Faith Points
and change Celestite for each alter ego type.", keeping the Japanese name; every other English line says alter ego
points. The modern page shows "alter ego points" there; the classic window keeps retail's text.

Tests `point_names`, `alter_ego_upgrade_line` (game data), `alter_ego_help`.
