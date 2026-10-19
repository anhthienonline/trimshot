import CoreGraphics
import Foundation
import os

/// Logging that survives into release builds, unlike the `--self-check` family.
///
/// This exists because a copy that silently produced nothing was impossible to diagnose from
/// the outside: the HUD said "Copied" either way, so there was no signal at all. Everything
/// here is *metadata* — sizes, colour spaces, byte counts, success flags. No pixels, no file
/// contents, no window titles, nothing from the captured image itself.
///
/// Watch it live with:
///
///     log stream --level debug --predicate 'subsystem == "com.thienho.trimshot"'
///
/// The verdict lines are `.info` rather than `.debug` on purpose: debug records are not
/// retained, so an intermittent fault could only ever be caught while already streaming.
/// `.info` can be read back afterwards:
///
///     log show --last 30m --predicate 'subsystem == "com.thienho.trimshot"' --info
enum Diagnostics {
    static let clipboard = Logger(subsystem: "com.thienho.trimshot", category: "clipboard")
    static let capture = Logger(subsystem: "com.thienho.trimshot", category: "capture")

    /// A one-line description of a bitmap's actual format, which is the thing that decides
    /// whether the encoders below will accept it.
    static func describe(_ image: CGImage) -> String {
        let space = image.colorSpace?.name.map(String.init(describing:)) ?? "nil"
        return """
            \(image.width)×\(image.height) \
            bpc=\(image.bitsPerComponent) bpp=\(image.bitsPerPixel) \
            alpha=\(image.alphaInfo.rawValue) \
            bitmapInfo=0x\(String(image.bitmapInfo.rawValue, radix: 16)) \
            space=\(space)
            """
    }
}
