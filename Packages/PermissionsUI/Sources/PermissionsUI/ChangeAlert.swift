import Foundation

/// The local notification posted when a scan writes a snapshot that differs
/// from the previous one.
public struct ChangeAlert: Sendable, Equatable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    /// The alert for the changes in `diff` the user has not dismissed or
    /// snoozed, or nil when there is nothing to tell them. Entries from a
    /// domain the diff did not compare are ignored even if present, so a
    /// partial endpoint can never announce false additions or removals.
    @MainActor
    public static func make(
        for diff: SnapshotDiffs?,
        dismissals: DismissedDiffEntryStore?,
        asOf date: Date
    ) -> ChangeAlert? {
        guard let diff else { return nil }
        let visible = dismissals?.visibleEntries(in: diff, asOf: date) ?? diff.entries
        let entries = visible.filter { diff.uncompared[$0.domain] == nil }
        guard let first = entries.first else { return nil }
        let title = String(localized: "Permission Pulse: something changed")
        guard entries.count > 1 else { return ChangeAlert(title: title, body: first.summary) }
        let count = entries.count
        let others = count - 1
        // Two or more in all, so only "the rest" can be singular.
        let body = others == 1
            ? String(localized: "2 changes: \(first.summary) and 1 other change.")
            : String(localized: "\(count) changes: \(first.summary) and \(others) other changes.")
        return ChangeAlert(title: title, body: body)
    }
}
