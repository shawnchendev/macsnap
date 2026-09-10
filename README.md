# opensnap

Native macOS screenshot capture and annotation tool, matching [tobi/omasnap](https://github.com/tobi/omasnap) feature-for-feature. Built in Swift 6 on AppKit, CoreGraphics, and Apple Vision.

It captures at native Retina resolution before showing the overlay, so the editor never captures itself. Annotations stay as movable vector layers with unlimited undo/redo, persisted exactly in sidecar `.png.json` files for crash recovery and re-editing.

## Features

- **Capture modes** — freeform region, window (hover highlight, `Enter` to grab, arrow-key navigation), fullscreen, and scrolling region with Manual/Auto stitching
- **Annotation tools** — arrow, line, freehand, text-snapping highlighter, spotlight loupe, numbered markers, rectangle, ellipse, mosaic/solid redaction, cut-collapse, text labels (3 fonts), Vision OCR, eyedropper, 8 color presets (`1`–`8`)
- **Canvas** — recrop handles, Framed/Overflow/Image growth modes (`G`), backdrops (`B`: Slate, Aurora, Sunset, Lagoon, Violet, Gray, Custom, Off)
- **Non-destructive editing** — every action is an undoable operation; reopen any capture from the recents shelf with history intact
- **Outputs** — copy / save / both, floating pinned captures (`P`), single-instance toggle (run again to dismiss)
- **Menu bar app** — resident capture menu, system-wide hotkeys (no Accessibility permission needed), settings panel, Open at Login

## Install

Requirements: macOS 14+, Swift 6 / Xcode command line tools (`xcode-select --install`).

```bash
make install          # opensnap + opensnap-menubar → ~/.local/bin (add to PATH)
make app install-app  # optional: double-clickable Opensnap.app → /Applications
```

Run `opensnap` for region capture, `opensnap-menubar` for the menu bar app, `opensnap --help` for all modes and flags.

> First capture requests Screen Recording permission under the name "opensnap" — approve once and it sticks. Ad-hoc signed rebuilds invalidate the grant (the toggle looks ON but captures fail); remove and re-add opensnap, or sign stably with `make app CODESIGN_IDENTITY="Apple Development: Name (TEAMID)"`.

## Configure

The settings panel (menu bar → Settings…) covers screenshots folder, filename pattern (`{date}` `{time}` `{app}` tokens), global hotkeys, and Open at Login. File-backed config lives at `~/.config/opensnap/opensnap.conf`, with env overrides `OPENSNAP_SCREENSHOT_DIR`, `OPENSNAP_RECENT_DIR`, `OPENSNAP_OCR_LANGS`.

## Contributing

- Fork, branch off `main`, keep PRs small and focused.
- Build with `make build`, and run the full suite with `make test` — it must pass before requesting review.
- Match the existing style: 4-space indent, `// MARK:` section headers, concise comments explaining *why*, not *what*.
- Add or update tests for behavior changes (`Tests/OpensnapTests`).
- Update this README when you change user-facing behavior.
- Be kind in reviews; assume good intent.

## License

MIT License. Bundled fonts (Neucha, JetBrains Mono, Inter Display) are licensed under the SIL Open Font License.
