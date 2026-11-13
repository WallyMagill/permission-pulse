import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct FullDiskAccessFlowTests {
    private let version = AppVersion(shortVersion: "0.7.2", build: "12")

    @Test func earlierCaptureAndAnOlderBuildClassifyAsLostAfterUpdateThenRecordThisBuild() async throws {
        let env = try ScanEnvironment(appVersion: version)
        defer { env.cleanUp() }
        _ = try await env.store.writeSnapshot(
            grants: [], launchAgents: [], btmItems: [], coverage: .allComplete,
            at: Date().addingTimeInterval(-86_400)
        )
        env.delegate.runtimeDefaults.set("0.7.1 (11)", forKey: AppDelegate.lastLaunchedVersionKey)
        env.delegate.viewModel.tccAvailability = .failed(lastSuccessful: nil, error: .permissionDenied(reason: "FDA"))

        let first = await env.delegate.classifyFullDiskAccessLoss()
        let second = await env.delegate.classifyFullDiskAccessLoss()

        #expect(first == .lostAfterUpdate)
        #expect(second == .revoked)
        #expect(env.delegate.runtimeDefaults.string(forKey: AppDelegate.lastLaunchedVersionKey) == "0.7.2 (12)")
    }

    @Test func promptOpensOncePerVersionAndNeverOnFirstRun() async throws {
        var shown: [FullDiskAccessLoss] = []
        let env = try ScanEnvironment(appVersion: version) { shown.append($0) }
        defer { env.cleanUp() }

        await env.delegate.handleFullDiskAccessLoss(.firstRun)
        await env.delegate.handleFullDiskAccessLoss(.lostAfterUpdate)
        await env.delegate.handleFullDiskAccessLoss(.revoked)

        #expect(shown == [.lostAfterUpdate])
        #expect(env.delegate.runtimeDefaults.string(forKey: AppDelegate.fdaPromptShownForVersionKey) == "0.7.2 (12)")
    }

    @Test func promptAlsoNotifiesWhenChangeAlertsAreOn() async throws {
        let env = try ScanEnvironment(appVersion: version) { _ in }
        defer { env.cleanUp() }
        env.delegate.preferencesStore.changeAlertsEnabled = true

        await env.delegate.handleFullDiskAccessLoss(.revoked)

        let alerts = await env.scheduler.oneShots(withPrefix: ChangeAlertCoordinator.identifierPrefix)
        #expect(alerts.map(\.identifier) == [ChangeAlertCoordinator.fullDiskAccessIdentifier])
        #expect(alerts.first?.body == "Full Disk Access was turned off. Open Permission Pulse to turn it back on.")
    }

    @Test func withoutHistoryNothingIsClassifiedOrRecorded() async {
        let delegate = AppDelegate(
            runtimeEnvironment: AppRuntimeEnvironment(environment: ["PERMISSION_PULSE_TEST_MODE": "1"]),
            appVersion: version
        )
        delegate.viewModel.tccAvailability = .failed(lastSuccessful: nil, error: .permissionDenied(reason: "FDA"))

        #expect(await delegate.classifyFullDiskAccessLoss() == nil)
        #expect(delegate.runtimeDefaults.string(forKey: AppDelegate.lastLaunchedVersionKey) == nil)
    }

    @Test func aDeniedBackgroundItemsScanAloneIsNotALoss() async throws {
        let env = try ScanEnvironment(appVersion: version)
        defer { env.cleanUp() }
        _ = try await env.store.writeSnapshot(
            grants: [], launchAgents: [], btmItems: [], coverage: .allComplete,
            at: Date().addingTimeInterval(-86_400)
        )
        env.delegate.viewModel.tccAvailability = .complete(lastUpdated: Date())
        env.delegate.viewModel.btmAvailability = .failed(lastSuccessful: nil, error: .permissionDenied(reason: "unreadable .btm"))

        #expect(await env.delegate.classifyFullDiskAccessLoss() == nil)
    }

    @Test func returningDuringAScanReportsThatScansResult() async throws {
        let env = try ScanEnvironment(appVersion: version)
        defer { env.cleanUp() }
        let recovery = env.delegate.fullDiskAccessRecovery
        recovery.beginWaiting()
        recovery.appResignedActive()
        env.delegate.viewModel.tccAvailability = .failed(lastSuccessful: nil, error: .permissionDenied(reason: "FDA"))
        let inFlight = try #require(env.delegate.startScanIfIdle())

        await env.delegate.recheckFullDiskAccessIfReturning()

        #expect(recovery.phase == .restored)
        #expect(await inFlight.value)
    }

    @Test func dismissingWelcomeLeavesTheRecoveryWindowsStateAlone() throws {
        let env = try ScanEnvironment(appVersion: version)
        defer { env.cleanUp() }
        env.delegate.fullDiskAccessRecovery.beginWaiting()

        env.delegate.welcomeDismissAction()()

        #expect(env.delegate.fullDiskAccessRecovery.phase == .waiting)
    }
}
