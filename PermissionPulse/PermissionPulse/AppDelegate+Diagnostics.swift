import Foundation
import PermissionsCore
import PermissionsStore
import PermissionsUI

extension AppDelegate {
    /// The text Preferences → Data → Copy Diagnostics puts on the clipboard.
    func diagnosticsText() async -> String {
        let authorization = await weeklyDigestScheduler.currentAuthorizationStatus()
        let latestCoverage = await latestSnapshotCoverage()
        preferencesViewModel.refreshLaunchAtLoginStatus()
        return DiagnosticsReport(
            viewModel: viewModel,
            preferences: preferencesStore,
            appVersion: appVersion,
            bundlePath: Bundle.main.bundlePath,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            latestCoverage: latestCoverage,
            schemaVersion: try? snapshotStore?.schemaVersion(),
            notificationAuthorization: authorization,
            launchAtLogin: preferencesViewModel.launchAtLoginStatus
        ).text
    }

    private func latestSnapshotCoverage() async -> SnapshotDomainCoverage? {
        guard let snapshotStore, let id = viewModel.latestSnapshotID else { return nil }
        return try? await snapshotStore.coverage(snapshotID: id)
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
