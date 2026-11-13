import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite @MainActor struct InstallStateTests {
    private func grant(_ bundleID: String, _ service: PermissionService) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: nil),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil,
            authValue: 2
        )
    }

    private func agent(_ label: String) -> LaunchAgentItem {
        LaunchAgentItem(
            label: label, sourceDirectory: .userLaunchAgents,
            programPath: "/opt/\(label)", programArguments: [], runAtLoad: true, keepAlive: false
        )
    }

    @Test func eachAppAndAgentIsCheckedOncePerScanAndCached() {
        let vm = AppViewModel(
            grants: [grant("com.example.gone", .camera), grant("com.example.gone", .microphone), grant("com.example.here", .camera)],
            launchAgents: [agent("gone"), agent("here")],
            tccDataSource: .live
        )
        var appChecks: [String] = []
        var agentChecks = 0

        vm.refreshInstallState(
            isAppMissing: { appChecks.append($0.bundleID); return $0.bundleID == "com.example.gone" },
            isProgramMissing: { agentChecks += 1; return $0.label == "gone" }
        )

        #expect(appChecks.sorted() == ["com.example.gone", "com.example.here"])
        #expect(agentChecks == 2)
        #expect(vm.missingAppKeys == [grant("com.example.gone", .camera).appKey])
        #expect(vm.missingProgramAgentIDs == [agent("gone").id])
    }

    @Test func mockGrantsAreNeverCalledMissing() {
        let vm = AppViewModel(grants: [grant("com.example.gone", .camera)], tccDataSource: .mock)

        vm.refreshInstallState(isAppMissing: { _ in true }, isProgramMissing: { _ in false })

        #expect(vm.missingAppKeys.isEmpty)
    }
}
