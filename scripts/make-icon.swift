#!/usr/bin/env swift
//
// Draws the app icon and assembles Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift            # writes Resources/AppIcon.icns
//   swift scripts/make-icon.swift --preview  # also writes build/preview/icon-*.png
//   swift scripts/make-icon.swift --framed   # draw our own squircle (pre-macOS 26)
//
// Generated rather than hand-drawn so it stays reproducible and tweakable in one place,
// and needs no design tool — which matters here because the project deliberately builds
// with Command Line Tools only.
//
// The mark is four crop brackets around a crosshair: what the app does, in the simplest
// shape that still reads at 16 px.
//
// Palette: the app's own brand — see brand/BRAND.md. Deliberately *not* the Gravity Global
// green it started with: this is a portfolio piece, and wearing an employer's brand colour
// misattributes it.
//
// Artwork is **full-bleed** by default. macOS 26 puts every legacy `.icns` inside its own
// squircle plate with shading and a rim highlight, so supplying our own rounded shape as
// well produced a dark tile nested inside a light one. Verify any change to this by
// checking what the system actually reports, not just the PNG:
//
//   NSWorkspace.shared.icon(forFile: "…/Trimshot.app")

import AppKit
import Foundation

// MARK: - Palette

/// Signal — the mark. Light enough to hold up at 16 px against any wallpaper.
let signal = CGColor(srgbRed: 0x5F / 255, green: 0xD3 / 255, blue: 0xDE / 255, alpha: 1)
/// Petrol, the brand's dark ground. A tinted tile reads as chosen; plain near-black does not.
let surfaceTop = CGColor(srgbRed: 0x16 / 255, green: 0x3D / 255, blue: 0x45 / 255, alpha: 1)
let surfaceBottom = CGColor(srgbRed: 0x07 / 255, green: 0x18 / 255, blue: 0x1C / 255, alpha: 1)
let hairline = CGColor(srgbRed: 0x1E / 255, green: 0x4A / 255, blue: 0x53 / 255, alpha: 1)

// MARK: - Shape

/// Apple's icon silhouette is a superellipse, not a plain rounded rect — n ≈ 5 matches it
/// closely enough that the icon does not look subtly wrong beside system apps.
func squirclePath(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    let steps = 240
    let power = 2 / exponent

    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        let x = centre.x + a * (cosT < 0 ? -1 : 1) * pow(abs(cosT), power)
        let y = centre.y + b * (sinT < 0 ? -1 : 1) * pow(abs(sinT), power)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

// MARK: - Drawing

func drawIcon(size: CGFloat, in context: CGContext) {
    // Below 32 px the fine detail turns to mush, so the small sizes get a chunkier,
    // stripped-back variant — optical sizing, the same thing type designers do.
    let isSmall = size <= 32

    // macOS 26 puts every legacy .icns inside its own squircle plate. Drawing our own
    // rounded shape as well produced a dark tile nested inside a light one, so the
    // artwork now goes edge to edge and lets the system supply the silhouette.
    // `--framed` renders the self-contained version instead, for older macOS.
    let framed = CommandLine.arguments.contains("--framed")
    let bodyInset = framed ? size * (isSmall ? 0.045 : 0.09) : 0
    let body = CGRect(x: bodyInset, y: bodyInset, width: size - bodyInset * 2, height: size - bodyInset * 2)
    let shape = framed
        ? squirclePath(in: body)
        : CGPath(rect: body, transform: nil)

    // Surface
    context.saveGState()
    context.addPath(shape)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [surfaceTop, surfaceBottom] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.midX, y: body.maxY),
            end: CGPoint(x: body.midX, y: body.minY),
            options: []
        )
    }
    context.restoreGState()

    if !isSmall {
        // A faint top sheen, which is what stops a flat dark icon looking like a hole.
        context.saveGState()
        context.addPath(shape)
        context.clip()
        if let sheen = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [
                CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07),
                CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                sheen,
                start: CGPoint(x: body.midX, y: body.maxY),
                end: CGPoint(x: body.midX, y: body.midY),
                options: []
            )
        }
        context.restoreGState()

        if framed {
            // Only meaningful when we draw our own silhouette — a hairline along the
            // canvas edge would just be clipped away by the system's mask.
            context.saveGState()
            context.addPath(shape)
            context.setStrokeColor(hairline)
            context.setLineWidth(size * 0.006)
            context.strokePath()
            context.restoreGState()
        }
    }

    // The mark: four crop brackets around an implied selection — what the app does,
    // in the one shape that survives being drawn 16 px wide.
    // The small variant needs a bigger frame with shorter arms: at 16 px the gaps between
    // brackets are only a few pixels wide, and if they close up the mark turns into a
    // solid ring and stops reading as a crop frame.
    let padding = body.width * (isSmall ? 0.11 : 0.20)
    let marks = body.insetBy(dx: padding, dy: padding)
    let stroke = size * (isSmall ? 0.085 : 0.040)
    let arm = marks.width * (isSmall ? 0.31 : 0.30)

    // Inset by half the stroke so the bracket's outer edge lands on `marks`, not astride it.
    let m = marks.insetBy(dx: stroke / 2, dy: stroke / 2)

    context.setStrokeColor(signal)
    context.setLineWidth(stroke)
    context.setLineCap(.butt)
    context.setLineJoin(.miter)
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: m.minX, y: m.maxY - arm), CGPoint(x: m.minX, y: m.maxY), CGPoint(x: m.minX + arm, y: m.maxY)),
        (CGPoint(x: m.maxX - arm, y: m.maxY), CGPoint(x: m.maxX, y: m.maxY), CGPoint(x: m.maxX, y: m.maxY - arm)),
        (CGPoint(x: m.maxX, y: m.minY + arm), CGPoint(x: m.maxX, y: m.minY), CGPoint(x: m.maxX - arm, y: m.minY)),
        (CGPoint(x: m.minX + arm, y: m.minY), CGPoint(x: m.minX, y: m.minY), CGPoint(x: m.minX, y: m.minY + arm)),
    ]

    for (from, corner, to) in corners {
        context.move(to: from)
        context.addLine(to: corner)
        context.addLine(to: to)
        context.strokePath()
    }

    guard !isSmall else { return }

    // A crosshair at the centre — the cursor the app puts on screen, and it keeps the
    // middle of the icon from reading as an empty box. Deliberately light: at a glance it
    // should register as texture, not as a fifth shape competing with the brackets.
    // Long and thin, or it reads as a plus sign rather than a crosshair.
    let crossArm = body.width * 0.085
    context.setLineWidth(stroke * 0.42)
    context.setStrokeColor(signal.copy(alpha: 0.85)!)
    context.move(to: CGPoint(x: body.midX - crossArm, y: body.midY))
    context.addLine(to: CGPoint(x: body.midX + crossArm, y: body.midY))
    context.strokePath()
    context.move(to: CGPoint(x: body.midX, y: body.midY - crossArm))
    context.addLine(to: CGPoint(x: body.midX, y: body.midY + crossArm))
    context.strokePath()
}

// MARK: - Output

func render(size: Int) -> CGImage? {
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    drawIcon(size: CGFloat(size), in: context)
    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let icns = root.appendingPathComponent("Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(
    at: root.appendingPathComponent("Resources"),
    withIntermediateDirectories: true
)

// The exact filenames iconutil expects.
let entries: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for entry in entries {
    guard let image = render(size: entry.size) else {
        FileHandle.standardError.write("failed to render \(entry.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try write(image, to: iconset.appendingPathComponent("\(entry.name).png"))
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["--convert", "icns", "--output", icns.path, iconset.path]
try convert.run()
convert.waitUntilExit()
guard convert.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
print("✓ \(icns.path)")

if CommandLine.arguments.contains("--preview") {
    let previewDirectory = root.appendingPathComponent("build/preview")
    try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
    for size in [1024, 128, 32, 16] {
        guard let image = render(size: size) else { continue }
        let url = previewDirectory.appendingPathComponent("icon-\(size).png")
        try write(image, to: url)
        print("  \(size)px → \(url.path)")
    }
}
