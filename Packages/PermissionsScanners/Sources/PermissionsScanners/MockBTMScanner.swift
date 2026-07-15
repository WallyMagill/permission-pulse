import Foundation
import PermissionsCore

public struct MockBTMScanner: BTMScanner {
    private let warnings: [ScannerWarning]

    public init(warnings: [ScannerWarning] = []) {
        self.warnings = warnings
    }

    public func scan() async throws -> ScannerOutput<BTMItem> {
        let now = Date()
        let items = [
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
        return ScannerOutput(items: items, warnings: warnings)
    }
}
