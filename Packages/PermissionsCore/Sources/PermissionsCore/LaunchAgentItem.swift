import Foundation

public struct LaunchAgentItem: Sendable, Hashable, Identifiable {
    public enum SourceDirectory: String, Sendable, CaseIterable {
        case userLaunchAgents
        case libraryLaunchAgents
        case libraryLaunchDaemons

        public var path: String {
            switch self {
            case .userLaunchAgents:     "~/Library/LaunchAgents/"
            case .libraryLaunchAgents:  "/Library/LaunchAgents/"
            case .libraryLaunchDaemons: "/Library/LaunchDaemons/"
            }
        }
    }

    public let label: String
    public let sourceDirectory: SourceDirectory
    public let programPath: String?
    public let programArguments: [String]
    public let runAtLoad: Bool
    public let keepAlive: Bool
    // launchd `Disabled` key. A disabled agent is registered but NOT loaded by
    // launchd; persisted in schema-v5 snapshots and surfaced in the detail view
    // so it isn't mistaken for active. Legacy snapshots did not capture this
    // field, so store diffing compares it only between two v5 snapshots.
    public let isDisabled: Bool

    public init(
        label: String,
        sourceDirectory: SourceDirectory,
        programPath: String?,
        programArguments: [String],
        runAtLoad: Bool,
        keepAlive: Bool,
        isDisabled: Bool = false
    ) {
        self.label = label
        self.sourceDirectory = sourceDirectory
        self.programPath = programPath
        self.programArguments = programArguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.isDisabled = isDisabled
    }

    // Mirror of the diff identity key. Used by SwiftUI sheet(item:) bindings.
    public var id: String { "\(sourceDirectory.rawValue)|\(label)" }
}
