import Foundation
import OSLog
import PermissionsCore

// Hybrid last-used probe: Spotlight via `mdls` first, then the bundle's
// file-system modification date. Returns nil if both miss — caller skips
// the app from Stale review (under-flag, never over-flag, per
// docs/04-data-sources.md).
//
// Note for a future sandboxed build (v0.6.0+): Process(/usr/bin/mdls)
// requires the sandbox to be off or a binary entitlement. The drop-in
// replacement is MDItemCreate / MDItemCopyAttribute in-process.
public struct LastUsedProbeHybrid: LastUsedProbe, Sendable {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "last-used-probe"
    )

    // Bound mdls invocations to avoid runaway hangs on pathological metadata.
    private static let mdlsTimeout: Duration = .seconds(2)

    public init() {}

    public func lastUsedDate(
        for bundlePath: URL
    ) async -> (date: Date, source: StaleApp.DateSource)? {
        if let spotlight = await spotlightDate(for: bundlePath) {
            return (spotlight, .spotlight)
        }
        if let fileSystem = fileSystemDate(for: bundlePath) {
            return (fileSystem, .fileSystem)
        }
        return nil
    }

    private func spotlightDate(for bundlePath: URL) async -> Date? {
        let path = bundlePath.path(percentEncoded: false)
        return await withTaskGroup(of: Date?.self) { group in
            group.addTask { await Self.runMDLS(path: path) }
            group.addTask {
                try? await Task.sleep(for: Self.mdlsTimeout)
                return nil
            }
            // First-to-finish wins. Cancel the other.
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
    }

    private static func runMDLS(path: String) async -> Date? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-name", "kMDItemLastUsedDate", "-raw", path]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Date?, Never>) in
                process.terminationHandler = { proc in
                    guard proc.terminationStatus == 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    let raw = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if raw.isEmpty || raw == "(null)" {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: Self.parseMDLSDate(raw))
                }
                do {
                    try process.run()
                } catch {
                    logger.error("mdls launch failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            // Cancellation (e.g. the 2s timeout) fired: signal mdls to terminate
            // (SIGTERM) so its terminationHandler runs and the continuation
            // resumes — no orphaned process, no stranded continuation. terminate()
            // on an already-exited process is harmless. (R4)
            if process.isRunning { process.terminate() }
        }
    }

    private static func parseMDLSDate(_ raw: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        if let d = fmt.date(from: raw) { return d }
        return ISO8601DateFormatter().date(from: raw)
    }

    private func fileSystemDate(for bundlePath: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let values = try? bundlePath.resourceValues(forKeys: keys) else {
            return nil
        }
        return values.contentModificationDate
    }
}
