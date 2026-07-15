import Foundation
import OSLog
import Observation

/// Persists a set of bundle IDs the user has chosen to skip in the
/// Stale Apps tab forever. Backed by a `[String]` UserDefaults array
/// under `com.wallymagill.permissionpulse.dismissedStaleApps`.
///
/// No expiry — "Skip forever" is intentional. The user can un-skip via
/// the Preferences "Reset all data" flow.
@Observable
@MainActor
public final class DismissedStaleAppStore {
    public static let key = "com.wallymagill.permissionpulse.dismissedStaleApps"

    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "dismissed-stale-app-store"
    )

    private let defaults: UserDefaults
    private var bundleIDs: Set<String>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.bundleIDs = Self.load(from: defaults)
    }

    public func contains(bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }

    public func skipForever(bundleID: String) {
        guard !bundleIDs.contains(bundleID) else { return }
        bundleIDs.insert(bundleID)
        persist()
    }

    public func unskip(bundleID: String) {
        guard bundleIDs.contains(bundleID) else { return }
        bundleIDs.remove(bundleID)
        persist()
    }

    public func allBundleIDs() -> Set<String> {
        bundleIDs
    }

    public func removeAll() {
        bundleIDs.removeAll()
        persist()
    }

    // MARK: - Private

    private func persist() {
        defaults.set(Array(bundleIDs), forKey: Self.key)
    }

    private static func load(from defaults: UserDefaults) -> Set<String> {
        // UserDefaults will return nil for a missing key, but also nil if the
        // stored value isn't an [String] (someone wrote garbage). Treat both
        // as "empty set" and let the next write overwrite.
        guard let raw = defaults.array(forKey: key) else { return [] }
        guard let strings = raw as? [String] else {
            logger.error("Stale-app set blob has unexpected type; starting empty")
            return []
        }
        return Set(strings)
    }
}
