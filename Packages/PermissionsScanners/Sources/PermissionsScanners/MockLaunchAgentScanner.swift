import Foundation
import PermissionsCore

public struct MockLaunchAgentScanner: LaunchAgentScanner {
    private let warnings: [ScannerWarning]

    public init(warnings: [ScannerWarning] = []) {
        self.warnings = warnings
    }

    public func scan() async throws -> ScannerOutput<LaunchAgentItem> {
        let items = [
            LaunchAgentItem(
                label: "com.example.demo.helper",
                sourceDirectory: .userLaunchAgents,
                programPath: "/Applications/DemoApp.app/Contents/MacOS/DemoHelper",
                programArguments: [],
                runAtLoad: true,
                keepAlive: false
            ),
            LaunchAgentItem(
                label: "com.example.tinybackup",
                sourceDirectory: .libraryLaunchAgents,
                programPath: "/usr/local/bin/tinybackup",
                programArguments: ["--daily"],
                runAtLoad: true,
                keepAlive: true
            ),
        ]
        return ScannerOutput(items: items, warnings: warnings)
    }
}
