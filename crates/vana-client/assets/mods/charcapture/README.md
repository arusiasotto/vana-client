# Character Capture

Port of [vanadreams-launcher charcapture](https://github.com/VanaDreams/vanadreams-launcher/tree/main/addons/charcapture) for vana-client.

`//capture` writes a schema-1 JSON snapshot to `shared/charcapture/<Name>.json` in the client's mod data (`mod-data/.shared/charcapture/` on disk). `//capture show` repeats the last summary.

Use the same prep as the Ashita addon: zone once, open Merit Points, Job Points, and both Currencies tabs, switch jobs in your Mog House for skills, ride your chocobo if you have one, and switch to PUP once for your automaton.

Load the mod with `/lua load charcapture`, grant `packets.read` and `files.shared` when asked, then `//capture`.