import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite struct PermissionsDisplayItemTests {
    @Test func nonAutomationGrantsPassThroughAsSingles() {
        let grants = [
            grant(.microphone, "com.example.a"),
            grant(.camera, "com.example.b"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 2)
        #expect(items.allSatisfy { if case .single = $0 { return true } else { return false } })
    }

    @Test func singleAutomationGrantStaysSingle() {
        let grants = [
            automation("com.example.tool", target: "com.apple.finder"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 1)
        if case .single = items[0] {} else { Issue.record("Expected .single") }
    }

    @Test func multipleAutomationGrantsForSameAppGroup() {
        let grants = [
            automation("com.raycast.macos", target: "com.apple.systemevents"),
            automation("com.raycast.macos", target: "com.apple.MobileSMS"),
            automation("com.raycast.macos", target: "com.apple.shortcuts.events"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 1)
        guard case .automationGroup(let group) = items[0] else {
            Issue.record("Expected .automationGroup"); return
        }
        #expect(group.targets.count == 3)
        #expect(group.app.bundleID == "com.raycast.macos")
    }

    @Test func differentAppsAreNotGrouped() {
        let grants = [
            automation("com.example.a", target: "com.apple.finder"),
            automation("com.example.a", target: "com.apple.MobileSMS"),
            automation("com.example.b", target: "com.apple.finder"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        // App A → grouped (2 targets). App B → single (1 target).
        #expect(items.count == 2)
        let groupCount = items.filter {
            if case .automationGroup = $0 { return true } else { return false }
        }.count
        #expect(groupCount == 1)
    }

    @Test func nonAutomationServicesDoNotGroupEvenAcrossSameApp() {
        // Defensive: only .automation gets bundled. Two microphone grants for
        // the same app (post-dedupe shouldn't happen, but be safe) stay as
        // two singles, not a fake group.
        let grants = [
            grant(.microphone, "com.example.a"),
            grant(.microphone, "com.example.a"),
        ]
        let items = PermissionsDisplayItem.make(from: grants)
        #expect(items.count == 2)
        #expect(items.allSatisfy { if case .single = $0 { return true } else { return false } })
    }

    // MARK: - Helpers

    private func grant(_ service: PermissionService, _ bundleID: String) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID),
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
