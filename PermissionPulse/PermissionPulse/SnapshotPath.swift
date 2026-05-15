import Foundation

// Canonical on-disk path for the snapshot store. Creates the parent directory
// if missing. Caller hands the resulting path string to SnapshotStore.init —
// the store stays ignorant of applicationSupportDirectory.
enum SnapshotPath {
    static let directoryName = "com.wallymagill.permissionpulse"
    static let fileName = "snapshots.db"

    static func canonicalURL() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent(directoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName, isDirectory: false)
    }
}
