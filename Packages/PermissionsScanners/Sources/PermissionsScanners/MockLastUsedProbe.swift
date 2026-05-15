import Foundation
import PermissionsCore

public struct MockLastUsedProbe: LastUsedProbe, Sendable {
    public let fixed: [URL: (date: Date, source: StaleApp.DateSource)]

    public init(fixed: [URL: (date: Date, source: StaleApp.DateSource)] = [:]) {
        self.fixed = fixed
    }

    public func lastUsedDate(
        for bundlePath: URL
    ) async -> (date: Date, source: StaleApp.DateSource)? {
        fixed[bundlePath]
    }
}
