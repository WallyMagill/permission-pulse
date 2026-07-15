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

    @Test("Any degraded domain is non-clean")
    func degraded() {
        let degraded = ScanAvailability.degraded(
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            warnings: [.init(source: .entries, omittedCount: 1)]
        )
        #expect(evaluate(tcc: degraded) == .degradedData)
        #expect(evaluate(btm: degraded) == .degradedData)
        #expect(evaluate(launch: degraded) == .degradedData)
    }

    @Test("Failed TCC and BTM domains without history report a scan failure")
    func failedWithoutHistory() {
        let failed = ScanAvailability.failed(
            lastSuccessful: nil,
            error: .temporarilyUnavailable(reason: "busy")
        )
        #expect(evaluate(tcc: failed) == .scanFailed)
        #expect(evaluate(btm: failed) == .scanFailed)
    }

    @Test("Failed TCC and BTM domains with history report stale data")
    func failedWithHistory() {
        let failed = ScanAvailability.failed(
            lastSuccessful: Date(timeIntervalSince1970: 1_700_000_000),
            error: .temporarilyUnavailable(reason: "busy")
        )
        #expect(evaluate(tcc: failed) == .staleData)
        #expect(evaluate(btm: failed) == .staleData)
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
            warnings: [.init(source: .entries)]
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
        #expect(evaluate(tcc: schema, btm: stale, launch: degraded) == .schemaMismatch)
    }

    @Test("Stale data outranks degraded data")
    func staleBeatsDegraded() {
        let degraded = ScanAvailability.degraded(
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            warnings: [.init(source: .entries)]
        )
        let stale = ScanAvailability.failed(
            lastSuccessful: Date(timeIntervalSince1970: 1_700_000_000),
            error: .temporarilyUnavailable(reason: "busy")
        )
        #expect(evaluate(tcc: degraded, btm: stale) == .staleData)
    }

    @Test("Scan failure without history outranks degraded data")
    func scanFailureBeatsDegraded() {
        let degraded = ScanAvailability.degraded(
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            warnings: [.init(source: .entries)]
        )
        let failed = ScanAvailability.failed(
            lastSuccessful: nil,
            error: .temporarilyUnavailable(reason: "busy")
        )

        #expect(evaluate(tcc: degraded, btm: failed) == .scanFailed)
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
