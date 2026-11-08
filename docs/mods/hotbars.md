# Hotbars: macro bars by job

Hotbars is a bundled mod (from Arusia's VCHotbar, PR #88): up to three bars of up to twelve slots over the chat
window. Each slot holds a macro of as many lines as you like. Its action's icon shows on the slot (the first spell,
ability, weapon skill or item a line names), with a shade and the time left while it recasts; a slot with no action
shows its label. Turn it on in Config → Extras, on its page (Hotbars), where its size and place are set too.

The bars load by main job: each job has its own bars and its own library of macros.

## Building macros

The manager (`//hb`) has three pages.

- **Library:** the job's macros (the Job line picks another job). New, Edit, Copy, Delete (which empties the slots it
  is on) and Palette. The Slots column shows how many slots each macro is on; editing a macro changes all of them.
- **Builder:** pick the **Type**: Spell, Job ability, Weapon skill, Pet command, Item, Equip, Command or Macro. Search
  what you can use (the spells you have learned, the abilities in your lists, the usable items you carry, the
  equipment in your inventory and wardrobes, the common system commands such as `/attack`, `/heal`, `/assist`,
  `/lockon`, `/ra`), pick one, and pick its **Target** (`<t>`, `<me>`, `<stpc>`, ...; a pick starts on its usual one,
  and a command such as `/heal` takes none) or, to equip, its **Equipment slot**. That builds the first line,
  `/ma "Cure" <me>`, `/attack <t>` or `/equip ring1 "Warp Ring"`; lines typed under it run after it
  (`/p Curing <me> | /wait 2`). A **Macro** is typed lines only. The line at the foot shows what the macro will run; **Save** keeps it in the library.
- **Config:** each bar's hotkey modifier and the key row.

**Palette:** `//hb palette` (or the Library's Palette button) shows the job's macros as tiles over the bars. Drag a
tile onto a slot to put it there; click one to edit it.

## On the bars

- **Keys:** bar 1 takes `1`..`0`, `-`, `=`; bar 2 the same with Ctrl, bar 3 with Alt. The manager's Config page picks
  each bar's modifier and the key row (number row, function keys or the numpad). A slot shows its key in its corner.
- **Click** a slot to run it; **right-click** to open the manager (on that slot's macro) or clear the slot; **drag** a
  slot onto another to swap them.
- **Hover** a slot for its name and lines.
- The job over the top bar opens the manager.

The game's macro palette hides while the bars show (Hide Stock Macro Bar); its Ctrl and Alt keys still run its
macros unless a bar uses them.

## Macros

Each line runs as typed. `/wait 2` on its own line waits two seconds; `<wait 2>` at the end of a line waits after it.
A macro still running ignores a second press.

The macros are kept in `mod-data/hotbar/files/macros.json`:

```json
{
  "WAR": {
    "library": {
      "1": { "name": "Utsusemi", "action": { "kind": "ma", "name": "Utsusemi: Ichi", "target": "me" }, "lines": [] },
      "2": { "name": "Warp", "action": { "kind": "equip", "name": "Warp Ring", "target": "ring1" }, "lines": [] }
    },
    "main": { "1": { "1": { "ref": "1" }, "2": { "name": "Provoke", "lines": ["/ja \"Provoke\" <t>"] } } }
  }
}
```

A slot holds `{"ref": "<id>"}`, a library macro, or a macro of its own (from before the library), which still runs
and can be cleared. Sets kept under `"sub"` by earlier versions are no longer used.

## Commands

- `//hb` opens or closes the manager.
- `//hb show`, `//hb hide`: the bars for this session.
- `//hb palette` shows or hides the palette of the job's macros.
- `//hb run <bar> <slot>`: runs a slot (for a key bind).
- `//hb reload`: reads macros.json again.
- `//hb wipestock` empties the game's own macro sets after keeping a copy; `//hb restorestock` puts it back.
