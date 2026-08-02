import AppKit
import ScreenCaptureKit
import TrimshotCore

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplays
    case captureFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording permission was denied."
        case .noDisplays:
            "No displays were available to capture."
        case .captureFailed(let error):
            "Screen capture failed: \(error.localizedDescription)"
        }
    }
}

/// Grabs a full-resolution still of every display.
///
/// The app captures *first* and shows the overlay on top of the frozen result, the way
/// Lightshot does. A live transparent overlay would drift — video keeps playing, menus
/// close, the cursor moves — so the pixels you finally crop would not be the pixels you
/// selected. Freezing also makes the magnifier and the colour picker exact, since they
/// read the same bitmap that gets cropped.
@MainActor
enum ScreenCapturer {

    static func captureAllDisplays() async throws -> [DisplayShot] {
        guard PermissionGate.hasScreenRecordingAccess else {
            throw CaptureError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw CaptureError.captureFailed(error)
        }

        guard !content.displays.isEmpty else { throw CaptureError.noDisplays }

        let screensByID = Dictionary(
            NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
                guard let id = screen.displayID else { return nil }
                return (id, screen)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Sequential rather than a task group: SCDisplay is not Sendable, and a handful
        // of displays at ~40 ms each stays well inside the latency budget for the
        // overlay to feel instant.
        var shots: [DisplayShot] = []
        for display in content.displays {
            guard let screen = screensByID[display.displayID] else { continue }

            let geometry = DisplayGeometry(
                displayID: display.displayID,
                frame: screen.frame,
                scale: screen.backingScaleFactor
            )

            do {
                let image = try await capture(display: display, geometry: geometry)
                shots.append(DisplayShot(geometry: geometry, image: image))
            } catch {
                throw CaptureError.captureFailed(error)
            }
        }

        guard !shots.isEmpty else { throw CaptureError.noDisplays }
        return shots
    }

    private static func capture(
        display: SCDisplay,
        geometry: DisplayGeometry
    ) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        // Ask for the display's true pixel dimensions so Retina content is not halved.
        configuration.width = Int(geometry.pixelSize.width.rounded())
        configuration.height = Int(geometry.pixelSize.height.rounded())
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }
}

extension NSScreen {
    /// The `CGDirectDisplayID` that ties an `NSScreen` to an `SCDisplay`.
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
