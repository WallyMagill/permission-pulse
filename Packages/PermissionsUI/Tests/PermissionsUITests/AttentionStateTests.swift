import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite("AttentionState")
struct AttentionStateTests {
    @Test("Clean when no errors")
    func clean() {
        #expect(AttentionState.evaluate(tccError: nil, btmError: nil, launchAgentError: nil) == .clean)
    }

    @Test("TCC permission denial wins over everything")
    func fdaDenied() {
        #expect(AttentionState.evaluate(
            tccError: .permissionDenied(reason: "denied"), btmError: .permissionDenied(reason: "denied"), launchAgentError: nil
        ) == .fdaDenied)
    }

    @Test("BTM-only denial is its own state")
    func btmOnly() {
        #expect(AttentionState.evaluate(
            tccError: nil, btmError: .permissionDenied(reason: "denied"), launchAgentError: nil
        ) == .btmOnlyFDADenied)
    }

    @Test("Schema mismatch and launch-agent errors rank below denial")
    func ordering() {
        #expect(AttentionState.evaluate(
            tccError: .schemaMismatch(detail: "x"), btmError: nil, launchAgentError: nil
        ) == .schemaMismatch)
        #expect(AttentionState.evaluate(
            tccError: nil, btmError: nil, launchAgentError: .temporarilyUnavailable(reason: "db")
        ) == .launchAgentError)
    }

    @Test("Schema mismatch outranks a concurrent launch-agent error")
    func schemaMismatchBeatsLaunchAgentError() {
        #expect(AttentionState.evaluate(
            tccError: .schemaMismatch(detail: "x"),
            btmError: nil,
            launchAgentError: .temporarilyUnavailable(reason: "db")
        ) == .schemaMismatch)
    }
}
