import Foundation

/// NSObject shim matching the private `Storage` class that wraps the BTM
/// archive's root. The archive's `$top` exposes the storage under the key
/// `"store"` alongside an integer `"version"`. We register this shim under
/// the on-disk Objective-C class name `"Storage"` so the archive's `$class`
/// pointer resolves to this Swift type.
///
/// Only the field v0.4.0 consumes is read here. Unknown encoded keys are
/// ignored.
final class BTMStorageShim: NSObject, NSCoding, @unchecked Sendable {
    var itemsByUserIdentifier: NSDictionary?

    override init() {
        super.init()
    }

    init(itemsByUserIdentifier: NSDictionary?) {
        self.itemsByUserIdentifier = itemsByUserIdentifier
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init()
        self.itemsByUserIdentifier = coder.decodeObject(forKey: "itemsByUserIdentifier") as? NSDictionary
    }

    func encode(with coder: NSCoder) {
        coder.encode(itemsByUserIdentifier, forKey: "itemsByUserIdentifier")
    }
}
