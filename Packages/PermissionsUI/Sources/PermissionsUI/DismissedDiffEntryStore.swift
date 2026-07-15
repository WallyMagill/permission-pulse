import Foundation
import OSLog
import Observation

/// Persists per-row diff dismissals as a JSON `[String: Date]` map under
/// `com.wallymagill.permissionpulse.dismissedDiffEntries`. Keys map to
/// expiry timestamps:
///
/// - distantFuture → dismissed forever
/// - any other date → snoozed until that date; treated as dismissed only
///   while `asOf < expiry`
///
/// Defensive on read: a corrupt blob logs and falls back to an empty
/// map so the rest of the UI never crashes from bad persisted state.
@Observable
@MainActor
public final class DismissedDiffEntryStore {
    public static let key = "com.wallymagill.permissionpulse.dismissedDiffEntries"

    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "dismissed-diff-entry-store"
    )

    private let defaults: UserDefaults
    private var entries: [String: Date]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    public func isDismissed(key: String, asOf date: Date) -> Bool {
        guard let expiry = entries[key] else { return false }
        return expiry > date
    }

    public func dismissForever(key: String) {
        entries[key] = .distantFuture
        persist()
    }

    public func snooze(key: String, until expiry: Date) {
        entries[key] = expiry
        persist()
    }

    public func undismiss(key: String) {
        entries.removeValue(forKey: key)
        persist()
    }

    /// Drops entries whose expiry has passed. Cheap; safe to call every
    /// time the Recent Changes page appears.
    public func pruneExpired(asOf date: Date) {
        let before = entries.count
        entries = entries.filter { _, expiry in expiry > date }
        if entries.count != before {
            persist()
        }
    }

    public func allEntries() -> [String: Date] {
        entries
    }

    public func removeAll() {
        entries.removeAll()
        persist()
    }

    // MARK: - Private

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: Self.key)
        } catch {
            Self.logger.error(
                "Failed to encode dismissed entries: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func load(from defaults: UserDefaults) -> [String: Date] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        do {
            return try JSONDecoder().decode([String: Date].self, from: data)
        } catch {
            logger.error(
                "Failed to decode dismissed entries; starting empty: \(error.localizedDescription, privacy: .public)"
            )
            return [:]
        }
    }
}
