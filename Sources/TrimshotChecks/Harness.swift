import Foundation

/// A ~50-line stand-in for XCTest.
///
/// Command Line Tools ships neither XCTest nor the swift-testing runtime, so
/// `swift test` cannot work on this machine. This gives the same value —
/// `swift run TrimshotChecks` exits non-zero when something breaks, which is all
/// CI or a pre-commit hook needs.
enum Check {
    nonisolated(unsafe) private static var failures: [String] = []
    nonisolated(unsafe) private static var passed = 0
    nonisolated(unsafe) private static var currentSuite = ""

    static func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        print("\n\(name)")
        body()
    }

    static func expect(
        _ condition: Bool,
        _ label: String,
        detail: @autoclosure () -> String = "",
        line: UInt = #line
    ) {
        if condition {
            passed += 1
            print("  ✓ \(label)")
        } else {
            let extra = detail()
            let message = "\(currentSuite) › \(label) (line \(line))"
                + (extra.isEmpty ? "" : "\n      \(extra)")
            failures.append(message)
            print("  ✗ \(label)\(extra.isEmpty ? "" : "\n      \(extra)")")
        }
    }

    static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ label: String,
        line: UInt = #line
    ) {
        expect(
            actual == expected,
            label,
            detail: "expected \(expected)\n      actual   \(actual)",
            line: line
        )
    }

    /// Prints the summary and terminates with an exit code suitable for CI.
    static func finish() -> Never {
        print("\n\(passed) passed, \(failures.count) failed")
        if !failures.isEmpty {
            print("\nFailures:")
            for f in failures { print("  • \(f)") }
            exit(1)
        }
        exit(0)
    }
}
