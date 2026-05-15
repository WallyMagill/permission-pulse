import Foundation

public struct StaleApp: Sendable, Hashable {
    public enum DateSource: Sendable, Hashable {
        case spotlight
        case fileSystem
    }

    public let app: AppIdentity
    public let lastUsedDate: Date
    public let dateSource: DateSource
    public let daysSinceUsed: Int
    public let grantedServices: [PermissionService]

    public init(
        app: AppIdentity,
        lastUsedDate: Date,
        dateSource: DateSource,
        daysSinceUsed: Int,
        grantedServices: [PermissionService]
    ) {
        self.app = app
        self.lastUsedDate = lastUsedDate
        self.dateSource = dateSource
        self.daysSinceUsed = daysSinceUsed
        self.grantedServices = grantedServices
    }
}
