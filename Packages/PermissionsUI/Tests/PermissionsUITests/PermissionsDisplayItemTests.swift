import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite struct PermissionsDisplayItemTests {
    @Test func eachDistinctAppProducesOneAppGroup() {
        let grants = [
            grant(.microphone, "com.example.a", name: "App A"),
            grant(.camera, "com.example.b", name: "App B"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 2)
        #expect(items.allSatisfy { if case .appGroup = $0 { return true } else { return false } })
    }

    @Test func multipleServicesForSameAppAggregateIntoOneGroup() {
        let grants = [
            grant(.camera, "us.zoom.xos", name: "Zoom"),
            grant(.microphone, "us.zoom.xos", name: "Zoom"),
            grant(.screenRecording, "us.zoom.xos", name: "Zoom"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 1)
        #expect(items[0].grants.count == 3)
        #expect(items[0].distinctServices.count == 3)
        #expect(items[0].app.bundleID == "us.zoom.xos")
    }

    @Test func duplicateServiceGrantsDedupeInDistinctServices() {
        // Two microphone grants for the same app (defensive: shouldn't happen
        // post-scanner-dedupe but the UI must not show "Microphone · Microphone").
        let grants = [
            grant(.microphone, "com.example.a", name: "App A"),
            grant(.microphone, "com.example.a", name: "App A"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 1)
        #expect(items[0].grants.count == 2)
        #expect(items[0].distinctServices == [.microphone])
    }

    @Test func multipleAutomationGrantsCollapseToOneServiceEntry() {
        let grants = [
            automation("com.raycast.macos", target: "com.apple.systemevents"),
            automation("com.raycast.macos", target: "com.apple.MobileSMS"),
            automation("com.raycast.macos", target: "com.apple.shortcuts.events"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 1)
        #expect(items[0].distinctServices == [.automation])
        #expect(items[0].automationGrants.count == 3)
    }

    @Test func mixedAutomationAndOtherServicesForSameApp() {
        let grants = [
            grant(.accessibility, "com.raycast.macos", name: "Raycast"),
            grant(.inputMonitoring, "com.raycast.macos", name: "Raycast"),
            automation("com.raycast.macos", target: "com.apple.systemevents"),
            automation("com.raycast.macos", target: "com.apple.MobileSMS"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 1)
        // Distinct services: Accessibility, Automation, Input Monitoring
        #expect(items[0].distinctServices.count == 3)
        #expect(items[0].distinctServices.contains(.accessibility))
        #expect(items[0].distinctServices.contains(.inputMonitoring))
        #expect(items[0].distinctServices.contains(.automation))
        // Automation targets queryable
        #expect(items[0].automationGrants.count == 2)
    }

    @Test func emptyBundleIDDoesNotCollapseAcrossUnknownApps() {
        let grants = [
            grant(.microphone, "", name: "Unknown 1"),
            grant(.camera, "", name: "Unknown 2"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 2)
        // Both items must have distinct ids so SwiftUI doesn't merge them.
        #expect(Set(items.map(\.id)).count == 2)
    }

    @Test func sortOrderIsCaseInsensitiveByDisplayName() {
        let grants = [
            grant(.microphone, "com.zebra", name: "zebra"),
            grant(.microphone, "com.alpha", name: "Alpha"),
            grant(.microphone, "com.bravo", name: "BRAVO"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 3)
        #expect(items[0].app.displayName == "Alpha")
        #expect(items[1].app.displayName == "BRAVO")
        #expect(items[2].app.displayName == "zebra")
    }

    @Test func sameDisplayNameDifferentBundleIDsStaySeparate() {
        let grants = [
            grant(.microphone, "com.helper.one", name: "Helper"),
            grant(.camera, "com.helper.two", name: "Helper"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 2)
        #expect(items[0].app.bundleID != items[1].app.bundleID)
    }

    @Test func mostRecentGrantPicksLatestModification() {
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_100_000)
        let grants = [
            PermissionGrant(
                service: .microphone,
                app: AppIdentity(bundleID: "com.example.a", displayName: "App A"),
                lastModified: earlier
            ),
            PermissionGrant(
                service: .microphone,
                app: AppIdentity(bundleID: "com.example.a", displayName: "App A"),
                lastModified: later
            ),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 1)
        #expect(items[0].mostRecentGrant(for: .microphone)?.lastModified == later)
    }

    // MARK: - Helpers

    private func grant(_ service: PermissionService, _ bundleID: String, name: String) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: name),
            lastModified: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func automation(_ bundleID: String, target: String) -> PermissionGrant {
        PermissionGrant(
            service: .automation,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID),
            lastModified: Date(timeIntervalSince1970: 1_700_000_000),
            automationTarget: target
        )
    }
}
