import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite struct DiffEntryKeyTests {
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
