import Foundation

public struct DomainChange<T: Sendable & Hashable>: Sendable, Hashable {
    public let before: T
    public let after: T

    public init(before: T, after: T) {
        self.before = before
        self.after = after
    }
}
