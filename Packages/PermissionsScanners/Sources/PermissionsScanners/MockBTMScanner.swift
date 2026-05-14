import Foundation
import PermissionsCore

public struct MockBTMScanner: BTMScanner {
    public init() {}

    public func scan() async throws -> [BTMItem] {
        let now = Date()
        return [
            BTMItem(
                identifier: "2.us.zoom.xos",
                name: "zoom.us",
                developerName: nil,
                bundleIdentifier: "us.zoom.xos",
                teamIdentifier: "BJ4HAAB9B3",
                type: .app,
                disposition: .enabled,
                scope: .user,
                modificationDate: now.addingTimeInterval(-86_400 * 5)
            ),
            BTMItem(
                identifier: "16.com.docker.vmnetd",
                name: "com.docker.vmnetd",
                developerName: "Docker",
                bundleIdentifier: nil,
                teamIdentifier: "9BNSXJN65R",
                type: .legacyDaemon,
                disposition: .enabled,
                scope: .system,
                modificationDate: now.addingTimeInterval(-86_400 * 12),
                parentIdentifier: "Docker"
            ),
            BTMItem(
                identifier: "2.com.example.disabled",
                name: "Example Disabled App",
                developerName: "Example Co.",
                bundleIdentifier: "com.example.disabled",
                teamIdentifier: "EXAMPLE01",
                type: .app,
                disposition: .disabled,
                scope: .user,
                modificationDate: now.addingTimeInterval(-86_400 * 30)
            ),
        ]
    }
}
