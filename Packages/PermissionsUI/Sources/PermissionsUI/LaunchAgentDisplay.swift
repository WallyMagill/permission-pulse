import Darwin
import Foundation
import PermissionsCore

extension LaunchAgentItem.SourceDirectory {
    /// Who the job runs for, in plain words. Suitable for compact row display.
    var scopeName: String {
        switch self {
        case .userLaunchAgents:     String(localized: "User")
        case .libraryLaunchAgents:  String(localized: "All users")
        case .libraryLaunchDaemons: String(localized: "System daemon")
        }
    }
}

enum LaunchAgentDisplay {
    static var unreadableValue: String { String(localized: "Unknown (file not readable)") }
    static var unreadableSummary: String { String(localized: "Details unreadable") }
    static var programNotFound: String {
        String(localized: "Program not found — likely left behind by an uninstalled app")
    }

    static func programFileName(_ item: LaunchAgentItem) -> String? {
        guard let program = item.effectiveProgram, !program.isEmpty else { return nil }
        return (program as NSString).lastPathComponent
    }

    /// Row subtitle: the program's file name and scope. Unreadable items say
    /// so instead of naming a program.
    static func secondaryLine(_ item: LaunchAgentItem) -> String {
        let scope = item.sourceDirectory.scopeName
        if !item.detailsReadable {
            return String(localized: "\(unreadableSummary) · \(scope)")
        }
        guard let program = programFileName(item) else { return scope }
        return String(localized: "\(program) · \(scope)")
    }

    static func filtered(_ items: [LaunchAgentItem], searchText: String) -> [LaunchAgentItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            searchFields(item).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private static func searchFields(_ item: LaunchAgentItem) -> [String] {
        [item.label, item.programPath, item.fileName].compactMap { $0 } + item.programArguments
    }

    /// The file Reveal in Finder should select: the recorded file name, else
    /// the conventional `<label>.plist`, else the directory itself.
    static func revealTarget(
        for item: LaunchAgentItem,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let expanded = (item.sourceDirectory.path as NSString).expandingTildeInPath
        let directory = URL(fileURLWithPath: expanded, isDirectory: true)
        let candidate = directory.appendingPathComponent(item.fileName ?? "\(item.label).plist")
        return fileExists(candidate.path(percentEncoded: false)) ? candidate : directory
    }
}

/// Decides whether an agent's program is certainly gone from disk. It only
/// answers yes when the absence is observable: the path is absolute, it does
/// not exist, and its nearest existing ancestor is a directory we can list.
/// Anything uncertain (permission walls, unmounted volumes) answers no.
struct MissingProgramCheck: Sendable {
    enum EntryState: Sendable { case present, absent, unknown }

    var entryState: @Sendable (String) -> EntryState
    var isDirectoryListable: @Sendable (String) -> Bool

    static let live = MissingProgramCheck(
        entryState: { path in
            var info = stat()
            if lstat(path, &info) == 0 { return .present }
            return errno == ENOENT ? .absent : .unknown
        },
        isDirectoryListable: { path in
            guard let directory = opendir(path) else { return false }
            closedir(directory)
            return true
        }
    )

    func isProgramMissing(_ item: LaunchAgentItem) -> Bool {
        guard item.detailsReadable,
              let program = item.effectiveProgram,
              program.hasPrefix("/"),
              entryState(program) == .absent else {
            return false
        }
        var ancestor = (program as NSString).deletingLastPathComponent
        while true {
            switch entryState(ancestor) {
            case .present:
                // A missing child of /Volumes is usually an unmounted disk.
                return ancestor != "/Volumes" && isDirectoryListable(ancestor)
            case .unknown:
                return false
            case .absent:
                guard ancestor != "/" else { return false }
                ancestor = (ancestor as NSString).deletingLastPathComponent
            }
        }
    }
}
