import Foundation

/// The status lines under Recent Changes' window picker: when history last
/// moved, and which domains a window could not compare. A stalled history
/// must be visible, not silent.
enum RecentChangesStatus {
    static func lines(latestSnapshotDate: Date?, uncompared: [HistoryDomain]) -> [String] {
        var lines: [String] = []
        if let latestSnapshotDate {
            let date = latestSnapshotDate.formatted(date: .abbreviated, time: .shortened)
            lines.append(String(localized: "History updated \(date)"))
        }
        for domain in uncompared {
            lines.append(String(localized: "\(domain.displayName) weren't compared — a scan in this window was incomplete."))
        }
        return lines
    }
}
