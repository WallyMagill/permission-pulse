import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite("InspectorContentResolver")
struct InspectorContentResolverTests {
    private func grant(_ bundleID: String, _ service: PermissionService) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: nil),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil,
            authValue: 2
        )
    }

    private var agent: LaunchAgentItem {
        LaunchAgentItem(
            label: "com.test.agent", sourceDirectory: .userLaunchAgents,
            programPath: "/usr/bin/true", programArguments: [],
            runAtLoad: true, keepAlive: false, isDisabled: false
        )
    }

    private var btm: BTMItem {
        BTMItem(
            identifier: "btm-1", name: "Test Item", developerName: nil,
            bundleIdentifier: "com.test.item", teamIdentifier: nil,
            type: .app, disposition: .enabled, dispositionRaw: 2,
            scope: .user, modificationDate: Date(timeIntervalSince1970: 0),
            parentIdentifier: nil
        )
    }

    @Test("Resolves an app selection to its full grant group")
    func resolvesAppGroup() {
        let grants = [grant("com.a", .camera), grant("com.a", .microphone), grant("com.b", .camera)]
        let content = InspectorContentResolver.resolve(
            .app(appKey: "com.a"), grants: grants, launchAgents: [], btmItems: []
        )
        guard case .app(let app, let appGrants) = content else {
            Issue.record("Expected .app content"); return
        }
        #expect(app.bundleID == "com.a")
        #expect(appGrants.count == 2)
    }

    @Test("Resolves launch agent and background item by ID")
    func resolvesByID() {
        let la = InspectorContentResolver.resolve(
            .launchAgent(id: agent.id), grants: [], launchAgents: [agent], btmItems: []
        )
        #expect(la == .launchAgent(agent))
        let bg = InspectorContentResolver.resolve(
            .backgroundItem(id: "btm-1"), grants: [], launchAgents: [], btmItems: [btm]
        )
        #expect(bg == .backgroundItem(btm))
    }

    @Test("Returns nil for nil selection or items no longer present")
    func unresolvable() {
        #expect(InspectorContentResolver.resolve(nil, grants: [], launchAgents: [], btmItems: []) == nil)
        #expect(InspectorContentResolver.resolve(
            .app(appKey: "gone"), grants: [], launchAgents: [], btmItems: []
        ) == nil)
        #expect(InspectorContentResolver.resolve(
            .launchAgent(id: "gone"), grants: [], launchAgents: [agent], btmItems: []
        ) == nil)
    }

    @Test("Routes carry their pre-selection")
    func routeSelectionPayload() {
        #expect(AppRoute.permissions(selectAppKey: "com.a").inspectorSelection == .app(appKey: "com.a"))
        #expect(AppRoute.permissions(selectAppKey: nil).inspectorSelection == nil)
        #expect(AppRoute.launchAgents(selectID: "x").inspectorSelection == .launchAgent(id: "x"))
        #expect(AppRoute.backgroundItems(selectID: "y").inspectorSelection == .backgroundItem(id: "y"))
        #expect(AppRoute.recentChanges.inspectorSelection == nil)
    }
}
