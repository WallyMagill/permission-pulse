import Foundation
import PermissionsCore
import PermissionsStore

/// The status lines under Recent Changes' window picker: when history last
/// moved, what each domain was compared with, and why any domain was not.
/// A stalled or partial history must be visible, not silent.
enum RecentChangesStatus {
    static func lines(diff: SnapshotDiffs?, latestSnapshotDate: Date?) -> [String] {
        var lines: [String] = []
        if let latestSnapshotDate {
            lines.append(String(localized: "History updated \(format(latestSnapshotDate))"))
        }
        guard let diff else { return lines }
        lines += comparisonLines(diff)
        if diff.systemLevelPermissionsOnly {
            lines.append(String(localized: "Compared system-level permissions only"))
        }
        for domain in diff.uncomparedDomains {
            if let reason = diff.uncompared[domain] {
                lines.append(uncomparedLine(domain, reason: reason))
            }
        }
        return lines
    }

    /// One line when every compared domain shares a baseline, otherwise one
    /// line per baseline naming its domains.
    static func comparisonLines(_ diff: SnapshotDiffs) -> [String] {
        let groups = baselineGroups(diff)
        guard groups.count > 1 else {
            return groups.map { comparedWith($0.baseline, reviewed: diff.reviewedSnapshotID) }
        }
        return groups.map { group in
            let domains = ListFormatter.localizedString(byJoining: group.domains.map(\.displayName))
            let date = format(group.baseline.date)
            return group.baseline.id == diff.reviewedSnapshotID
                ? String(localized: "\(domains) compared with \(date), your last review")
                : String(localized: "\(domains) compared with \(date)")
        }
    }

    /// One complete sentence per domain, so each translation can make its
    /// verb agree with the domain's name.
    static func uncomparedLine(_ domain: HistoryDomain, reason: UncomparedReason) -> String {
        switch reason {
        case .scopeChanged: scopeChangedLine(domain)
        case .latestScanFailed: latestScanFailedLine(domain)
        case .itemsUnreadable: itemsUnreadableLine(domain)
        case .noEarlierSnapshot: noEarlierSnapshotLine(domain)
        }
    }

    private static func scopeChangedLine(_ domain: HistoryDomain) -> String {
        switch domain {
        case .tcc: String(localized: "Permissions weren't compared: macOS changed what Permission Pulse can read during this window.")
        case .btm: String(localized: "Background Items weren't compared: macOS changed what Permission Pulse can read during this window.")
        case .launchAgents: String(localized: "Launch Agents weren't compared: macOS changed what Permission Pulse can read during this window.")
        }
    }

    private static func latestScanFailedLine(_ domain: HistoryDomain) -> String {
        switch domain {
        case .tcc: String(localized: "Permissions weren't compared: the latest scan couldn't read them, usually because Full Disk Access is off.")
        case .btm: String(localized: "Background Items weren't compared: the latest scan couldn't read them, usually because Full Disk Access is off.")
        case .launchAgents: String(localized: "Launch Agents weren't compared: the latest scan couldn't read them.")
        }
    }

    private static func itemsUnreadableLine(_ domain: HistoryDomain) -> String {
        switch domain {
        case .tcc: String(localized: "Permissions weren't compared: some items couldn't be read during this window.")
        case .btm: String(localized: "Background Items weren't compared: some items couldn't be read during this window.")
        case .launchAgents: String(localized: "Launch Agents weren't compared: some items couldn't be read during this window.")
        }
    }

    private static func noEarlierSnapshotLine(_ domain: HistoryDomain) -> String {
        switch domain {
        case .tcc: String(localized: "Permissions weren't compared: no earlier snapshot recorded them.")
        case .btm: String(localized: "Background Items weren't compared: no earlier snapshot recorded them.")
        case .launchAgents: String(localized: "Launch Agents weren't compared: no earlier snapshot recorded them.")
        }
    }

    static func writeFailedLine(latestSnapshotDate: Date?) -> String {
        guard let latestSnapshotDate else {
            return String(localized: "Couldn't save the latest snapshot. Changes are not being recorded.")
        }
        let date = format(latestSnapshotDate)
        return String(localized: "Couldn't save the latest snapshot. Changes found since \(date) are not recorded.")
    }

    private struct BaselineGroup {
        let baseline: DiffBaseline
        var domains: [HistoryDomain]
    }

    private static func baselineGroups(_ diff: SnapshotDiffs) -> [BaselineGroup] {
        var groups: [BaselineGroup] = []
        for domain in diff.comparedDomains {
            guard let baseline = diff.baselines[domain] else { continue }
            if let index = groups.firstIndex(where: { $0.baseline == baseline }) {
                groups[index].domains.append(domain)
            } else {
                groups.append(BaselineGroup(baseline: baseline, domains: [domain]))
            }
        }
        return groups
    }

    private static func comparedWith(_ baseline: DiffBaseline, reviewed: SnapshotID?) -> String {
        let date = format(baseline.date)
        return baseline.id == reviewed
            ? String(localized: "Compared with \(date), your last review")
            : String(localized: "Compared with \(date)")
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
