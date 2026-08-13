<div align="center">

<img src="docs/perch.png" width="128" alt="Perch icon">

# Perch 🐦

**Folders always on top in Finder — with any sort order.**

![platform](https://img.shields.io/badge/macOS-13%2B-blue)
![arch](https://img.shields.io/badge/Apple%20Silicon-arm64e-black)
![version](https://img.shields.io/badge/version-1.0-brightgreen)
![license](https://img.shields.io/badge/license-Personal%20Use%20Only-orange)

</div>

---

## What it is

macOS keeps folders on top **only** when sorting by name. Sort by date, size
or kind and folders get mixed in with files. Grouping by kind helps halfway,
but breaks the list into sections.

**Perch** removes that limitation: folders stay on top **with any sort order**,
while the files below them remain a single continuous list in the order you
chose (for example, by date). It lives in the menu bar and is toggled on with
a single switch.

<div align="center">
<em>Sort files by date — and still see every folder on top.</em>
</div>

---

## How it works

Perch hooks Finder's private method
`-[… shouldSortFoldersFirstForSortBy:groupBy:]` and makes it always return
`YES`. Technically it's a tiny `foldertop_hook.dylib` that is loaded **into
Finder only** via `DYLD_INSERT_LIBRARIES` (in every other process the
constructor bails out immediately after checking the bundle id).

The menu-bar app just orchestrates this: it copies the library, installs a
LaunchAgent and restarts Finder. When you delete the app, the LaunchAgent
cleans itself up.

---

## ⚠️ Important: one-time system setup required

For macOS to allow loading a third-party library into Finder, you must relax
security **once** in **Recovery mode**:

```
csrutil disable
nvram boot-args="amfi_get_out_of_my_way=0x1"
```

This is a deliberate trade-off: **you are disabling part of macOS security
(SIP / AMFI)**. Do this only if you understand the consequences. Everything is
entirely at your own risk. The app shows the exact steps on screen
("How to set up…").

To turn it back off: in Recovery enable Full Security and run
`sudo nvram -d boot-args` in Terminal.

---

## Installation

1. Download `Perch.dmg` from [**Releases**](../../releases/latest).
2. Open the image and drag **Perch** into **Applications**.
3. Launch Perch (its icon appears in the menu bar).
4. Complete the one-time system setup ("How to set up…" button).
5. Turn on the **"Folders on top"** switch — Finder will restart.

> For "Launch at login" to work, the app must live in `/Applications`.

---

## Build from source

Requires macOS with Xcode Command Line Tools (Apple Silicon).

```bash
git clone https://github.com/DeeMon4eg/Perch.git
cd Perch/app
./build-app.sh      # builds the dylib, the app and the icons → ../Perch.app
# or produce a DMG directly:
./make-dmg.sh       # → ../Perch.dmg
```

`build-app.sh` compiles `foldertop_hook.dylib` (arm64e) itself, builds
`Perch.app`, generates the icons and ad-hoc signs the bundle.

### Layout

| File | Purpose |
|------|---------|
| `foldertop_hook.m`    | the hook: intercepts Finder's sort method |
| `app/main.swift`      | menu-bar app (UI, installer, LaunchAgent) |
| `app/build-app.sh`    | build the `.app` from source |
| `app/make-dmg.sh`     | package into a `.dmg` |
| `app/makeicons.swift` | icon generation |
| `app/Info.plist`      | bundle manifest |

---

## Uninstall

Perch menu → **"Uninstall Perch…"**. Folders go back to their normal order,
the add-on is removed from Finder, and the app is moved to Trash. The
LaunchAgent and support files are removed automatically.

---

## Support

Perch is free. If you find it useful, you can support the author via
[Boosty](https://boosty.to/sibainka/donate). Thank you!

---

## License

**Personal, non-commercial use only.** See [LICENSE](LICENSE). Commercial use,
resale and redistribution are prohibited without the author's written
permission.

© 2026 DeeMon4eg
