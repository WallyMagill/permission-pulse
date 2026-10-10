import Foundation
import PermissionsCore

enum StoreFixtures {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)

    static func grant(_ bundleID: String, service: PermissionService = .camera) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: nil),
            lastModified: date,
            automationTarget: nil
        )
    }

    static func agent(_ label: String) -> LaunchAgentItem {
        LaunchAgentItem(
            label: label,
            sourceDirectory: .userLaunchAgents,
            programPath: "/usr/local/bin/\(label)",
            programArguments: [],
            runAtLoad: true,
            keepAlive: false,
            isDisabled: false
        )
    }

    static func btm(_ identifier: String) -> BTMItem {
        BTMItem(
            identifier: identifier,
            name: "Item-\(identifier)",
            developerName: nil,
            bundleIdentifier: "com.example.\(identifier)",
            teamIdentifier: nil,
            type: .app,
            disposition: .enabled,
            scope: .system,
            modificationDate: date,
            parentIdentifier: nil
        )
    }

    static func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("permission-pulse-\(UUID().uuidString).sqlite")
    }
}
