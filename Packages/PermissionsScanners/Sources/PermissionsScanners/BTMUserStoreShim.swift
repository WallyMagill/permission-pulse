import Foundation

/// NSObject shim matching the private `BTMUserStore` class. From store
/// version 18 (macOS 27) Background Task Management keeps one archive per
/// user, `BackgroundItems-v18-<user UUID>.btm`, whose `$top` exposes this
/// object under `"userStore"`. The unsuffixed `BackgroundItems-v18.btm` is
/// only an index of users and holds no items.
///
/// Only the fields the scanner consumes are read. Unknown encoded keys are
/// ignored.
final class BTMUserStoreShim: NSObject, NSCoding, @unchecked Sendable {
    var userIdentifier: String?
    var records: NSArray?

    init(userIdentifier: String?, records: NSArray?) {
        self.userIdentifier = userIdentifier
        self.records = records
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init()
        self.userIdentifier = coder.decodeObject(forKey: "userIdentifier") as? String
        self.records = coder.decodeObject(forKey: "records") as? NSArray
    }

    func encode(with coder: NSCoder) {
        coder.encode(userIdentifier, forKey: "userIdentifier")
        coder.encode(records, forKey: "records")
    }
}
