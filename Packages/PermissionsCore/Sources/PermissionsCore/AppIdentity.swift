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
}
