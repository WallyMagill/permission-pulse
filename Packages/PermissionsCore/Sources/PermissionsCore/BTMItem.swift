import Foundation

public struct BTMItem: Sendable, Equatable, Hashable, Identifiable {
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
    // Raw BTM disposition bitmask, captured losslessly for the snapshot. Excluded
    // from Equatable/Hashable so a sub-bit change (e.g. policy-block vs user
    // toggle) does not surface as a confusing "Disabled -> Disabled" diff; the
    // friendly `disposition` enum drives display. Representing raw changes is a
    // future slice. (D3)
    public let dispositionRaw: Int
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
        dispositionRaw: Int? = nil,
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
        // If no raw value was supplied, fall back to the associated value of the
        // .unknown case (which is itself the raw bitmask), then to 0.
        if let provided = dispositionRaw {
            self.dispositionRaw = provided
        } else if case .unknown(let r) = disposition {
            self.dispositionRaw = r
        } else {
            // .enabled / .disabled carry no raw in the enum; the live scanner always
            // supplies dispositionRaw explicitly, so 0 here is a safe fallback used
            // only by test/convenience construction. (D3)
            self.dispositionRaw = 0
        }
        self.scope = scope
        self.modificationDate = modificationDate
        self.parentIdentifier = parentIdentifier
    }

    // Hand-written Equatable/Hashable to EXCLUDE `dispositionRaw` (a sub-bit change
    // must not surface as a confusing "Disabled -> Disabled" diff; the friendly
    // `disposition` enum drives display).
    // Included (10): identifier, name, developerName, bundleIdentifier,
    //   teamIdentifier, type, disposition, scope, modificationDate, parentIdentifier.
    // Excluded (1):  dispositionRaw.
    // IMPORTANT: if you add a stored property to BTMItem, add it to BOTH == and
    // hash(into:) (and to BTMItemEqualityTests). Synthesized conformance would
    // have caught the omission; hand-written conformance will not. (D3)
    public static func == (lhs: BTMItem, rhs: BTMItem) -> Bool {
        lhs.identifier == rhs.identifier
            && lhs.name == rhs.name
            && lhs.developerName == rhs.developerName
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.teamIdentifier == rhs.teamIdentifier
            && lhs.type == rhs.type
            && lhs.disposition == rhs.disposition
            && lhs.scope == rhs.scope
            && lhs.modificationDate == rhs.modificationDate
            && lhs.parentIdentifier == rhs.parentIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(name)
        hasher.combine(developerName)
        hasher.combine(bundleIdentifier)
        hasher.combine(teamIdentifier)
        hasher.combine(type)
        hasher.combine(disposition)
        hasher.combine(scope)
        hasher.combine(modificationDate)
        hasher.combine(parentIdentifier)
    }

    // BTM's natural primary key. Used by SwiftUI sheet(item:) bindings.
    public var id: String { identifier }
}
