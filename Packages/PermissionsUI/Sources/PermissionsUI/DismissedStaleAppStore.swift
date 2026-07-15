import Foundation
import OSLog
import Observation

/// Persists a set of stable application keys the user has chosen to skip in the
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
    private var stableKeys: Set<String>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.stableKeys = Self.load(from: defaults)
    }

    public func contains(stableKey: String) -> Bool {
        stableKeys.contains(stableKey)
    }

    public func skipForever(stableKey: String) {
        guard !stableKeys.contains(stableKey) else { return }
        stableKeys.insert(stableKey)
        persist()
    }

    public func unskip(stableKey: String) {
        guard stableKeys.contains(stableKey) else { return }
        stableKeys.remove(stableKey)
        persist()
    }

    public func allStableKeys() -> Set<String> {
        stableKeys
    }

    public func removeAll() {
        stableKeys.removeAll()
        persist()
    }

    // MARK: - Private

    private func persist() {
        defaults.set(stableKeys.sorted(), forKey: Self.key)
    }

    private static func load(from defaults: UserDefaults) -> Set<String> {
        // UserDefaults returns nil for a missing key or a non-array value.
        // Preserve valid strings in a mixed array and ignore invalid entries.
        guard let raw = defaults.array(forKey: key) else { return [] }
        let strings = raw.compactMap { $0 as? String }
        if strings.count != raw.count {
            logger.error("Stale-app set blob contains invalid entries; ignoring them")
        }
        let migrated = strings.map { stableKey in
            if stableKey.hasPrefix("bundle:") || stableKey.hasPrefix("path:") {
                return stableKey
            }
            return "bundle:\(stableKey)"
        }
        return Set(migrated)
    }
}
