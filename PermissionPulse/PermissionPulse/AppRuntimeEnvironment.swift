import Foundation

nonisolated struct AppRuntimeEnvironment: Sendable {
    let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    var isRunningTests: Bool {
        environment["PERMISSION_PULSE_TEST_MODE"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
    }
}
