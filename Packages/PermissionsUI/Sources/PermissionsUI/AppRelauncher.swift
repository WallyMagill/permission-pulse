// AppKit: there is no SwiftUI/Foundation primitive that restarts the running
// app. We spawn a fresh instance of our own bundle, then terminate this one —
// the standard Sparkle-less relaunch. Read-only: launches our own bundle only.
import AppKit
import OSLog

public enum AppRelauncher {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "app-relauncher"
    )

    /// Names the process a relaunched instance replaces, so the new one waits
    /// for it to quit instead of handing off to it as a duplicate.
    public static let relaunchedFromArgument = "--relaunched-from"

    /// Launch a new instance of this app, then terminate the current process.
    /// Used to recover from the FDA grant loop, where a running process stays
    /// denied until restart. (U3)
    public static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            relaunchedFromArgument,
            String(ProcessInfo.processInfo.processIdentifier),
        ]
        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                // New instance is live — only now is it safe to drop this one.
                NSApp.terminate(nil)
            } catch {
                // Launch failed: keep the current instance running so the user
                // isn't left with no app. They can retry or quit manually.
                logger.error("Relaunch failed; keeping current instance: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The process ID passed by `relaunch()`, if this instance was started by it.
    public static func relaunchedFromPID(in arguments: [String]) -> pid_t? {
        guard let index = arguments.firstIndex(of: relaunchedFromArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return pid_t(arguments[index + 1])
    }
}
