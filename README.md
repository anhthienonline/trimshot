# Trimshot

A Lightshot-style screen capture app for macOS: hit a hotkey, the screen freezes, drag a
region, annotate it, copy or save. Built for design QA — every reading is in CSS
pixels, the unit your design is already in, and it picks colours out of the frozen bitmap and
runs OCR in Vietnamese.

Native Swift + AppKit + ScreenCaptureKit. No cloud upload: captures stay on your machine.

Identity and voice live in [brand/BRAND.md](brand/BRAND.md); [brand/index.html](brand/index.html)
is a shareable intro page that doubles as the identity reference. [site/](site/) is the
public promo page — see "Promo site" below.

## Requirements

macOS 14+, Swift 6. **Full Xcode is not required** — everything builds with Command Line
Tools. That constraint shapes a couple of things:

- No SwiftPM dependencies (popular packages use `#Preview`, whose macro plugin ships only
  with Xcode).
- No `swift test` (Command Line Tools ships neither XCTest nor the swift-testing runtime).
  Pure logic lives in `TrimshotCore` and is exercised by a plain executable instead.

## Setup

```bash
./scripts/create-signing-cert.sh   # once — see "Signing" below
./scripts/install.sh               # → /Applications, starts it, adds the login item
```

Run `create-signing-cert.sh` *before* granting the permission, otherwise you will have to
grant it again after the next rebuild.

`install.sh` puts the app in `/Applications` (or `~/Applications` if that is not writable)
rather than leaving it in `build/`, which every `scripts/bundle.sh` wipes — a login item
pointing there would break on the next boot. The app registers itself as a login item on
its first run from a permanent location, once only, so switching it off in Settings sticks.

The Screen Recording grant follows the app across the move and across reinstalls: its
designated requirement is `identifier "…" and certificate leaf = H"…"`, which does not
involve the path or the binary hash.

For development you can still run it in place with `./scripts/bundle.sh` and
`open "./build/Trimshot.app"`.

The first capture triggers the macOS Screen Recording prompt. Grant it under
**Privacy & Security › Screen & System Audio Recording**, then trigger the shortcut again.

## Usage

There is no window and no Dock icon — the app is `LSUIElement`, so it lives entirely in the
menu bar as a **camera inside viewfinder brackets**. Three ways in:

- press `⌃G`
- click the menu bar icon → **Capture Area**
- the icon's menu also has Open Save Folder, Settings… and Quit

Settings carries the shortcut, save folder and format, plus what the app is and links to the
site, the source and the privacy page.

Double-clicking the app in Finder while it is already running shows a HUD and blinks the
menu bar icon, because otherwise absolutely nothing happens and it looks like a failed
launch.

| Action | |
|---|---|
| `⌃G` | start a capture (rebindable in Settings) |
| drag | select a region |
| drag a handle / the interior | resize / move a settled selection |
| arrows, `⇧`+arrows, `⌥`+arrows | nudge by 1 pt, 10 pt, resize by 1 pt |
| `⌘A` | select the whole display |
| `C` | copy the HEX colour under the cursor |
| `M` or the ruler button | ruler mode — hover reads the gap under the cursor, drag measures A→B |
| `⌘Z` / `⌘⇧Z` | undo / redo an annotation |
| `⌘C` / `return` | copy the selection |
| `⌘S` / `⌘⇧S` | save to the configured folder / via a panel |
| `⌘V` | with the image tool armed, place the clipboard image instead of a file |
| drag a placed image / its handles | move it / resize it |
| `⌫` | remove the selected placed image |
| `esc` / right-click | cancel |

Once a selection settles, a toolbar appears with freehand, line, arrow, rectangle,
ellipse, highlighter, text, pixelate and place-an-image, plus six colours and a custom colour
picker, stroke width, undo, the ruler, OCR, copy, save and cancel. Hover any button for a
tip. Picking a tool turns the selection into a canvas; tapping the active tool
again returns to resizing it.

Choosing an image drops it into the middle of the selection right away, selected, with a
dashed teal frame and handles — drag it to move, drag a handle to resize, `⌫` to remove.
Only the tools that fill a rect are pickable this way; a line or a freehand stroke would need
distance-to-stroke hit testing, so those are not pickable rather than pickable and wrong.

The magnifier follows the cursor while selecting: an 8× pixel grid with the HEX value and
pixel coordinate under the crosshair. The size readout is in CSS pixels, so a 420 px
Figma frame reads 420 — not the 840 device pixels macOS's own screenshot tool would report.

All measurements are **CSS pixels**, never device pixels. AppKit points already are CSS
pixels, so the discipline is in never multiplying by the scale factor; everything routes
through `Units` in `TrimshotCore` so one label cannot drift into a different unit from the
rest. A saved PNG is still 2× those numbers on a Retina display, as every macOS screenshot is.

**Ruler mode** does two things. Hovering reports the near-uniform run the cursor sits inside,
horizontally and vertically — point at the space between a button and its label and read the
spacing. Dragging gives a measured box: a rectangle with a dimension line on each axis and its
`W × H` in the middle. The reading stays on screen after you let go.

It draws a rectangle rather than the direct A→B line Photoshop uses. Drawing the diagonal plus
its two components made a right triangle, and in UI work the diagonal is almost never the
number wanted — how wide and how tall is.

The **save format** setting governs saved files only. Copies are always PNG: a JPEG on the
pasteboard would put compression artefacts into every pasted capture, and colours and edges
are the thing this tool exists to check.

**OCR** reads Vietnamese and English on-device via Vision and puts the text on the
clipboard. Note that Vision's Vietnamese language tag is `vi-VT`, not the `vi-VN` you would
expect — asking for `vi-VN` silently falls back to English-only and mangles every accent.
It also needs recognition revision 3; revisions 1 and 2 know 1 and 6 languages respectively.

## Development

```bash
swift build                      # compile
swift run TrimshotChecks       # stands in for `swift test`
./scripts/bundle.sh              # assemble build/Trimshot.app
CONFIG=debug ./scripts/bundle.sh # same, unoptimised
UNIVERSAL=1 ./scripts/bundle.sh  # arm64 + x86_64 (lipo of two separate builds)
```

Two verification scripts stand in for the parts that would otherwise need a human dragging
a rectangle and eyeballing the result.

### Self-check

Runs the whole capture path without a human dragging anything, and compares the crop
against macOS's own `screencapture` for the identical region. A flipped Y axis or a
mishandled Retina scale factor shows up here as a large pixel difference.

```bash
./scripts/self-check.sh
```

It goes through `open` rather than running the binary directly, because a process started
from a shell inherits the *terminal's* Screen Recording permission rather than the app's —
and it quits any running instance first, since `open` ignores `--args` when the app is
already up.

Both verification scripts rebuild `build/` as a **debug** bundle, because the diagnostic
entry points are `#if DEBUG` only. That is a security boundary, not tidiness: they capture
every display and write to a path from argv with no user interaction, so in a release build
any local process could run `open -a "Trimshot" --args --render-chrome /tmp/steal`
and borrow this app's Screen Recording grant — including a process that has none of its own
and would be denied if it asked. Run `./scripts/bundle.sh` afterwards to get a release
bundle back.

The PNGs these scripts leave in `build/` are real screen contents. They are gitignored but
unencrypted; `rm -rf build/preview build/selfcheck` when you are done with them.

### Render-chrome

```bash
./scripts/render-chrome.sh
```

Renders the selection UI to PNGs in `build/preview/` — mid-drag, settled, and with one of
every annotation tool — so it can be inspected without triggering the hotkey. It also
asserts the two things most likely to break silently:

- the **live preview matches the exported file** pixel for pixel (both go through
  `AnnotationRenderer`, so a divergence means the two paths have drifted);
- **OCR reads Vietnamese back** out of text drawn by the annotation renderer, which
  catches a missing language model as well as broken glyph rendering.

### Layout of the outputs

`chrome-raw.png` is the same region with no chrome at all. Comparing it against
`chrome-dragging.png` is how you check the dim is actually being applied — squinting at a
screenshot is not reliable, the ratio should be ~0.58.

### App icon

```bash
swift scripts/make-icon.swift --preview
```

Draws `Resources/AppIcon.icns` in code — four crop brackets in the brand teal around a
crosshair on a petrol tile — and writes `build/preview/icon-*.png` to check it at 16,
32, 128 and 1024 px. The 16 px and 32 px sizes use a chunkier variant with shorter bracket
arms; at the full weight the gaps close up and the mark turns into a solid ring.

The artwork is **full-bleed on purpose**. macOS 26 places every legacy `.icns` inside its
own squircle plate, so drawing our own rounded shape as well nests a dark tile inside a
light one. Pass `--framed` for the self-contained silhouette if this ever has to run on
something older than macOS 26.

Check icon changes against what the system actually reports rather than the raw PNG —
Finder caches, and the system mask changes the result:

```swift
NSWorkspace.shared.icon(forFile: ".../Trimshot.app")
```

### Distributing to another Mac

```bash
./scripts/package.sh                # → build/dist/*.zip and *.dmg
UNIVERSAL=1 ./scripts/package.sh    # add an x86_64 slice for Intel Macs
```

Builds a release for this Mac's architecture, verifies the signature, and wraps it with
`ditto` — not `zip`, which can invalidate a bundle's signature — plus a dmg. Apple Silicon
only by default; an Intel recipient cannot launch that at all, hence `UNIVERSAL=1`.

**Without notarization the receiving Mac blocks the first launch.** The app is signed with
the local self-signed certificate, so Gatekeeper rejects it (`spctl --assess` → `rejected`).
The recipient has to open System Settings › Privacy & Security and click **Open Anyway** on
the blocked-app notice. macOS 15 removed the old Control-click → Open shortcut, so that
panel is the only route now. Once per machine.

To ship it cleanly you need a paid Apple Developer account and a *Developer ID Application*
certificate. `notarytool` and `stapler` are both present in Command Line Tools, so no Xcode
is needed:

```bash
xcrun notarytool store-credentials my-profile \
    --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
SIGN_IDENTITY_NAME="Developer ID Application: …" NOTARIZE_PROFILE=my-profile \
    ./scripts/package.sh
```

Two things do not travel with the package:

- **Screen Recording permission.** TCC is per-machine; every recipient grants it once.
- **The macOS 26 icon treatment.** The artwork is full-bleed because macOS 26 supplies the
  squircle itself. On macOS 14 and 15 nothing masks it, so it draws as a hard-edged square —
  run `swift scripts/make-icon.swift --framed` before packaging for those machines.

`UNIVERSAL=1` builds each architecture separately and `lipo`s them, because SwiftPM's
built-in `--arch a --arch b` needs `xcbuild` from full Xcode.

### Promo site

```bash
./scripts/site.sh              # build the dmg and stage it into site/
./scripts/site.sh --preview    # deploy a throwaway Vercel URL
./scripts/site.sh --prod       # deploy to production
```

`site/` is a static Vercel root: one `index.html`, a `vercel.json`, and the disk image
staged beside them. No build step, no dependencies.

The script **rewrites the download size in the page** from the file it just built. A
hand-typed figure is wrong the first time the binary changes, and on a page whose whole
argument is that the numbers are exact, a stale number is the worst possible detail to get
wrong. It exits non-zero if any mention fails to update.

The product figure in the hero is the overlay rebuilt in CSS rather than a screenshot: it
stays crisp at any density, follows the viewer's theme, weighs nothing, and — the reason it
started out as CSS — a real screen capture of this app would publish whatever happened to be
on the author's desktop.

The positioning is deliberately narrow. Broad free tools (Shottr, macshot) win on features:
scrolling capture, recording, 40-language OCR, cloud upload. Trimshot's page does not
pretend otherwise; it has a comparison table that says so plainly and competes on the one
thing it can prove — a stated accuracy figure. Keep it that way. The moment the page claims
breadth it cannot back up, the accuracy claim stops being believable too.

**The download is not notarised**, so Gatekeeper blocks the first launch and the install
section says so up front, with the exact click path. Publishing an unnotarised binary and
letting visitors discover that themselves is how a promo page loses people.

### Releasing

```bash
./scripts/release.sh 0.1.0
```

Checks that `Info.plist` and `CHANGELOG.md` agree with the version you asked for, runs the
build and the checks, packages the dmg, and stamps the real sha256 into
`homebrew/trimshot.rb`. Then it stops and prints the publish commands — creating a tag, a
GitHub release and a public download are one-way, so it does not do them for you.

Two verifications cannot run in CI because they need a Screen Recording grant, and they are
the manual gate before publishing:

```bash
./scripts/self-check.sh
./scripts/render-chrome.sh
```

### Homebrew

`homebrew/trimshot.rb` is the source of truth for the cask; the tap itself is a separate
repository (`homebrew-trimshot`, so the tap name is `hokhacthien91/trimshot`).

**Homebrew does not solve the Gatekeeper problem.** Cask quarantines its downloads by
default, so `brew install --cask trimshot` on an un-notarised build still needs the same
one-time approval in System Settings. The `--no-quarantine` flag that used to skip it is
being removed, and Homebrew is moving toward requiring casks to pass Gatekeeper outright —
so brew buys convenient installs and updates, not a bypass, and an un-notarised cask may
stop being accepted. Notarising is the only thing that actually removes the step.

### Signing

macOS ties the Screen Recording permission to the app's designated requirement. An ad-hoc
signature is derived from the binary hash, so it changes on every build and macOS treats
each build as a new app — you would re-grant the permission every single time.
`create-signing-cert.sh` creates a stable self-signed certificate, which makes the
requirement `identifier "…" and certificate leaf = H"…"` and survives rebuilds.

The certificate is deliberately **not** marked as trusted: codesign only needs the
identity to exist, and skipping the trust step avoids a login-password prompt.
`security find-identity` reports it as `CSSMERR_TP_NOT_TRUSTED`, which is expected —
which is also why the scripts detect it with `find-identity -p codesigning` rather than
`-v` (the latter hides untrusted identities).

`bundle.sh` uses the certificate when it exists and falls back to ad-hoc with a warning
when it does not.

## Layout

```
Sources/TrimshotCore/     pure logic, no AppKit — geometry, compositing, pixel sampling
Sources/Trimshot/   the app
  Capture/                  permission gate, ScreenCaptureKit
  Overlay/                  the selection UI, one window per display
  Actions/                  clipboard, file saving
  Hotkey/                   Carbon global hotkey
  Prefs/                    UserDefaults
Sources/TrimshotChecks/   assertions over TrimshotCore
scripts/                    bundling and signing
```

### Why capture first, then overlay

The hotkey grabs a full-resolution still of every display *before* anything is drawn, and
the overlay is painted on top of that frozen bitmap. A live transparent overlay would
drift — video keeps playing, menus close, the cursor moves — so the pixels you finally
crop would not be the pixels you selected. Freezing also makes the magnifier and the
colour picker exact, because they read the same bitmap that gets cropped.

### Coordinate systems

Three collide, and mixing them up is the most likely source of bugs:

- **AppKit global points** — origin bottom-left of the main screen, Y up. `NSScreen.frame`
  and `NSWindow.convertPoint(toScreen:)` speak this. The app reasons in it everywhere.
- **Display-local pixels** — origin top-left of one display, Y down. What ScreenCaptureKit
  returns.
- Displays can sit at negative coordinates and can each have a different scale factor.

All conversions go through `TrimshotCore/ScreenGeometry.swift`, which is covered by
`TrimshotChecks`.
