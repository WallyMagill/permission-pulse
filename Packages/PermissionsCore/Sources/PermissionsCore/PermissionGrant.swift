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

    // Canonical app key. Path-only grants (TCC client_type == 1) carry an empty
    // bundleID, so fall back to the bundle path to keep two distinct path-based
    // clients from collapsing into one identity. The final `displayName` fallback
    // is a defensive last resort only: real TCC grants always carry either a
    // bundleID (client_type 0) or a bundlePath (client_type 1), so it is not a
    // reachable identity anchor for live data. (D1)
    public var appKey: String {
        if !app.bundleID.isEmpty { return app.bundleID }
        return app.bundlePath?.path(percentEncoded: false) ?? app.displayName
    }

    // Single source of truth for TCC grant identity — used by the scanner's
    // dedupe, the store's diff engine, the dismiss-key mapper, and SwiftUI
    // sheet(item:) bindings. (D1)
    public var identityKey: String {
        "\(service.rawValue)|\(appKey)|\(automationTarget ?? "")"
    }

    public var id: String { identityKey }
}
