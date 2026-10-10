import Foundation
import Testing
@testable import PermissionsUI

@Suite struct RecentChangesStatusTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func noHistoryNoLines() {
        #expect(RecentChangesStatus.lines(latestSnapshotDate: nil, uncompared: []).isEmpty)
    }

    @Test func historyDateOnly() {
        let lines = RecentChangesStatus.lines(latestSnapshotDate: date, uncompared: [])
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("History updated "))
    }

    @Test func oneLinePerUncomparedDomainInOrder() {
        let lines = RecentChangesStatus.lines(latestSnapshotDate: date, uncompared: [.tcc, .launchAgents])
        #expect(lines.dropFirst() == [
            "Permissions weren't compared — a scan in this window was incomplete.",
            "Launch Agents weren't compared — a scan in this window was incomplete.",
        ])
    }
}
