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
    // launchd's disabled-override database entry for this label, else the
    // plist's `Disabled` key. A disabled agent is registered but NOT loaded by
    // launchd; persisted in schema-v5 snapshots and surfaced in the detail view
    // so it isn't mistaken for active. Legacy snapshots did not capture this
    // field, so store diffing compares it only between two v5 snapshots.
    public let isDisabled: Bool
    // False when the plist exists but could not be read or parsed (e.g. a
    // root-only 0700 daemon plist). The label is then the file name, and the
    // program/argument/flag fields carry no evidence.
    public let detailsReadable: Bool
    // Name of the plist on disk. Not part of identity or diff equivalence:
    // snapshots before schema v7 did not record it.
    public let fileName: String?

    public init(
        label: String,
        sourceDirectory: SourceDirectory,
        programPath: String?,
        programArguments: [String],
        runAtLoad: Bool,
        keepAlive: Bool,
        isDisabled: Bool = false,
        detailsReadable: Bool = true,
        fileName: String? = nil
    ) {
        self.label = label
        self.sourceDirectory = sourceDirectory
        self.programPath = programPath
        self.programArguments = programArguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.isDisabled = isDisabled
        self.detailsReadable = detailsReadable
        self.fileName = fileName
    }

    /// The executable launchd would start: `Program`, else `ProgramArguments[0]`.
    public var effectiveProgram: String? {
        programPath ?? programArguments.first
    }

    // Mirror of the diff identity key. Used by SwiftUI sheet(item:) bindings.
    public var id: String { "\(sourceDirectory.rawValue)|\(label)" }
}
