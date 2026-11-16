import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite("AttentionState")
struct AttentionStateTests {
    private let complete = ScanAvailability.complete(
        lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
    )

    @Test("Never and complete states are clean")
    func clean() {
        #expect(AttentionState.evaluate(
            tccAvailability: .never,
            btmAvailability: .never,
            launchAgentAvailability: .never
        ) == .clean)
        #expect(AttentionState.evaluate(
            tccAvailability: complete,
            btmAvailability: complete,
            launchAgentAvailability: complete
        ) == .clean)
    }

    @Test("A degraded domain is non-clean and named")
    func degraded() {
        let degraded = ScanAvailability.degraded(
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            warnings: [.init(source: .userLaunchAgents)]
        )
        #expect(evaluate(tcc: degraded) == .degradedData([.permissions]))
        #expect(evaluate(btm: degraded) == .degradedData([.backgroundItems]))
        #expect(evaluate(launch: degraded) == .degradedData([.launchAgents]))
        #expect(evaluate(tcc: degraded, launch: degraded) == .degradedData([.permissions, .launchAgents]))
    }

    @Test("Omitted entries alone are informational, not attention")
    func omittedEntriesOnlyIsClean() {
        let entriesOnly = ScanAvailability.degraded(
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            warnings: [.init(source: .entries, omittedCount: 2, omittedNames: ["a.plist", "b.plist"])]
        )
        #expect(evaluate(launch: entriesOnly) == .clean)
        #expect(entriesOnly.onlyOmittedEntries)
    }

    @Test("Failed TCC and BTM domains without history report a scan failure")
    func failedWithoutHistory() {
        let failed = ScanAvailability.failed(
            lastSuccessful: nil,
            error: .temporarilyUnavailable(reason: "busy")
        )
        #expect(evaluate(tcc: failed) == .scanFailed([.permissions]))
        #expect(evaluate(btm: failed) == .scanFailed([.backgroundItems]))
        #expect(evaluate(tcc: failed, btm: failed) == .scanFailed([.permissions, .backgroundItems]))
    }

    @Test("Failed TCC and BTM domains with history report stale data")
    func failedWithHistory() {
        let failed = ScanAvailability.failed(
            lastSuccessful: Date(timeIntervalSince1970: 1_700_000_000),
            error: .temporarilyUnavailable(reason: "busy")
        )
        #expect(evaluate(tcc: failed) == .staleData([.permissions]))
        #expect(evaluate(btm: failed) == .staleData([.backgroundItems]))
    }

    @Test("LaunchAgent failure retains its dedicated attention state")
    func launchAgentFailure() {
        let failed = ScanAvailability.failed(
            lastSuccessful: nil,
            error: .temporarilyUnavailable(reason: "busy")
        )
        #expect(evaluate(launch: failed) == .launchAgentError)
    }

    @Test("FDA and schema states outrank stale and degraded data")
    func precedence() {
        let degraded = ScanAvailability.degraded(
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            warnings: [.init(source: .userLaunchAgents)]
        )
        let stale = ScanAvailability.failed(
            lastSuccessful: nil,
            error: .temporarilyUnavailable(reason: "busy")
        )
        let denied = ScanAvailability.failed(
            lastSuccessful: nil,
            error: .permissionDenied(reason: "denied")
        )
        let schema = ScanAvailability.failed(
            lastSuccessful: nil,
            error: .schemaMismatch(detail: "changed")
        )

        #expect(evaluate(tcc: denied, btm: stale, launch: degraded) == .fdaDenied)
        #expect(evaluate(tcc: schema, btm: denied, launch: stale) == .btmOnlyFDADenied)
        #expect(evaluate(tcc: schema, btm: stale, launch: degraded) == .schemaMismatch([.permissions]))
        #expect(evaluate(btm: schema) == .schemaMismatch([.backgroundItems]))
    }

    @Test("Stale data outranks degraded data")
    func staleBeatsDegraded() {
        let degraded = ScanAvailability.degraded(
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            warnings: [.init(source: .userLaunchAgents)]
        )
        let stale = ScanAvailability.failed(
            lastSuccessful: Date(timeIntervalSince1970: 1_700_000_000),
            error: .temporarilyUnavailable(reason: "busy")
        )
        #expect(evaluate(tcc: degraded, btm: stale) == .staleData([.backgroundItems]))
    }

    @Test("Scan failure without history outranks degraded data")
    func scanFailureBeatsDegraded() {
        let degraded = ScanAvailability.degraded(
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            warnings: [.init(source: .userLaunchAgents)]
        )
        let failed = ScanAvailability.failed(
            lastSuccessful: nil,
            error: .temporarilyUnavailable(reason: "busy")
        )

        #expect(evaluate(tcc: degraded, btm: failed) == .scanFailed([.backgroundItems]))
    }

    @Test("A history problem needs attention, below scan failures")
    func historyNotRecorded() {
        #expect(AttentionState.evaluate(
            tccAvailability: complete, btmAvailability: complete, launchAgentAvailability: complete,
            historyNotRecorded: true
        ) == .historyNotRecorded)
        let failed = ScanAvailability.failed(lastSuccessful: nil, error: .temporarilyUnavailable(reason: "busy"))
        let items = AttentionState.items(
            tccAvailability: failed, btmAvailability: complete, launchAgentAvailability: complete,
            historyNotRecorded: true
        )
        #expect(items == [
            AttentionItem(state: .scanFailed([.permissions]), domain: .permissions),
            AttentionItem(state: .historyNotRecorded, domain: .history),
        ])
    }

    @Test("Full Disk Access off doesn't hide a Launch Agents error")
    func fdaOffKeepsOtherSections() {
        let denied = ScanAvailability.failed(lastSuccessful: nil, error: .permissionDenied(reason: "FDA"))
        let failed = ScanAvailability.failed(lastSuccessful: nil, error: .temporarilyUnavailable(reason: "busy"))
        let items = AttentionState.items(
            tccAvailability: denied, btmAvailability: complete, launchAgentAvailability: failed
        )
        #expect(items.map(\.domain) == [.permissions, .launchAgents])
        #expect(items.map(\.state) == [.fdaDenied, .launchAgentError])
    }

    private func evaluate(
        tcc: ScanAvailability? = nil,
        btm: ScanAvailability? = nil,
        launch: ScanAvailability? = nil
    ) -> AttentionState {
        AttentionState.evaluate(
            tccAvailability: tcc ?? complete,
            btmAvailability: btm ?? complete,
            launchAgentAvailability: launch ?? complete
        )
    }
}
