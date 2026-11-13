import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite struct FullDiskAccessLossTests {
    @Test func neverCapturedIsFirstRunWhateverTheVersion() {
        #expect(FullDiskAccessLoss.classify(capturedBefore: false, lastLaunchedVersion: nil, runningVersion: "0.7.2 (12)") == .firstRun)
        #expect(FullDiskAccessLoss.classify(capturedBefore: false, lastLaunchedVersion: "0.7.1 (11)", runningVersion: "0.7.2 (12)") == .firstRun)
    }

    @Test func capturedBeforeWithADifferentOrMissingVersionIsLostAfterUpdate() {
        #expect(FullDiskAccessLoss.classify(capturedBefore: true, lastLaunchedVersion: "0.7.2 (11)", runningVersion: "0.7.2 (12)") == .lostAfterUpdate)
        #expect(FullDiskAccessLoss.classify(capturedBefore: true, lastLaunchedVersion: nil, runningVersion: "0.7.2 (12)") == .lostAfterUpdate)
    }

    @Test func capturedBeforeWithTheSameVersionIsRevoked() {
        #expect(FullDiskAccessLoss.classify(capturedBefore: true, lastLaunchedVersion: "0.7.2 (12)", runningVersion: "0.7.2 (12)") == .revoked)
    }

    @Test func onlyPermissionDeniedCountsAsDenied() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let ok = ScanAvailability.complete(lastUpdated: date)
        #expect(FullDiskAccessLoss.isDenied(tcc: .failed(lastSuccessful: nil, error: .permissionDenied(reason: "x")), btm: ok))
        #expect(FullDiskAccessLoss.isDenied(tcc: ok, btm: .failed(lastSuccessful: nil, error: .permissionDenied(reason: "x"))))
        #expect(!FullDiskAccessLoss.isDenied(tcc: .failed(lastSuccessful: nil, error: .temporarilyUnavailable(reason: "busy")), btm: ok))
    }
}

@Suite @MainActor struct FullDiskAccessRecoveryTests {
    @Test func recheckOnlyAfterLeavingTheAppWhileWaiting() {
        let recovery = FullDiskAccessRecovery()
        recovery.beginWaiting()
        // The window's own activation is not a return from System Settings.
        #expect(!recovery.shouldRecheckOnActivation())

        recovery.appResignedActive()
        #expect(recovery.shouldRecheckOnActivation())
        #expect(!recovery.shouldRecheckOnActivation())

        recovery.end()
        recovery.appResignedActive()
        #expect(!recovery.shouldRecheckOnActivation())
    }
}

@Suite struct AppLocationTests {
    @Test func homeIsShownAsTilde() {
        #expect(AppLocation.displayPath("/Users/a/Applications/PP.app", home: "/Users/a") == "~/Applications/PP.app")
        #expect(AppLocation.displayPath("/Users/ab/PP.app", home: "/Users/a") == "/Users/ab/PP.app")
        #expect(AppLocation.displayPath("/Applications/PP.app", home: "/Users/a") == "/Applications/PP.app")
    }

    @Test func translocatedPathIsDetected() {
        #expect(AppLocation.isTranslocated("/private/var/folders/xy/T/AppTranslocation/1234/d/Permission Pulse.app"))
        #expect(!AppLocation.isTranslocated("/Applications/Permission Pulse.app"))
    }
}
