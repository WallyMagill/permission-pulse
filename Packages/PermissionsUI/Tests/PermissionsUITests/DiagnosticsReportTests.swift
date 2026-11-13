import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite @MainActor struct DiagnosticsReportTests {
    @Test func reportCarriesCountsAndKindsButNoOtherAppsIdentifiersOrPaths() throws {
        let viewModel = AppViewModel(
            grants: [PermissionGrant(
                service: .screenRecording,
                app: AppIdentity(
                    bundleID: "us.zoom.xos",
                    displayName: "Zoom",
                    bundlePath: URL(fileURLWithPath: "/Applications/zoom.us.app")
                ),
                lastModified: Date(timeIntervalSince1970: 0)
            )],
            launchAgents: [LaunchAgentItem(
                label: "com.vendor.updater",
                sourceDirectory: .userLaunchAgents,
                programPath: "/Users/someone/Library/Vendor/updater",
                programArguments: ["--secret-flag"],
                runAtLoad: true,
                keepAlive: false
            )],
            btmItems: [BTMItem(
                identifier: "16.com.vendor.helper",
                name: "Vendor Helper",
                developerName: "Vendor Inc.",
                bundleIdentifier: "com.vendor.helper",
                teamIdentifier: "ABCDE12345",
                type: .loginItem,
                disposition: .enabled,
                scope: .user,
                modificationDate: Date(timeIntervalSince1970: 0)
            )],
            btmAvailability: .failed(
                lastSuccessful: nil,
                error: .permissionDenied(reason: "/Library/Application Support/com.apple.TCC/TCC.db")
            )
        )
        let preferences = PreferencesStore(
            defaults: try #require(UserDefaults(suiteName: "diagnostics-\(UUID().uuidString)"))
        )

        let text = DiagnosticsReport(
            viewModel: viewModel,
            preferences: preferences,
            appVersion: AppVersion(shortVersion: "0.7.2", build: "12"),
            bundlePath: "/Users/someone/Applications/Permission Pulse.app",
            home: "/Users/someone",
            osVersion: "Version 26.1 (Build 25B78)",
            architecture: "arm64",
            latestCoverage: .allComplete,
            schemaVersion: 7,
            notificationAuthorization: .denied,
            launchAtLogin: .requiresApproval
        ).text

        for leak in [
            "us.zoom.xos", "zoom.us.app", "Zoom", "com.vendor.updater", "Library/Vendor", "--secret-flag",
            "com.vendor.helper", "Vendor", "ABCDE12345", "TCC.db", "/Applications/zoom", "/Users/someone",
        ] {
            #expect(!text.contains(leak), "diagnostics leaked \(leak)")
        }
        #expect(text.contains("app: 0.7.2 (12)"))
        #expect(text.contains("bundlePath: ~/Applications/Permission Pulse.app"))
        #expect(text.contains("permissions: availability=never coverage=complete error=none unavailableSources=[] items=1"))
        #expect(text.contains("backgroundItems: availability=failed coverage=complete error=permissionDenied"))
        #expect(text.contains("schemaVersion: 7"))
        #expect(text.contains("launchAtLogin: requiresApproval"))
    }
}
