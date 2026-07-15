import Foundation

public struct AppIdentity: Sendable, Hashable {
    public let bundleID: String
    public let displayName: String
    public let bundlePath: URL?

    public init(bundleID: String, displayName: String, bundlePath: URL? = nil) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.bundlePath = bundlePath
    }

    public var stableKey: String? {
        if !bundleID.isEmpty { return "bundle:\(bundleID)" }
        guard let bundlePath else { return nil }
        let path = bundlePath.standardizedFileURL.path(percentEncoded: false)
        return path.isEmpty ? nil : "path:\(path)"
    }
}
