# vana-client on Android

The APK does **not** ship FINAL FANTASY XI game data. Square Enix’s install is many gigabytes and must live on the device’s storage separately (for example under `Download`, `Documents`, or an SD card). The client only stores a path in `config.json` (`game_dir`) that points at that tree.

## Layout the client expects

`game_dir` is the folder that **contains** `FINAL FANTASY XI` (the same as a Windows install’s `PlayOnline\SquareEnix` or similar). Inside that folder the client looks for `FINAL FANTASY XI/VTABLE.DAT` and the rest of the retail files.

The first start has two steps:

1. **All files access**: *Open settings* and allow vana-client. The game files and installer volumes are read as plain paths on shared storage, so nothing loads without it.
2. **Game files**, from one of:
   - **Square Enix**: opens PlayOnline's download page. Download all five US volumes (`FFXIFullSetup_US.part1.exe`, `part2.rar` … `part5.rar`) into one folder under **Download**.
   - **Local installer**: browse **Download** (or the folder where the browser saved the five parts). Volumes are staged into `Install to/.download`, validated, then unpacked. When the install finishes, you choose whether to **delete** those staged files (~7 GB) or **keep** them (nothing is removed without your tap).
   - **Existing install**: pick a folder holding `FINAL FANTASY XI/VTABLE.DAT` (or a folder above it).

**Config → Game data** on the title screen changes the folder later. Config, mods, logs and caches stay in app storage.

### Clear app data

Android **Settings → Apps → vana-client → Storage → Clear data** (or **Clear storage**) removes everything in **app storage** only: `config.json`, saved logins, mods under the data dir, logs and caches. It does **not** delete game files under shared storage (for example `/sdcard/Game/FFXI` or a path you chose on an SD card).

After clear data the client has no config (`installed` is false again) and shows the **first-start** screen even when `VTABLE.DAT` is still on disk. Use **Existing install** to point at that folder and skip reinstalling. Installer archives in **Download** are also left on the device unless you removed them yourself.

When first-start finds an **incomplete or stale** install (partial files, `.vana-installing`, `.staging`, staged installer volumes, or a stale setup flag), it opens a **recovery** screen before the normal setup steps. You can **Check install complete** (validates `VTABLE.DAT`, `FTABLE.DAT`, FFXiMain, and staging markers — a complete tree continues into the game), **Wipe Game/FFXI folder** at the default path (`/storage/emulated/0/Game/FFXI`), or **Continue to setup** for a fresh or resumed local install. Custom install folders are never deleted automatically; **Wipe install folder** asks for confirmation first. A complete tree at the default path after **Clear data** is not treated as broken — use **Existing install** on the setup screen.

## Mods, addons, and Download

**Settings → Mods** scans **`/storage/emulated/0/Download`** (and subfolders) for zip/7z/rar packs and opens **Install from File** there. That needs **All files access** (same as playing in zones), or the folder stays empty in the app.

Drop LuAshitacast exports, DAT packs, or mod archives in Download, grant access, then use **Found in the Downloads folder** or **Install from File**.

## Full screen

The activity runs in **immersive** mode (status and navigation bars hidden; swipe from the edge to peek).

## Launcher icon

Mipmaps come from `crates/vana-client/assets/icon-256.png` (same as desktop). Regenerate with:

```bash
android/gen-icons.sh
```

## Release signing (sideload)

Every APK must be signed. For installs you keep updating on your own devices, use one **release keystore** (not the debug key):

```bash
android/gen-signing-key.sh
```

That creates `~/.config/vana-client-android/release.keystore` and writes `android/local.properties` (gitignored). Back up the keystore and passwords; changing the key requires uninstalling the app before installing a new APK.

Release builds pick up signing automatically. Override paths with `VANA_ANDROID_KEYSTORE` and related env vars (see `android/local.properties.example`).

CI (`.github/workflows/android.yml`) builds a debug-signed APK unless the repository has these Actions secrets, then a release-signed one:

- `VANA_ANDROID_KEYSTORE_BASE64`: the keystore file, `base64 -w0 release.keystore`
- `VANA_ANDROID_KEYSTORE_PASSWORD`, `VANA_ANDROID_KEY_PASSWORD`
- `VANA_ANDROID_KEY_ALIAS` (`vana-client` from `gen-signing-key.sh`)

## Building

`release/build-android-apk.sh` cross-compiles `libvana_client.so` (NDK 27, `cargo-ndk`) and packages the APK with Gradle as `target/assets/vana-client-android-aarch64.apk`; `VANA_ANDROID_APK_VARIANT=release` builds the signed release. Game files are never part of the APK.

Set `VANA_ANDROID_RELEASE_TAG=android-v1.0.14-rc4` when packaging locally so the APK's `versionName` matches the GitHub tag (the title **Update** window compares against those tags).

### GitHub Actions

**Actions → Android → Run workflow** (default branch `android`):

- **release_tag** — required. Use `android-v1.0.15-rc5`, or just `1.0.15-rc5` (the workflow adds the `android-v` prefix). Sets `versionName` to match and titles the release **Android 1.0.15-rc5**.
- **publish** — creates or updates a GitHub Release and attaches the APK (re-upload replaces the file on an existing tag).
- **prerelease** — leave on for release candidates.

A **push** to `android` or a **pull request** only uploads a workflow artifact; it does not publish a release. **Release builds** is for desktop binaries upstream; use **Android** for APKs.

## In-app updates

On the title screen, **Update** checks `arusiasotto/vana-client` for the newest `android-v*` release with `vana-client-android-aarch64.apk`, downloads it, and opens the system installer. Game-file patches still come from the PlayOnline patch server. Override the repo with `VANA_RELEASE_REPO` for test builds.