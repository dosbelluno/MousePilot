import AppKit
import ApplicationServices
import Foundation
import MousePilotCore

@MainActor
enum AppDiagnostics {
    /// Reads the current signed app's actual TCC results; never prompts or posts input.
    /// This mode exits before SwiftUI creates a window or the mapping engine starts.
    static func report() -> String {
        let accessibility = AXIsProcessTrusted()
        let inputMonitoring = CGPreflightListenEventAccess()
        let postEvents = CGPreflightPostEventAccess()
        let ready = accessibility && postEvents
        var lines = [
            "MousePilot diagnostics",
            "app: \(Bundle.main.bundleURL.path)",
            "version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")",
            "accessibility: \(accessibility)",
            "inputMonitoring (optional): \(inputMonitoring)",
            "postEvents: \(postEvents)",
            "permissionsReady: \(ready)"
        ]
        if let index = CommandLine.arguments.firstIndex(of: "--request-id"),
           CommandLine.arguments.indices.contains(index + 1) {
            lines.insert("requestID: \(CommandLine.arguments[index + 1])", at: 1)
        }
        if ready {
            let mask = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
            if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: diagnosticPassThrough, userInfo: nil) {
                lines.append("mouseTapCreated: true")
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            } else { lines.append("mouseTapCreated: false") }
        } else {
            lines.append("mouseTapCreated: not attempted (permissions unavailable)")
            lines.append("If macOS toggles are already on, remove the old MousePilot entry and add this app again. A prior ad hoc build may have a different code requirement.")
        }
        return lines.joined(separator: "\n")
    }

    static var outputURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MousePilot", isDirectory: true)
            .appendingPathComponent("last-diagnostic.txt")
    }

    static func save(_ report: String) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}

private func diagnosticPassThrough(proxy: CGEventTapProxy, type: CGEventType,
                                  event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    Unmanaged.passUnretained(event)
}
