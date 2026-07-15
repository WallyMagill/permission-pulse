import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite @MainActor struct DiffEntryKeyTests {
    private func grant(
        authValue: Int,
        bundleID: String = "com.example.photos",
        displayName: String = "Photo Editor",
        bundlePath: String? = "/Applications/Photo Editor.app"
    ) -> PermissionGrant {
        PermissionGrant(
            service: .photos,
            app: AppIdentity(
                bundleID: bundleID,
                displayName: displayName,
                bundlePath: bundlePath.map(URL.init(fileURLWithPath:))
            ),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: "com.example.target",
            authValue: authValue
        )
    }

    @Test func tccAuthorizationChangeHasLocalizedSummaryAndTransitionKey() {
        let change = DomainChange(before: grant(authValue: 2), after: grant(authValue: 3))
        let kind = ChangeRow.Kind.permissionChanged(change)

        #expect(ChangeRow.summary(for: kind).contains("Allowed → Limited"))
        #expect(DiffEntryKey.key(for: kind) == "tcc-changed|photos|com.example.photos|com.example.target|2-3")
    }

    @Test func renderedRowSearchCoversEveryRecentChangesCategory() {
        let permissionChange = ChangeRow.Kind.permissionChanged(
            DomainChange(before: grant(authValue: 2), after: grant(authValue: 3))
        )
        let backgroundItem = ChangeRow.Kind.btmAdded(BTMItem(
            identifier: "com.example.background-helper",
            name: "Background Helper",
            developerName: "Example Developer",
            bundleIdentifier: "com.example.background",
            teamIdentifier: "TEAM123",
            type: .app,
            disposition: .enabled,
            scope: .user,
            modificationDate: Date(timeIntervalSince1970: 0)
        ))
        let launchAgent = ChangeRow.Kind.launchAgentAdded(LaunchAgentItem(
            label: "com.example.sync-agent",
            sourceDirectory: .userLaunchAgents,
            programPath: "/usr/local/bin/sync-agent",
            programArguments: ["--sync", "/Users/example/Documents"],
            runAtLoad: true,
            keepAlive: false
        ))
        let rows = [permissionChange, backgroundItem, launchAgent]

        #expect(ChangeRow.filtered(rows, searchText: "limited").map(\.id) == [permissionChange.id])
        #expect(ChangeRow.filtered(rows, searchText: "photo editor.app").map(\.id) == [permissionChange.id])
        #expect(ChangeRow.filtered(rows, searchText: "example developer").map(\.id) == [backgroundItem.id])
        #expect(ChangeRow.filtered(rows, searchText: "background-helper").map(\.id) == [backgroundItem.id])
        #expect(ChangeRow.filtered(rows, searchText: "sync-agent").map(\.id) == [launchAgent.id])
        #expect(ChangeRow.filtered(rows, searchText: "documents").map(\.id) == [launchAgent.id])
    }

    @Test func tccGrantedKeyContainsServiceBundleAndAutomationTarget() {
        let grant = PermissionGrant(
            service: .microphone,
            app: AppIdentity(bundleID: "com.example.demo", displayName: "Demo"),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: "com.target.app"
        )
        let key = DiffEntryKey.key(for: .granted(grant))
        #expect(key == "tcc-granted|microphone|com.example.demo|com.target.app")
    }

    @Test func btmKindsProduceDistinctKeysForSameIdentifier() {
        let item = BTMItem(
            identifier: "abc-123",
            name: "Item",
            type: .app,
            disposition: .enabled,
            scope: .user,
            modificationDate: Date(timeIntervalSince1970: 0)
        )
        let after = BTMItem(
            identifier: "abc-123",
            name: "Item",
            type: .app,
            disposition: .disabled,
            scope: .user,
            modificationDate: Date(timeIntervalSince1970: 1)
        )
        let added = DiffEntryKey.key(for: .btmAdded(item))
        let removed = DiffEntryKey.key(for: .btmRemoved(item))
        let flipped = DiffEntryKey.key(for: .btmDispositionFlipped(
            DomainChange(before: item, after: after)
        ))
        #expect(Set([added, removed, flipped]).count == 3)
    }

    @Test func launchAgentFlipKeyDistinctFromAddedAndRemoved() {
        let agent = LaunchAgentItem(
            label: "com.example.demo",
            sourceDirectory: .userLaunchAgents,
            programPath: "/usr/bin/demo",
            programArguments: [],
            runAtLoad: false,
            keepAlive: false
        )
        let after = LaunchAgentItem(
            label: "com.example.demo",
            sourceDirectory: .userLaunchAgents,
            programPath: "/usr/bin/demo",
            programArguments: [],
            runAtLoad: true,
            keepAlive: false
        )
        let added = DiffEntryKey.key(for: .launchAgentAdded(agent))
        let removed = DiffEntryKey.key(for: .launchAgentRemoved(agent))
        let flipped = DiffEntryKey.key(for: .launchAgentFlipped(
            DomainChange(before: agent, after: after)
        ))
        #expect(Set([added, removed, flipped]).count == 3)
    }

    @Test func keysAreStableAcrossSnapshotIDs() {
        // Same TCC grant data → same key regardless of which snapshot the
        // diff was computed against.
        let grant = PermissionGrant(
            service: .camera,
            app: AppIdentity(bundleID: "com.example.cam", displayName: "Cam"),
            lastModified: Date(timeIntervalSince1970: 0)
        )
        let k1 = DiffEntryKey.key(for: .granted(grant))
        let k2 = DiffEntryKey.key(for: .granted(grant))
        #expect(k1 == k2)
        // No snapshot identifier appears anywhere in the key.
        #expect(!k1.contains("snapshot"))
    }
}
