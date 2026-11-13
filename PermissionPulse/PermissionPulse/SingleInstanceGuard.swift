import AppKit
import OSLog
import PermissionsUI

/// Two copies with one bundle identifier, run from two paths, would share and
/// fight over one history database. Only one may run.
nonisolated enum SingleInstanceDecision: Equatable, Sendable {
    case proceed
    /// Started by `AppRelauncher`: the old process quits on its own shortly.
    case waitForExit(pid_t)
    /// Another copy is already running: bring it forward and quit this one.
    case handOff(to: pid_t)

    static func decide(otherInstancePIDs: [pid_t], relaunchedFrom: pid_t?) -> SingleInstanceDecision {
        let unrelated = otherInstancePIDs.filter { $0 != relaunchedFrom }
        if let existing = unrelated.min() { return .handOff(to: existing) }
        if let relaunchedFrom, otherInstancePIDs.contains(relaunchedFrom) {
            return .waitForExit(relaunchedFrom)
        }
        return .proceed
    }
}

// AppKit: NSRunningApplication and NSWorkspace are the only ways to find and
// reactivate another running copy of this app.
@MainActor
enum SingleInstanceGuard {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "single-instance"
    )

    /// A guess: the old instance quits as soon as the new one is launched,
    /// so ten seconds leaves room for a slow quit without hanging forever.
    static let relaunchWaitLimit: Duration = .seconds(10)
    static let relaunchPollInterval: Duration = .milliseconds(100)

    /// True when this instance should finish launching.
    static func resolve() async -> Bool {
        let decision = SingleInstanceDecision.decide(
            otherInstancePIDs: otherInstancePIDs(),
            relaunchedFrom: AppRelauncher.relaunchedFromPID(in: ProcessInfo.processInfo.arguments)
        )
        switch decision {
        case .proceed:
            return true
        case .waitForExit(let pid):
            if await waitForExit(pid) { return true }
            logger.error("Relaunched-from process \(pid) still running after \(relaunchWaitLimit); handing off")
            await handOff(to: pid)
            return false
        case .handOff(let pid):
            await handOff(to: pid)
            return false
        }
    }

    private static func otherInstancePIDs() -> [pid_t] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated && $0.processIdentifier != own }
            .map(\.processIdentifier)
    }

    private static func waitForExit(_ pid: pid_t) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: relaunchWaitLimit)
        while ContinuousClock.now < deadline {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return true }
            try? await Task.sleep(for: relaunchPollInterval)
        }
        return NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true
    }

    /// Opening the running copy's bundle sends it a reopen event, which shows
    /// its window; then this copy quits without touching the database.
    private static func handOff(to pid: pid_t) async {
        logger.info("Another instance (pid \(pid)) is running; handing off")
        if let app = NSRunningApplication(processIdentifier: pid) {
            if let url = app.bundleURL {
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                app.activate()
            }
        }
        NSApp.terminate(nil)
    }
}
