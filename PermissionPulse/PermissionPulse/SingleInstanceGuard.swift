import AppKit
import OSLog
import PermissionsUI

/// One running copy of Permission Pulse, as the launch decision sees it.
struct RunningInstance: Equatable, Sendable {
    let pid: pid_t
    let bundleURL: URL?
    let launchDate: Date?

    /// Earlier launch first; equal (or unknown) dates fall back to the
    /// lower process ID, so every copy computes the same order.
    func launched(before other: RunningInstance) -> Bool {
        let mine = launchDate ?? .distantPast
        let theirs = other.launchDate ?? .distantPast
        return mine == theirs ? pid < other.pid : mine < theirs
    }
}

/// Two copies with one bundle identifier, run from two paths, would share and
/// fight over one history database. Only one may run.
enum SingleInstanceDecision: Equatable, Sendable {
    case proceed
    /// Another copy runs this same code: bring it forward and quit this one.
    case handOff(to: pid_t)
    /// Continue once these copies have exited. `waitFor` is the process
    /// `AppRelauncher` replaces, which quits on its own; `terminate` are
    /// copies running other code (an older build, another path), which this
    /// copy asks to quit.
    case replace(waitFor: pid_t?, terminate: [pid_t])

    /// `executableModified` is when this copy's executable last changed on
    /// disk: a copy launched before then runs code that has since been
    /// replaced, even from the same path.
    static func decide(
        current: RunningInstance,
        executableModified: Date?,
        others: [RunningInstance],
        relaunchedFrom: pid_t?
    ) -> SingleInstanceDecision {
        let unrelated = others.filter { $0.pid != relaunchedFrom }
        let peers = unrelated.filter { runsSameCode($0, as: current, executableModified: executableModified) }
        let leader = ([current] + peers).min { $0.launched(before: $1) } ?? current
        if leader.pid != current.pid { return .handOff(to: leader.pid) }
        // A copy with other code that launched after this one is deciding
        // too, and will replace this one; asking it to quit would leave none.
        let replaced = unrelated
            .filter { !peers.contains($0) && $0.launched(before: current) }
            .map(\.pid)
        let waitFor = others.contains { $0.pid == relaunchedFrom } ? relaunchedFrom : nil
        if waitFor == nil && replaced.isEmpty { return .proceed }
        return .replace(waitFor: waitFor, terminate: replaced)
    }

    private static func runsSameCode(
        _ other: RunningInstance,
        as current: RunningInstance,
        executableModified: Date?
    ) -> Bool {
        guard let otherURL = other.bundleURL, let currentURL = current.bundleURL,
              otherURL.standardizedFileURL == currentURL.standardizedFileURL,
              let launched = other.launchDate, let executableModified else { return false }
        return launched > executableModified
    }

    /// A process ID can be reused once its process exits, so a live process
    /// counts as ours only while it still has our bundle identifier.
    static func hasExited(isTerminated: Bool?, bundleIdentifier: String?, expected: String) -> Bool {
        guard let isTerminated else { return true }
        return isTerminated || bundleIdentifier != expected
    }
}

// AppKit: NSRunningApplication and NSWorkspace are the only ways to find,
// reactivate, or ask another running copy of this app to quit.
@MainActor
enum SingleInstanceGuard {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "single-instance"
    )

    /// A guess: a copy asked to quit normally exits within a second, so ten
    /// seconds leaves room for a slow quit without hanging forever.
    static let exitWaitLimit: Duration = .seconds(10)
    static let exitPollInterval: Duration = .milliseconds(100)

    /// True when this instance should finish launching.
    static func resolve() async -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let decision = SingleInstanceDecision.decide(
            current: instance(NSRunningApplication.current),
            executableModified: executableModificationDate(),
            others: otherInstances(bundleID: bundleID),
            relaunchedFrom: AppRelauncher.relaunchedFromPID(in: ProcessInfo.processInfo.arguments)
        )
        switch decision {
        case .proceed:
            return true
        case .handOff(let pid):
            await handOff(to: pid)
            return false
        case .replace(let waitFor, let terminate):
            for pid in terminate {
                logger.info("Asking pid \(pid) running other code to quit")
                NSRunningApplication(processIdentifier: pid)?.terminate()
            }
            await waitForExit(of: terminate + [waitFor].compactMap { $0 }, bundleID: bundleID)
            return true
        }
    }

    private static func instance(_ app: NSRunningApplication) -> RunningInstance {
        RunningInstance(pid: app.processIdentifier, bundleURL: app.bundleURL, launchDate: app.launchDate)
    }

    private static func otherInstances(bundleID: String) -> [RunningInstance] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated && $0.processIdentifier != own }
            .map(instance)
    }

    /// Copying an app keeps its files' content dates, so the inode change
    /// date (set by every copy, move, or write) is the later of the two.
    private static func executableModificationDate() -> Date? {
        guard let url = Bundle.main.executableURL,
              let values = try? url.resourceValues(forKeys: [
                  .contentModificationDateKey, .attributeModificationDateKey,
              ]) else { return nil }
        return [values.contentModificationDate, values.attributeModificationDate].compactMap { $0 }.max()
    }

    /// Waits for each process to exit; one still running at the limit is
    /// force-quit, so this copy never quits leaving nothing running.
    private static func waitForExit(of pids: [pid_t], bundleID: String) async {
        let deadline = ContinuousClock.now.advanced(by: exitWaitLimit)
        var remaining = pids
        while !remaining.isEmpty {
            remaining.removeAll { isGone($0, bundleID: bundleID) }
            guard !remaining.isEmpty, ContinuousClock.now < deadline else { break }
            try? await Task.sleep(for: exitPollInterval)
        }
        for pid in remaining {
            guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == bundleID else { continue }
            logger.error("pid \(pid) still running after \(exitWaitLimit); force-quitting it")
            app.forceTerminate()
        }
    }

    private static func isGone(_ pid: pid_t, bundleID: String) -> Bool {
        let app = NSRunningApplication(processIdentifier: pid)
        return SingleInstanceDecision.hasExited(
            isTerminated: app?.isTerminated,
            bundleIdentifier: app?.bundleIdentifier,
            expected: bundleID
        )
    }

    /// Opening the running copy's bundle sends it a reopen event, which shows
    /// its window; then this copy quits without touching the database.
    private static func handOff(to pid: pid_t) async {
        logger.info("Another instance (pid \(pid)) runs this code; handing off")
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
