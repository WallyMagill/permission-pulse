import Foundation

public struct PermissionGrant: Sendable, Hashable {
    public let service: PermissionService
    public let app: AppIdentity
    public let lastModified: Date

    public init(service: PermissionService, app: AppIdentity, lastModified: Date) {
        self.service = service
        self.app = app
        self.lastModified = lastModified
    }
}
