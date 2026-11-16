import Foundation

public struct BTMItem: Sendable, Equatable, Hashable, Identifiable {
    public enum ItemType: Sendable, Hashable {
        case app
        case loginItem
        case agent
        case developerGroup
        case spotlightImporter
        case dockTilePlugin
        case quickLookExtension
        case backgroundTasks
        case legacyAgent
        case legacyDaemon
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

    // The same identifier is registered once per scope (system, root user,
    // each login user), so identity needs both.
    public var identityKey: String { "\(scope.key)|\(identifier)" }

    public var id: String { identityKey }
}

extension BTMItem.Scope {
    public var key: String {
        switch self {
        case .system: "system"
        case .user: "user"
        case .perUser(let uuid): "perUser:\(uuid)"
        }
    }
}

extension BTMItem.ItemType {
    // Raw `type` values from the BTM store, identified on macOS 26/27 by the
    // item paths each one registers.
    private static let known: [(raw: Int, type: Self, kind: String)] = [
        (0x2, .app, "app"),
        (0x4, .loginItem, "loginItem"),
        (0x8, .agent, "agent"),
        (0x20, .developerGroup, "developerGroup"),
        (0x40, .spotlightImporter, "spotlightImporter"),
        (0x80, .dockTilePlugin, "dockTilePlugin"),
        (0x800, .quickLookExtension, "quickLookExtension"),
        (0x2000, .backgroundTasks, "backgroundTasks"),
        (0x10008, .legacyAgent, "legacyAgent"),
        (0x10010, .legacyDaemon, "legacyDaemon"),
    ]

    public init(rawValue: Int) {
        self = Self.known.first { $0.raw == rawValue }?.type ?? .unknown(rawValue: rawValue)
    }

    public var rawValue: Int {
        if case .unknown(let raw) = self { return raw }
        return Self.known.first { $0.type == self }?.raw ?? 0
    }

    /// Stable, non-localized name used by the snapshot store and exports.
    public var kindName: String {
        Self.known.first { $0.type == self }?.kind ?? "unknown"
    }

    public init?(kindName: String) {
        guard let match = Self.known.first(where: { $0.kind == kindName }) else { return nil }
        self = match.type
    }
}
