# Contributing

## Getting it building

```bash
./scripts/create-signing-cert.sh   # once — read SECURITY.md first, it has a trade-off
swift build
swift run TrimshotChecks
./scripts/bundle.sh && open "build/Trimshot.app"
```

**Full Xcode is not required.** Everything builds with Command Line Tools, and that
constraint is deliberate — it is why there are no SwiftPM dependencies (popular Swift
packages use `#Preview`, whose macro plugin ships only with Xcode) and no `swift test`
target (Command Line Tools ships neither XCTest nor the swift-testing runtime).

## Where things go

Pure logic — coordinate maths, compositing, pixel sampling, annotation rendering — belongs in
`Sources/TrimshotCore`, which imports no AppKit. That is the part that can be checked without
a screen, so put anything checkable there.

`Sources/Trimshot` is the AppKit app. `Sources/TrimshotChecks` is the assertion harness that
stands in for `swift test`.

## Verifying a change

Three levels, in order of how much they catch:

```bash
swift run TrimshotChecks     # coordinate maths, handles, annotation model
./scripts/self-check.sh      # the real capture path vs macOS's own screencapture
./scripts/render-chrome.sh   # the selection UI to PNGs; preview-vs-export; Vietnamese OCR
```

The last two need a Screen Recording grant, so they cannot run in CI — they are the manual
gate before a release.

**If you touch coordinate code, add a check.** `ScreenGeometry` and `SelectionHandle` exist as
separate, AppKit-free types specifically so display arrangements can be described as data:
negative origins, mixed scale factors, selections spanning two monitors. A change there
without a new case in `TrimshotChecks/main.swift` is not finished.

## Things that will bite you

Collected because each of these cost real debugging time:

- **Window levels are the most repeated bug in this codebase — three so far.** They all go
  through `OverlayLevel` now, and `--render-chrome` asserts the ordering. The three:
  `isFloatingPanel = true` silently resets `NSWindow.level`, so the toolbar rendered under the
  overlay; the HUD sat at `.statusBar`, a thousand levels below the overlay it had to appear
  over; and an `NSOpenPanel` defaults to level 0, so a file picker opened behind the overlay
  — invisible, while `runModal()` froze the app with nothing on screen to explain it. Every
  one was silent. Anything new that shows a window during a capture gets its level from
  `OverlayLevel`.
- **`NSSavePanel.runModal()` does not work while the capture overlay is up.** Measured: it
  returns `.cancel` immediately without ever presenting, and while it runs, blocks scheduled
  on the main queue are never serviced. Use `begin(completionHandler:)`, which presents the
  same panel as an ordinary window — visible, unoccluded and key, measured in the same
  situation.
- **`NSWindow.acceptsMouseMovedEvents` defaults to false.** Without it `mouseMoved:` is never
  delivered, so anything tracking the cursor silently freezes at wherever the pointer was when
  the window opened. This shipped broken in the magnifier and the measure tool because
  `--render-chrome` sets the pointer directly — a harness that assigns state cannot catch state
  that is never assigned at runtime. Features that follow the cursor need a real click-through.
- **Vision's Vietnamese tag is `vi-VT`, not `vi-VN`.** The sensible-looking one is silently
  ignored, leaving English-only recognition. Recognition revision 3 is also required.
- **macOS 26 wraps every legacy `.icns` in its own squircle.** Icon artwork is full-bleed for
  that reason; drawing our own rounded shape nests a dark tile inside a light one.
- **The diagnostic flags are `#if DEBUG` for security, not tidiness.** See SECURITY.md.
- **Screen Recording permission follows the code signature, not the path.** Renaming the
  bundle identifier resets it on every machine.

## Style

Match the surrounding code. Comments explain *why*, especially where a line looks arbitrary —
most of the non-obvious constants in this codebase have a reason recorded next to them, and
that is the convention worth keeping.

Run `swift build` with no warnings before opening a pull request; the tree is warning-free and
CI keeps it that way.
