import Foundation

/// NSObject shim matching the private `ItemRecord` class encoded inside
/// `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`.
///
/// Decodes only the fields v0.4.0 surfaces in the UI. Unknown encoded keys are
/// ignored; missing required keys leave properties nil and the scanner drops the
/// row. The class is registered as "ItemRecord" with `NSKeyedUnarchiver` so the
/// archive's `$class` pointer resolves to this Swift type.
///
/// Marked `@unchecked Sendable` so the scanner (which runs `nonisolated`) can
/// hand instances back to its `async` caller before mapping them to `BTMItem`.
/// The shim has no concurrent access pattern — each instance is decoded, read
/// once, and dropped.
final class BTMItemRecordShim: NSObject, NSCoding, @unchecked Sendable {
    var identifier: String?
    var name: String?
    var developerName: String?
    var bundleIdentifier: String?
    var teamIdentifier: String?
    var container: String?
    var type: Int = 0
    var disposition: Int = 0
    var modificationDate: Double = 0

    override init() {
        super.init()
    }

    init(
        identifier: String,
        name: String,
        developerName: String? = nil,
        bundleIdentifier: String? = nil,
        teamIdentifier: String? = nil,
        container: String? = nil,
        type: Int,
        disposition: Int,
        modificationDate: Double
    ) {
        self.identifier = identifier
        self.name = name
        self.developerName = developerName
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.container = container
        self.type = type
        self.disposition = disposition
        self.modificationDate = modificationDate
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init()
        self.identifier = coder.decodeObject(forKey: "identifier") as? String
        self.name = coder.decodeObject(forKey: "name") as? String
        self.developerName = coder.decodeObject(forKey: "developerName") as? String
        self.bundleIdentifier = coder.decodeObject(forKey: "bundleIdentifier") as? String
        self.teamIdentifier = coder.decodeObject(forKey: "teamIdentifier") as? String
        self.container = coder.decodeObject(forKey: "container") as? String
        self.type = Int(coder.decodeInt64(forKey: "type"))
        self.disposition = Int(coder.decodeInt64(forKey: "disposition"))
        self.modificationDate = coder.decodeDouble(forKey: "modificationDate")
    }

    func encode(with coder: NSCoder) {
        coder.encode(identifier, forKey: "identifier")
        coder.encode(name, forKey: "name")
        coder.encode(developerName, forKey: "developerName")
        coder.encode(bundleIdentifier, forKey: "bundleIdentifier")
        coder.encode(teamIdentifier, forKey: "teamIdentifier")
        coder.encode(container, forKey: "container")
        coder.encode(Int64(type), forKey: "type")
        coder.encode(Int64(disposition), forKey: "disposition")
        coder.encode(modificationDate, forKey: "modificationDate")
    }
}
