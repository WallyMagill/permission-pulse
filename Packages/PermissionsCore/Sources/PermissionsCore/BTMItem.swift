import Foundation

public struct BTMItem: Sendable, Hashable, Identifiable {
    public enum ItemType: Sendable, Hashable {
        case app
        case legacyDaemon
        case developerGroup
        case unknown(rawValue: Int)
    }

    public enum Disposition: Sendable, Hashable {
        case enabled
        case disabled
        case unknown(rawValue: Int)
    }

    public enum Scope: Sendable, Hashable {
        case system
        case user
        case perUser(uuid: String)
    }

    public let identifier: String
    public let name: String
    public let developerName: String?
    public let bundleIdentifier: String?
    public let teamIdentifier: String?
    public let type: ItemType
    public let disposition: Disposition
    public let scope: Scope
    public let modificationDate: Date
    public let parentIdentifier: String?

    public init(
        identifier: String,
        name: String,
        developerName: String? = nil,
        bundleIdentifier: String? = nil,
        teamIdentifier: String? = nil,
        type: ItemType,
        disposition: Disposition,
        scope: Scope,
        modificationDate: Date,
        parentIdentifier: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.developerName = developerName
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.type = type
        self.disposition = disposition
        self.scope = scope
        self.modificationDate = modificationDate
        self.parentIdentifier = parentIdentifier
    }

    // BTM's natural primary key. Used by SwiftUI sheet(item:) bindings.
    public var id: String { identifier }
}
