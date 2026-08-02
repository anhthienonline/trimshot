# Changelog

Notable changes per release. Dates are ISO 8601.

## 0.1.0 — 2026-08-02

First public build.

### Capture

- Freezes a full-resolution still of every display before the overlay appears, so the pixels
  you crop are the pixels you saw. Verified against macOS's own `screencapture` of the
  identical region: mean difference **0.01 of one 8-bit level**.
- Multi-display selections, including monitors at negative coordinates and mixed scale
  factors. A cross-display crop renders at the highest scale involved so the Retina half is
  not halved.
- Size readout in both units — `840 × 480 px · 420 × 240 pt`.

### Selection

- Eight resize handles, drag the interior to move.
- Arrow keys nudge 1 pt, `⇧` 10 pt, `⌥` drags the bottom-right corner. Clamped to the
  displays.
- `⌘A` selects the whole display.

### Measuring

- Magnifier with an 8× pixel grid, following the cursor, reading the frozen bitmap.
- Eyedropper with hex readout; `C` copies it.

### Annotation

- Freehand, line, arrow, rectangle, ellipse, highlighter, text, pixelate.
- Six colours, three stroke widths, undo and redo.
- The live preview and the exported file go through one renderer, so they cannot drift —
  measured agreement 0.23/255.

### Text recognition

- On-device OCR via Vision in Vietnamese and English.
- Uses recognition revision 3 and the language tag `vi-VT` — **not** `vi-VN`, which Vision
  silently ignores, leaving English-only recognition that mangles every accent.

### Output

- Copy to clipboard as PNG and TIFF, save to a configured folder or through a panel.
- No network access. There is no networking code in the binary.

### App

- Menu bar only, no Dock icon. Default shortcut `⌃G`, rebindable in Settings.
- Registers itself as a login item on first run from `/Applications`, once.
- Universal builds available; the default build is Apple Silicon only.

### Notes

- Signed with a self-signed certificate, **not notarised** — Gatekeeper blocks the first
  launch. See the install instructions.
- Requires macOS 14 or later.
