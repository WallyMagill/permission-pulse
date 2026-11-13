import Foundation
import Testing
import PermissionsUI
@testable import PermissionPulse

@Suite struct SingleInstanceTests {
    @Test func aloneProceeds() {
        #expect(SingleInstanceDecision.decide(otherInstancePIDs: [], relaunchedFrom: nil) == .proceed)
    }

    @Test func anotherRunningCopyIsHandedOffTo() {
        #expect(SingleInstanceDecision.decide(otherInstancePIDs: [412], relaunchedFrom: nil) == .handOff(to: 412))
    }

    @Test func relaunchWaitsForTheProcessItReplaces() {
        #expect(SingleInstanceDecision.decide(otherInstancePIDs: [412], relaunchedFrom: 412) == .waitForExit(412))
        #expect(SingleInstanceDecision.decide(otherInstancePIDs: [], relaunchedFrom: 412) == .proceed)
    }

    @Test func relaunchStillHandsOffToAThirdCopy() {
        #expect(SingleInstanceDecision.decide(otherInstancePIDs: [412, 977], relaunchedFrom: 412) == .handOff(to: 977))
    }

    @Test func relaunchArgumentRoundTrips() {
        let arguments = ["/Applications/Permission Pulse.app/Contents/MacOS/PermissionPulse", AppRelauncher.relaunchedFromArgument, "412"]
        #expect(AppRelauncher.relaunchedFromPID(in: arguments) == 412)
        #expect(AppRelauncher.relaunchedFromPID(in: [AppRelauncher.relaunchedFromArgument]) == nil)
        #expect(AppRelauncher.relaunchedFromPID(in: ["-NSDocumentRevisionsDebugMode", "YES"]) == nil)
    }
}
