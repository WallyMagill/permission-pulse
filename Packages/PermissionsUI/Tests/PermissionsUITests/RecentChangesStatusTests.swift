import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite struct RecentChangesStatusTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func diff(
        baselines: [HistoryDomain: DiffBaseline] = [:],
        uncompared: [HistoryDomain: UncomparedReason] = [:],
        systemLevelOnly: Bool = false,
        reviewed: SnapshotID? = nil
    ) -> SnapshotDiffs {
        SnapshotDiffs(
            toID: SnapshotID(rawValue: 9),
            tcc: TCCGrantsDiff(added: [], removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: []),
            baselines: baselines,
            uncompared: uncompared,
            systemLevelPermissionsOnly: systemLevelOnly,
            reviewedSnapshotID: reviewed
        )
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    @Test func noHistoryNoLines() {
        #expect(RecentChangesStatus.lines(diff: nil, latestSnapshotDate: nil).isEmpty)
    }

    @Test func sharedBaselineNamesTheLastReview() {
        let reviewed = DiffBaseline(id: SnapshotID(rawValue: 4), date: date)
        let all = Dictionary(uniqueKeysWithValues: HistoryDomain.allCases.map { ($0, reviewed) })

        #expect(RecentChangesStatus.lines(diff: diff(baselines: all, reviewed: reviewed.id), latestSnapshotDate: nil)
            == ["Compared with \(formatted(date)), your last review"])
        #expect(RecentChangesStatus.lines(diff: diff(baselines: all), latestSnapshotDate: nil)
            == ["Compared with \(formatted(date))"])
    }

    @Test func differentBaselinesGetOneLineEach() {
        let older = DiffBaseline(id: SnapshotID(rawValue: 2), date: date.addingTimeInterval(-86_400))
        let reviewed = DiffBaseline(id: SnapshotID(rawValue: 4), date: date)
        let lines = RecentChangesStatus.lines(
            diff: diff(baselines: [.tcc: older, .btm: reviewed, .launchAgents: reviewed], reviewed: reviewed.id),
            latestSnapshotDate: nil
        )
        #expect(lines == [
            "Permissions compared with \(formatted(older.date))",
            "Background Items and Launch Agents compared with \(formatted(date)), your last review",
        ])
    }

    @Test func eachUncomparedDomainSaysWhy() {
        let lines = RecentChangesStatus.lines(
            diff: diff(uncompared: [
                .tcc: .scopeChanged,
                .btm: .latestScanFailed,
                .launchAgents: .itemsUnreadable,
            ]),
            latestSnapshotDate: nil
        )
        #expect(lines == [
            "Permissions weren't compared: macOS changed what Permission Pulse can read during this window.",
            "Background Items weren't compared: the latest scan couldn't read them, usually because Full Disk Access is off.",
            "Launch Agents weren't compared: some items couldn't be read during this window.",
        ])
        #expect(RecentChangesStatus.uncomparedLine(.tcc, reason: .noEarlierSnapshot)
            == "Permissions weren't compared: no earlier snapshot recorded them.")
    }

    @Test func narrowedComparisonIsStated() {
        let baseline = DiffBaseline(id: SnapshotID(rawValue: 5), date: date)
        let lines = RecentChangesStatus.lines(diff: diff(baselines: [.tcc: baseline], systemLevelOnly: true), latestSnapshotDate: nil)
        #expect(lines.last == "Compared system-level permissions only")
    }

    @Test func aReducedScopeEmptyStateNamesWhatWasCompared() {
        let baseline = DiffBaseline(id: SnapshotID(rawValue: 5), date: date)
        let all = Dictionary(uniqueKeysWithValues: HistoryDomain.allCases.map { ($0, baseline) })

        #expect(DiffTabView.emptyDescription(diff(baselines: all, systemLevelOnly: true))
            == "No changes in system-level permissions, background items, or launch agents.")
        #expect(DiffTabView.emptyDescription(diff(baselines: all))
            == "Nothing was added, removed, or changed in this window.")
    }

    @Test func emptyStateNamesUncomparedDomains() {
        let baseline = DiffBaseline(id: SnapshotID(rawValue: 5), date: date)
        let partial = diff(baselines: [.launchAgents: baseline], uncompared: [.tcc: .latestScanFailed, .btm: .latestScanFailed])
        let none = diff(uncompared: [.tcc: .latestScanFailed, .btm: .latestScanFailed, .launchAgents: .itemsUnreadable])

        #expect(DiffTabView.uncomparedHeadline(partial) == "Some history couldn't be compared")
        #expect(DiffTabView.uncomparedDescription(partial)
            == "No changes found in Launch Agents. Permissions and Background Items couldn't be compared; the notes above say why.")
        #expect(DiffTabView.uncomparedHeadline(none) == "Nothing could be compared")
    }
}
