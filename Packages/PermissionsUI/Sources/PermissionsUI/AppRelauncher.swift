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

    /// Launch a new instance of this app, then terminate the current process.
    /// Used to recover from the FDA grant loop, where a running process stays
    /// denied until restart. (U3)
    public static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } catch {
                // The app still terminates below; the user must reopen manually.
                logger.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
            }
            NSApp.terminate(nil)
        }
    }
}
