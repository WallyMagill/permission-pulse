import Foundation

public struct PermissionGrant: Sendable, Hashable {
    public let service: PermissionService
    public let app: AppIdentity
    public let lastModified: Date
    public let automationTarget: String?

    public init(
        service: PermissionService,
        app: AppIdentity,
        lastModified: Date,
        automationTarget: String? = nil
    ) {
        self.service = service
        self.app = app
        self.lastModified = lastModified
        self.automationTarget = automationTarget
    }
}
