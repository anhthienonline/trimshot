import CoreGraphics
import Foundation

/// One display's frozen bitmap, taken at the moment the hotkey fired.
///
/// `CGImage` is immutable and thread-safe in practice but not marked `Sendable`,
/// hence the `@unchecked` — the app only ever reads these.
public struct DisplayShot: @unchecked Sendable {
    public let geometry: DisplayGeometry
    /// Origin top-left, Y down, sized `geometry.pixelSize`.
    public let image: CGImage

    public init(geometry: DisplayGeometry, image: CGImage) {
        self.geometry = geometry
        self.image = image
    }
}

public enum ImageCompositor {

    /// Cuts a rect — given in AppKit global points — out of the frozen display shots.
    ///
    /// Works across displays: the selection is painted onto one canvas, each display
    /// drawn at its own position. Mixed scale factors are handled by rendering at the
    /// highest scale involved, so dragging from a Retina screen onto a 1x monitor keeps
    /// the Retina half at full resolution instead of halving it.
    ///
    /// Returns nil when the rect is empty or touches no display.
    public static func crop(globalRect: CGRect, from shots: [DisplayShot]) -> CGImage? {
        let touched = shots.filter {
            let overlap = $0.geometry.frame.intersection(globalRect)
            return !overlap.isNull && !overlap.isEmpty
        }
        guard !touched.isEmpty else { return nil }

        let scale = touched.map(\.geometry.scale).max() ?? 1
        let pixelWidth = Int((globalRect.width * scale).rounded())
        let pixelHeight = Int((globalRect.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.interpolationQuality = .high

        // A bitmap CGContext has its origin at the bottom-left with Y up, the same
        // orientation as AppKit global points — so display positions map over directly,
        // and `draw(_:in:)` places each bitmap upright. Anything outside the canvas is
        // clipped for free.
        for shot in touched {
            let frame = shot.geometry.frame
            let destination = CGRect(
                x: (frame.minX - globalRect.minX) * scale,
                y: (frame.minY - globalRect.minY) * scale,
                width: frame.width * scale,
                height: frame.height * scale
            )
            context.draw(shot.image, in: destination)
        }

        return context.makeImage()
    }

    /// The display shot under a point in AppKit global coordinates.
    public static func shot(at globalPoint: CGPoint, from shots: [DisplayShot]) -> DisplayShot? {
        shots.first { $0.geometry.frame.contains(globalPoint) }
    }
}
