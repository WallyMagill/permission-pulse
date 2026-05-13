import Foundation
import PermissionsCore

public struct MockLaunchAgentScanner: LaunchAgentScanner {
    public init() {}

    public func scan() async throws -> [LaunchAgentItem] {
        [
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
    }
}
