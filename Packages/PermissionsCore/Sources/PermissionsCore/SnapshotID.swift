import Foundation

public struct SnapshotID: Sendable, Hashable {
    public let rawValue: Int64

    public init(rawValue: Int64) {
        self.rawValue = rawValue
    }
}
