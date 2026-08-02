import AppKit

// The diagnostic entry points are debug-only, and that is a security boundary rather than
// tidiness.
//
// Both of them capture every display and write the result to a path taken straight from
// argv, with no user interaction. In a release build that turns this app into a confused
// deputy: any local process — including one that has no Screen Recording permission of its
// own and would be denied if it asked — could run
//
//     open -a "Trimshot" --args --render-chrome /tmp/steal
//
// and read the screenshots back out of /tmp, borrowing *our* TCC grant. Launching the
// binary directly does not work (TCC blames the calling process), but going through
// LaunchServices makes the app its own responsible process, so the grant applies.
//
// Compiling them out of release builds closes that. The verification scripts build a debug
// bundle on purpose — see scripts/self-check.sh.
#if DEBUG
    if let flagIndex = CommandLine.arguments.firstIndex(of: "--self-check") {
        let directory = CommandLine.arguments.count > flagIndex + 1
            ? URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1], isDirectory: true)
            : FileManager.default.temporaryDirectory
        SelfCheck.run(outputDirectory: directory)
    }

    if CommandLine.arguments.contains("--dump-status") {
        StatusDump.run()
    }

    if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-chrome") {
        let directory = CommandLine.arguments.count > flagIndex + 1
            ? URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1], isDirectory: true)
            : FileManager.default.temporaryDirectory
        ChromePreview.run(outputDirectory: directory)
    }
#endif

// Normal launch. `.accessory` keeps the app out of the Dock and the ⌘-Tab switcher —
// it lives in the menu bar only, like Lightshot.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
