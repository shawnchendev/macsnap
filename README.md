# macsnap

A native macOS screenshot and annotation overlay tool matching [tobi/omasnap](https://github.com/tobi/omasnap) feature-for-feature.

It captures the screen at native Retina resolution before mapping an overlay window, ensuring the editor never captures itself. The editor retains annotations as movable, resizable vector layers, preserves non-destructive operation history, and supports exact operation-log persistence (`.png.json`).

Built in Swift 6 on AppKit, CoreGraphics, and Apple Vision.

---

## Features

- **Capture Modes**:
  - Freeform region selection.
  - Window selection with live hover detection and keyboard navigation.
  - Full-screen capture.
  - Scrolling region capture with frame stitching.
- **Pointer-Side Measurement Ruler**:
  - Shows cursor coordinates `(x, y)` while idle.
  - Shows frame size in native export pixels (`1920 × 1080 px`) while sizing a region, window, or crop handle.
- **Top Tab Strip**:
  - Switch capture mode anytime: **Region**, **Window**, **Scrolling Region**, **Fullscreen**.
  - `Space` steps through tabs; `S` toggles scrolling mode; `Ctrl+A` or `Cmd+A` triggers fullscreen.
- **Recents Shelf**:
  - Displays the 5 most recent captures as small cards stacked along the right edge.
  - Hovering smoothly fans them out; clicking any card reopens that capture in the editor with all vector annotations and undo history intact!
- **Non-Destructive Operation Log**:
  - Every action is an entry in `OperationLog`.
  - Exact, unlimited Undo/Redo (`⌘Z` / `⇧⌘Z`).
  - Rebuilding the image is a pure function of the log.
  - Sidecar `.png.json` files let you close, crash-recover, or reopen any capture with its layers still editable.
- **8 External Recropping Handles**:
  - Dragging crop handles resizes the screenshot boundaries.
- **Canvas Growth Modes (`G` / `Shift+G`)**:
  - **Framed** (default): adds backdrop mat around drawn layers.
  - **Overflow**: tight growth only on sides needed by annotations, transparent background.
  - **Image**: clips strictly to the original screenshot bounds.
- **Backdrops (`B` / `Shift+B`)**:
  - Mesh gradients: **Slate**, **Aurora**, **Sunset**, **Lagoon**, **Violet**.
  - **Window Gray** with soft ambient-plus-key drop shadow.
  - **Custom** image backdrops.
  - **Off / None** for transparency.
  - `Shift+B` toggles the card's drop shadow.
- **Vector Tools**:
  - `V`: Select / Move / Resize / Scale layers with mouse wheel.
  - `A`: Arrow (with 45° snapping on `Shift`).
  - `L`: Straight line (with 45° snapping on `Shift`).
  - `F`: Freehand stroke (smoothed points).
  - `H`: Highlighter:
    - **Snap mode** (default): detects text rows using horizontal edge density and locks straight across the text row at the exact font height.
    - **Normal mode**: freehand highlighter. Press `H` again to toggle.
  - `S`: Spotlight / Loupe magnifier (1.5x–4x zoom, shape cycle: ellipse, rectangle, rounded rectangle).
  - `C`: Numbered counter marker (1, 2, 3... auto-incrementing circular badge).
  - `R`: Rectangle (hollow or filled, `Alt+Wheel` rounds corners, `Shift` for 1:1 square).
  - `E`: Ellipse (hollow or filled, `Shift` for circle).
  - `D`: Redaction (Pixelate randomized mosaic or Solid opaque blackout). Irreversibly destroys pixels in exports and under loupes.
  - `X`: Cut tool (drag a band horizontally or vertically, preview shaded strip with dashed seam, release to collapse gap and shift layers).
  - `T`: Text label on a cream readability pill, outline, or plain (`Shift+T` cycles Neucha, JetBrains Mono, and Inter Display).
  - `O`: OCR (recognizes text using Apple Neural Engine Vision framework, copies text to clipboard, and shows preview).
  - `I`: Eyedropper (samples pixel color directly into custom palette).
- **Color Palette**:
  - 8 preset colors (`1`–`8`): `#ff375f`, `#ff9f0a`, `#ffd60a`, `#30d158`, `#0a84ff`, `#bf5af2`, `#000000`, `#ffffff`.
- **Pinned Captures (`P`)**:
  - Floating, always-on-top window on bottom-right of screen.
  - Hover reveals controls: **Edit** (reopens in macsnap), **Copy**, **Link** (copies file path), **Drag handle** (drag file into Slack/Finder), **Resize** with mouse wheel, **Close**.
- **Single-Instance Hotkey Toggle**:
  - Running `macsnap` while an overlay is open sends `SIGTERM` and cleanly closes the overlay.
  - Pressing your screenshot hotkey once opens the overlay, and pressing it again closes it!

---

## Build & Installation

### Requirements
- macOS 14.0 or later
- Swift 6.0+ / Xcode command line tools (`xcode-select --install`)

### Build
```bash
make build
# or: swift build -c release
```

### Run Tests
```bash
make test
# or: swift test
```

### Install
```bash
make install
```
This installs the `macsnap` binary to `~/.local/bin/macsnap` (make sure `~/.local/bin` is on your `PATH`).

To install globally to `/usr/local/bin`:
```bash
sudo make install PREFIX=/usr/local
```

---

## Menu Bar App

For point-and-click triggering instead of the terminal, run the resident menu-bar app (also installed by `make install`):

```bash
macsnap-menubar
```

A viewfinder icon appears in the menu bar with Capture Region / Window / Scrolling Region / Fullscreen actions, an Open Screenshots Folder shortcut, an Open at Login toggle (LaunchAgent, takes effect next login), and Quit. Each action launches the installed `macsnap` binary, so the capture flow — and its Screen Recording permission — is unchanged. Only one menu-bar instance runs at a time.

## Settings (Menu Bar)

**Settings…** (in the menu, `⌘,`) opens a settings panel with two tabs:

- **General** — screenshots folder (with folder picker), filename pattern (`{date}` `{time}` `{app}` tokens), and Open at Login. When bundled as `Macsnap.app` in `/Applications`, login uses the system service; the bare-binary install writes a LaunchAgent file instead.
- **Hotkeys** — system-wide shortcuts for all four capture modes, no Accessibility permission needed (Carbon hotkeys). Click *Record shortcut*, press a combo with at least one of ⌘/⌃/⌥/⇧, Delete clears, Esc cancels. Combos the system rejects (already taken) are reported on Save. Bindings persist in `~/.config/macsnap/macsnap.conf` under `[hotkeys]`, e.g. `region = cmd+shift+5`, and take effect immediately — no restart. They fire even when another app is focused; while an overlay is already open they toggle it closed, same as the CLI. Assigned shortcuts also appear next to their menu items.

## Mac App Bundle

For a double-clickable app (no terminal, no Dock icon), build the bundle and copy it to Applications:

```bash
make app              # assembles dist/Macsnap.app (ad-hoc signed)
make install-app      # copies it to /Applications (may prompt for a password)
```

Double-clicking `Macsnap.app` launches the same resident menu bar. Inside the bundle, `Contents/MacOS` holds both executables, so capture launching keeps working with no PATH setup. Open at Login uses the system login-items service when bundled (requires the app to live in `/Applications`).

> **One-time re-permission:** macOS grants Screen Recording per app identity, so the first capture from the bundle asks for permission again under the name “macsnap” — approve it once in System Settings and it sticks.

### Permissions & rebuilding (important)

macOS pins a Screen Recording grant to the exact binary signature. The default build is **ad-hoc signed**, so **every rebuild invalidates the grant**: System Settings still shows the toggle ON, but captures fail (`Failed to match existing code requirement` in the log) until you remove macsnap with minus and re-add/re-approve it. If captures suddenly fail right after an update, that dance is the fix — not a bug in the capture code.

Durable options:
1. **Sign with a free Apple Development certificate** (stable across rebuilds): in Xcode go to Settings → Accounts, add your Apple ID, then
   ```bash
   make app CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
   make install-app
   ```
   Find the exact identity string via `security find-identity -v -p codesigning`.
2. Or stop rebuilding once a build works — the grant stays valid as long as the binary is untouched.

---

## Setting up macOS Shortcuts

You can trigger `macsnap` with a global hotkey such as `Cmd+Shift+4` or `F12`:

### Option A: Using Raycast / Alfred / skhd
In `skhd` (`~/.config/skhd/skhdrc`):
```bash
# Toggle macsnap overlay
cmd + shift - 4 : macsnap
```

### Option B: macOS Shortcuts App
1. Open **Shortcuts.app** and create a new Shortcut.
2. Add a **Run Shell Script** action: `~/.local/bin/macsnap`.
3. Under Shortcut Details (sidebar), assign a keyboard shortcut (e.g. `Cmd+Shift+5` or `F12`).

---

## CLI Usage

```bash
# Freeform region capture (default)
macsnap

# Explicit starting modes
macsnap --capture-region
macsnap --capture-window
macsnap --capture-fullscreen
macsnap --scroll

# Compatibility aliases
macsnap region
macsnap windows
macsnap fullscreen
macsnap smart

# Quick output (skips annotation editor)
macsnap --copy              # Copy PNG to clipboard only
macsnap --save              # Save PNG to ~/Pictures/Screenshots only
macsnap --copy --save       # Copy and save immediately

# Open existing image or clipboard
macsnap /path/to/screenshot.png
macsnap --file /path/to/screenshot.png
macsnap --clipboard

# Pinned mode
macsnap --pin /path/to/screenshot.png
```

---

## Controls

### Selection Phase

| Input | Action |
|---|---|
| Drag | Select region, native pixel readout displayed at pointer |
| `Space` | Cycle capture tabs (Region, Window, Scrolling Region) |
| `S` | Toggle scrolling-region mode |
| `R` | Restore last drawn region |
| Arrow keys | Move between windows in window mode |
| `Enter` | Capture highlighted window |
| `Cmd+A` | Select fullscreen |
| Scrolling capture | Drag a region, pick Manual ↓/→ (you scroll) or Auto ↓/→ (macsnap scrolls), then Done stitches |
| Hover right edge | Fan out 5 most recent captures; click one to reopen |
| `Esc` | Dismiss overlay |

### Annotation Editor Phase

| Input | Action |
|---|---|
| `V` | Select / Move / Resize layers; wheel scales layer |
| `A` | Arrow (`Shift` snaps to 45°) |
| `L` | Straight line (`Shift` snaps to 45°) |
| `F` | Freehand stroke |
| `H` | Highlighter (Snap text lock vs Normal freehand mode) |
| `S` | Spotlight / Loupe (press again to cycle Ellipse, Rect, Rounded) |
| `C` | Numbered marker (1, 2, 3...) |
| `R` | Rectangle (`Alt+Wheel` rounds corners, `Shift` for 1:1) |
| `E` | Ellipse (`Shift` for 1:1 circle) |
| `D` | Redact (press again to toggle Pixelate mosaic vs Solid) |
| `X` | Cut tool (drag band to remove and collapse gap) |
| `T` | Text on readability pill; `Shift+T` cycles font |
| `O` | Recognize and copy all text via Apple Vision OCR |
| `I` | Eyedropper color picker |
| `B` | Cycle backdrops (Slate, Aurora, Sunset, Lagoon, Violet, Gray, Off) |
| `Shift+B` | Toggle card drop shadow |
| `G` / `Shift+G` | Cycle canvas boundary: Framed, Overflow, Image |
| `1`–`8` | Set annotation color preset |
| `Cmd+Z` | Undo |
| `Shift+Cmd+Z` | Redo |
| `Cmd+C` | Copy PNG to clipboard |
| `Cmd+S` | Save PNG to `~/Pictures/Screenshots` |
| `Enter` | Copy and Save |
| `P` | Pin capture as floating window |
| `Esc` | Return to Selection phase; press again to exit |

---

## Configuration

Optional configuration file at `~/.config/macsnap/macsnap.conf` (or `~/.config/omasnap/omasnap.conf`):

```ini
[output]
# Where saved screenshots go. Default: ~/Pictures/Screenshots
directory = ~/Pictures/Screenshots
# Filename pattern (.png is appended). Default: screenshot-{date}_{time}-{app}
filename = screenshot-{date}_{time}-{app}

[colors]
# 8 preset colors
palette = #ff375f, #ff9f0a, #ffd60a, #30d158, #0a84ff, #bf5af2, #000000, #ffffff
custom = #ff375f

[background]
# Custom backdrop image
image = ~/Pictures/backdrops/desk.jpg
# Default style: none, off, slate, aurora, sunset, lagoon, violet, custom
default = none
```

Environment variable overrides:
- `MACSNAP_SCREENSHOT_DIR` / `OMASNAP_SCREENSHOT_DIR`
- `MACSNAP_RECENT_DIR` / `OMASNAP_RECENT_DIR`
- `MACSNAP_OCR_LANGS` / `OMASNAP_OCR_LANGS`

---

## License

MIT License. Bundled fonts (Neucha, JetBrains Mono, Inter Display) are licensed under the SIL Open Font License.
