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
    // launchd; surfaced in the detail view so it isn't mistaken for active.
    // NOT persisted in snapshots this slice (live-display only): the store reads
    // it back as `false`. It participates in Hashable/Equatable, so do NOT compare
    // a live-scan item against a store-read item by value — diffs run store-vs-
    // store (both false), so there's no diff noise today. (D4)
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
