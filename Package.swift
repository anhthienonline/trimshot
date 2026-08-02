// swift-tools-version: 6.0
import PackageDescription

// No external dependencies on purpose: this project builds with Command Line Tools
// only (no full Xcode), and popular Swift packages tend to use #Preview, whose macro
// plugin ships exclusively with Xcode.
//
// For the same reason there is no SwiftPM test target: CLT ships neither XCTest nor
// the swift-testing runtime. Pure logic lives in `TrimshotCore` and is exercised by
// the `TrimshotChecks` executable — run it with `swift run TrimshotChecks`.
let package = Package(
    name: "Trimshot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Trimshot", targets: ["Trimshot"]),
        .executable(name: "TrimshotChecks", targets: ["TrimshotChecks"]),
    ],
    targets: [
        // Pure, UI-free logic: coordinate math, image sampling, annotation rendering.
        .target(
            name: "TrimshotCore",
            path: "Sources/TrimshotCore"
        ),
        // The AppKit app.
        .executableTarget(
            name: "Trimshot",
            dependencies: ["TrimshotCore"],
            path: "Sources/Trimshot"
        ),
        // Stands in for `swift test`.
        .executableTarget(
            name: "TrimshotChecks",
            dependencies: ["TrimshotCore"],
            path: "Sources/TrimshotChecks"
        ),
    ]
)
