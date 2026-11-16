import Foundation
import OSLog
import PermissionsCore

public struct BTMScannerDirect: BTMScanner, Sendable {
    static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "scanners.btm"
    )

    static let topLevelStoreKey = "store"
    static let storageClassName = "Storage"
    static let topLevelUserStoreKey = "userStore"
    static let userStoreClassName = "BTMUserStore"
    static let indexUsersKey = "infoByUserIdentifier"
    static let itemRecordClassName = "ItemRecord"
    static let rootUserUUIDSentinel = "FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE"
    static let systemUserUUIDSentinel = "FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000"

    private static let defaultDirectoryURL = URL(
        fileURLWithPath: "/private/var/db/com.apple.backgroundtaskmanagement",
        isDirectory: true
    )

    private static let fileNamePrefix = "BackgroundItems-v"
    private static let fileNameSuffix = ".btm"

    private let directoryURL: URL

    public init() {
        self.directoryURL = Self.defaultDirectoryURL
    }

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func scan() async throws -> ScannerOutput<BTMItem> {
        var entries: [Entry] = []
        for fileURL in try locateLatestBTMFiles() {
            entries.append(contentsOf: try Self.unarchiveEntries(
                data: try readFile(at: fileURL),
                fileName: fileURL.lastPathComponent
            ))
        }
        let items = entries
            .compactMap(Self.mapEntryToItem)
            .filter { $0.type != .developerGroup }
            .sorted(by: Self.sortItems)
        return ScannerOutput(items: items)
    }

    private typealias Entry = (shim: BTMItemRecordShim, userUUID: String)

    private func readFile(at fileURL: URL) throws -> Data {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Self.logger.error("BTM read failed: \(error.localizedDescription, privacy: .public)")
            throw ScannerError.permissionDenied(reason: Self.permissionDeniedReason)
        }
        guard !data.isEmpty else {
            throw ScannerError.schemaMismatch(
                detail: String(localized: "Empty .btm file at \(fileURL.lastPathComponent).")
            )
        }
        return data
    }

    /// The files holding the newest store version. Through v16 that is one
    /// `BackgroundItems-v<N>.btm`. From v18 (macOS 27) the items live in
    /// per-user `BackgroundItems-v<N>-<user UUID>.btm` files and the
    /// unsuffixed file is an index with no items, so the per-user files win
    /// whenever the newest version has any.
    private func locateLatestBTMFiles() throws -> [URL] {
        let fm = FileManager.default
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
        } catch {
            Self.logger.error("BTM directory unreadable: \(error.localizedDescription, privacy: .public)")
            throw ScannerError.permissionDenied(reason: Self.permissionDeniedReason)
        }

        let candidates = contents.compactMap { url -> (url: URL, name: ParsedFileName)? in
            guard let name = Self.parseFileName(url.lastPathComponent) else { return nil }
            return (url, name)
        }

        guard let latestVersion = candidates.map(\.name.version).max() else {
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "No BackgroundItems-v*.btm file found in \(directoryURL.path)."
                )
            )
        }
        let latest = candidates.filter { $0.name.version == latestVersion }
        let perUser = latest.filter { $0.name.userUUID != nil }
        guard !perUser.isEmpty else { return latest.map(\.url) }
        if let index = latest.first(where: { $0.name.userUUID == nil }) {
            try requireFileForEveryIndexedUser(
                indexURL: index.url,
                presentUsers: Set(perUser.compactMap(\.name.userUUID))
            )
        }
        return perUser.map(\.url).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The index lists every user that has a store. A listed user with no
    /// file would silently drop that user's items, which a later diff would
    /// read as removals, so the scan fails instead.
    private func requireFileForEveryIndexedUser(indexURL: URL, presentUsers: Set<String>) throws {
        let unarchiver: NSKeyedUnarchiver
        do {
            unarchiver = try NSKeyedUnarchiver(forReadingFrom: try readFile(at: indexURL))
        } catch let error as ScannerError {
            throw error
        } catch {
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "Unable to unarchive \(indexURL.lastPathComponent): \(error.localizedDescription)"
                )
            )
        }
        unarchiver.requiresSecureCoding = false
        guard let info = unarchiver.decodeObject(forKey: Self.indexUsersKey) as? NSDictionary else {
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "\(indexURL.lastPathComponent) has no '\(Self.indexUsersKey)' dictionary."
                )
            )
        }
        let missing = Set(info.allKeys.compactMap { $0 as? String }).subtracting(presentUsers)
        guard missing.isEmpty else {
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "\(indexURL.lastPathComponent) lists \(info.count) users but \(missing.count) of them have no per-user file."
                )
            )
        }
    }

    struct ParsedFileName: Equatable {
        var version: Int
        var userUUID: String?
    }

    /// `BackgroundItems-v16.btm` → version 16; `BackgroundItems-v18-<UUID>.btm`
    /// → version 18 for that user.
    static func parseFileName(_ name: String) -> ParsedFileName? {
        guard name.hasPrefix(fileNamePrefix), name.hasSuffix(fileNameSuffix) else { return nil }
        let start = name.index(name.startIndex, offsetBy: fileNamePrefix.count)
        let end = name.index(name.endIndex, offsetBy: -fileNameSuffix.count)
        let parts = name[start..<end].split(separator: "-", maxSplits: 1)
        guard let first = parts.first, let version = Int(first) else { return nil }
        guard parts.count == 2 else { return ParsedFileName(version: version, userUUID: nil) }
        guard UUID(uuidString: String(parts[1])) != nil else { return nil }
        return ParsedFileName(version: version, userUUID: String(parts[1]))
    }

    private static func unarchiveEntries(data: Data, fileName: String) throws -> [Entry] {
        let unarchiver: NSKeyedUnarchiver
        do {
            unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        } catch {
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "Unable to unarchive \(fileName): \(error.localizedDescription)"
                )
            )
        }
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(BTMStorageShim.self, forClassName: storageClassName)
        unarchiver.setClass(BTMUserStoreShim.self, forClassName: userStoreClassName)
        unarchiver.setClass(BTMItemRecordShim.self, forClassName: itemRecordClassName)

        if unarchiver.containsValue(forKey: topLevelUserStoreKey) {
            return try userStoreEntries(from: unarchiver, fileName: fileName)
        }
        return try storageEntries(from: unarchiver, fileName: fileName)
    }

    private static func userStoreEntries(
        from unarchiver: NSKeyedUnarchiver,
        fileName: String
    ) throws -> [Entry] {
        guard let store = unarchiver.decodeObject(forKey: topLevelUserStoreKey) as? BTMUserStoreShim,
              let userUUID = store.userIdentifier ?? parseFileName(fileName)?.userUUID,
              let records = store.records as? [BTMItemRecordShim] else {
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "\(fileName) has no readable '\(topLevelUserStoreKey)' object of class '\(userStoreClassName)' with a 'records' list."
                )
            )
        }
        return records.map { ($0, userUUID) }
    }

    private static func storageEntries(
        from unarchiver: NSKeyedUnarchiver,
        fileName: String
    ) throws -> [Entry] {
        guard let storage = unarchiver.decodeObject(forKey: topLevelStoreKey) as? BTMStorageShim else {
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "\(fileName) is missing the '\(topLevelStoreKey)' object, or its class is not '\(storageClassName)'."
                )
            )
        }

        guard let items = storage.itemsByUserIdentifier else {
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "\(fileName) Storage object has no 'itemsByUserIdentifier' field."
                )
            )
        }

        var collected: [Entry] = []
        for (key, value) in items {
            guard let userUUID = key as? String else { continue }
            guard let bucket = value as? [BTMItemRecordShim] else { continue }
            for shim in bucket {
                collected.append((shim, userUUID))
            }
        }
        return collected
    }

    private static func mapEntryToItem(_ entry: Entry) -> BTMItem? {
        guard let identifier = entry.shim.identifier, !identifier.isEmpty,
              let name = entry.shim.name, !name.isEmpty else {
            logger.debug("BTM row dropped — missing identifier or name")
            return nil
        }
        return BTMItem(
            identifier: identifier,
            name: name,
            developerName: entry.shim.developerName,
            bundleIdentifier: entry.shim.bundleIdentifier,
            teamIdentifier: entry.shim.teamIdentifier,
            type: BTMItem.ItemType(rawValue: entry.shim.type),
            disposition: mapDisposition(entry.shim.disposition),
            dispositionRaw: entry.shim.disposition,
            scope: mapScope(userUUID: entry.userUUID),
            modificationDate: Date(timeIntervalSinceReferenceDate: entry.shim.modificationDate),
            parentIdentifier: entry.shim.container
        )
    }

    static func mapDisposition(_ raw: Int) -> BTMItem.Disposition {
        if raw & 1 != 0 { return .enabled }
        return .disabled
    }

    static func mapScope(userUUID: String) -> BTMItem.Scope {
        switch userUUID {
        case rootUserUUIDSentinel: .user
        case systemUserUUIDSentinel: .system
        default: .perUser(uuid: userUUID)
        }
    }

    private static func sortItems(_ a: BTMItem, _ b: BTMItem) -> Bool {
        if scopeOrder(a.scope) != scopeOrder(b.scope) {
            return scopeOrder(a.scope) < scopeOrder(b.scope)
        }
        let aSort = a.developerName ?? a.name
        let bSort = b.developerName ?? b.name
        if aSort != bSort {
            return aSort < bSort
        }
        return a.name < b.name
    }

    private static func scopeOrder(_ scope: BTMItem.Scope) -> Int {
        switch scope {
        case .system: 0
        case .user: 1
        case .perUser: 2
        }
    }

    private static let permissionDeniedReason = String(
        localized: "Full Disk Access is required to read the Background Task Management database. Grant it in System Settings → Privacy & Security → Full Disk Access."
    )
}
