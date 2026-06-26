# LunaTranslator on Arch Linux (Wine)

Run LunaTranslator — with **HOOK** (visual novels), **overlay**, and **OCR**
(browser games) — natively-installed on Arch via Wine. 

---

## Install

```sh
# From the AUR (once published):
paru -S lunatranslator-wine        # or: yay -S lunatranslator-wine

# Or build locally from this repo:
cd linux
makepkg -si
```

First launch downloads the official portable build once, into
`~/.local/share/lunatranslator/app`. After that **LunaTranslator updates
itself** (its built-in updater); `pacman -Syu` only refreshes these wrappers.

```sh
lunatranslator             # launch: general OCR + clipboard translation
lunatranslator-bootstrap   # (optional) pre-fetch the app without launching
```

---

## Hooking a specific game

HOOK requires LunaTranslator and the game to share **one Wine prefix**. Pick the
wrapper for how you launch the game. Hardened/most-reliable first.

### 1. Manual `.exe` (most reliable)

```sh
lunatranslator-run /path/to/game.exe
lunatranslator-run --prefix ~/.local/share/wineprefixes/myvn /path/to/game.exe
lunatranslator-run --wine /usr/bin/wine64 /path/to/game.exe
```

Starts LunaTranslator, waits for it to come up, then launches the game in the
same prefix. A **"Run with LunaTranslator"** entry is also added to your file
manager's right-click menu for `.exe` files.

### 2. Lutris

Game → **Configure** → **System options** → **Pre-launch script**:

```
/usr/bin/lunatranslator-lutris
```

Leave *"Wait for pre-launch script completion"* **off**. Lutris exports the
game's `WINEPREFIX` (and `WINE` runner) to the script; LunaTranslator starts in
that prefix, then Lutris launches the game into it.

### 3. Heroic

Game → **Settings** → **Advanced** → **Wrapper command** (or global *Wrappers*):

```
/usr/bin/lunatranslator-heroic
```

Heroic runs the game through the wrapper and exports the prefix
(`WINEPREFIX` for Wine games, `STEAM_COMPAT_DATA_PATH` for Proton).

### 4. Steam / Proton 

Game → **Properties** → **General** → **Launch Options**:

```
/usr/bin/lunatranslator-steam %command%
```

This is the **finickiest** path: Proton runs the game inside a *pressure-vessel*
container. The wrapper detects the game's Proton from `%command%` and starts
LunaTranslator with that **same Proton** into the game's prefix
(`$STEAM_COMPAT_DATA_PATH/pfx`) so the hook ABI matches, then launches the game.
See **Troubleshooting** if hooking doesn't attach.

---

## OCR for native Linux and browser games

Native (non-Wine) and browser games can't be screen-grabbed from inside the Wine
prefix. The feeder captures a region on the host, OCRs it, and pushes the text
to the clipboard — Wine mirrors the clipboard into the prefix, and
LunaTranslator's clipboard source translates it.

```sh
lunatranslator-ocr                 # pick a region, OCR (jpn+eng), send to Luna
lunatranslator-ocr --engine manga-ocr     # much better Japanese
lunatranslator-ocr --lang jpn --print
```

Make sure LunaTranslator's **clipboard** text source is enabled (it is by
default). Then **bind `lunatranslator-ocr` to a hotkey** in your compositor:

**Hyprland** (`~/.config/hypr/hyprland.lua`):
```
hl.bind("SUPER + T", hl.dsp.exec_cmd("lunatranslator-ocr"))
```

**Sway** (`~/.config/sway/config`):
```
bindsym $mod+t exec lunatranslator-ocr
```

**GNOME**: Settings → Keyboard → *View and Customize Shortcuts* → *Custom
Shortcuts* → add `lunatranslator-ocr`.

**KDE**: System Settings → Shortcuts → *Custom Shortcuts* → new → command
`lunatranslator-ocr`.

Capture backend is auto-detected: `grim`+`slurp` (wlroots) → desktop-portal
front-end (GNOME/KDE: needs `gnome-screenshot` or `spectacle`) → `python-mss`
(X11). Override with `--backend`.

---

## Japanese fonts & OCR quality

```sh
sudo pacman -S adobe-source-han-sans-jp-fonts wqy-zenhei   # JP rendering in Wine
paru -S manga-ocr                                          # best JP OCR
```

`tesseract` JP is serviceable; `manga-ocr` is dramatically better for game text.

---

## Troubleshooting

**Nothing translates from HOOK.** LunaTranslator and the game must be in the
*same* prefix and the *same* Wine. Manual: pass `--prefix`/`--wine` to match.
Lutris/Heroic: the wrapper reuses the launcher's prefix/runner automatically.

**Steam/Proton: hook won't attach.** Confirm the launch option is exactly
`/usr/bin/lunatranslator-steam %command%`. If Proton wasn't detected, the
wrapper logs a fallback to system Wine (ABI may mismatch). Try forcing a
specific Proton, or run the game through Lutris/Heroic instead — those paths are
cleaner. Anti-cheat titles may block Wine-level hooking entirely.

**OCR feeder: "region selection cancelled" / no picker on X11.** Install
`grim`+`slurp`, or a portal front-end (`gnome-screenshot`/`spectacle`).
`python-mss` grabs the whole monitor (no interactive region).

**First launch can't download.** Set a mirror and retry:
```sh
LT_RELEASE_URL=https://your.mirror/LunaTranslator_x64_win10.zip lunatranslator-bootstrap --force
```

**Re-download / switch build.** `lunatranslator-bootstrap --force`.

---

## Environment knobs

| Variable | Default | Purpose |
|----------|---------|---------|
| `LT_DATA_HOME` | `~/.local/share/lunatranslator` | shared app + config + prefix root |
| `LT_APP_DIR` | `$LT_DATA_HOME/app` | portable app location |
| `LT_DEFAULT_PREFIX` | `$LT_DATA_HOME/prefix` | prefix for `lunatranslator` / manual default |
| `LT_WINE` | `wine` | Wine binary for the default prefix |
| `LT_RELEASE_URL` | GitHub latest `…win10.zip` | bootstrap download source |
| `LT_STARTUP_DELAY` | `3` | seconds to let Luna start before the game |
| `LT_OCR_LANG` | `jpn+eng` | tesseract languages |
| `LT_OCR_ENGINE` | `tesseract` | `tesseract` or `manga-ocr` |

---
