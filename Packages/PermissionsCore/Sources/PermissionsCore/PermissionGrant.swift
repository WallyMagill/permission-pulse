import Foundation

public struct PermissionGrant: Sendable, Hashable, Identifiable {
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

    // Mirror of the diff identity key: (service, bundleID, automationTarget).
    // Used by SwiftUI sheet(item:) bindings and other identity-keyed lookups.
    public var id: String {
        "\(service.rawValue)|\(app.bundleID)|\(automationTarget ?? "")"
    }
}
