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
        let fileURL = try locateLatestBTMFile()
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

        let entries = try Self.unarchiveEntries(data: data, fileName: fileURL.lastPathComponent)
        let items = entries
            .compactMap(Self.mapEntryToItem)
            .filter { $0.type != .developerGroup }
            .sorted(by: Self.sortItems)
        return ScannerOutput(items: items)
    }

    private func locateLatestBTMFile() throws -> URL {
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

        let candidates = contents.compactMap { url -> (URL, Int)? in
            guard let version = Self.parseVersionSuffix(url.lastPathComponent) else { return nil }
            return (url, version)
        }

        guard let latest = candidates.max(by: { $0.1 < $1.1 }) else {
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "No BackgroundItems-v*.btm file found in \(directoryURL.path)."
                )
            )
        }
        return latest.0
    }

    static func parseVersionSuffix(_ name: String) -> Int? {
        guard name.hasPrefix(fileNamePrefix), name.hasSuffix(fileNameSuffix) else { return nil }
        let start = name.index(name.startIndex, offsetBy: fileNamePrefix.count)
        let end = name.index(name.endIndex, offsetBy: -fileNameSuffix.count)
        return Int(name[start..<end])
    }

    private static func unarchiveEntries(
        data: Data,
        fileName: String
    ) throws -> [(shim: BTMItemRecordShim, userUUID: String)] {
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
        unarchiver.setClass(BTMItemRecordShim.self, forClassName: itemRecordClassName)

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

        var collected: [(BTMItemRecordShim, String)] = []
        for (key, value) in items {
            guard let userUUID = key as? String else { continue }
            guard let bucket = value as? [BTMItemRecordShim] else { continue }
            for shim in bucket {
                collected.append((shim, userUUID))
            }
        }
        return collected
    }

    private static func mapEntryToItem(
        _ entry: (shim: BTMItemRecordShim, userUUID: String)
    ) -> BTMItem? {
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
            type: mapType(entry.shim.type),
            disposition: mapDisposition(entry.shim.disposition),
            dispositionRaw: entry.shim.disposition,
            scope: mapScope(userUUID: entry.userUUID),
            modificationDate: Date(timeIntervalSinceReferenceDate: entry.shim.modificationDate),
            parentIdentifier: entry.shim.container
        )
    }

    static func mapType(_ raw: Int) -> BTMItem.ItemType {
        switch raw {
        case 0x2: .app
        case 0x10010: .legacyDaemon
        case 0x20: .developerGroup
        default: .unknown(rawValue: raw)
        }
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
