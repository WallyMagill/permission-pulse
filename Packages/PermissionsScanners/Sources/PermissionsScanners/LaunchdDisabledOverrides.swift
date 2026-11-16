import Foundation
import PermissionsCore

/// launchd's own enabled/disabled state, which `launchctl disable`/`enable`
/// and System Settings → Login Items write. It overrides a plist's `Disabled`
/// key. Both files are world-readable `label → Bool` dictionaries; a missing
/// or unreadable file means "no overrides", never an error.
struct LaunchdDisabledOverrides: Sendable {
    static let defaultDirectory = URL(
        fileURLWithPath: "/private/var/db/com.apple.xpc.launchd",
        isDirectory: true
    )

    let system: [String: Bool]
    let user: [String: Bool]

    static let none = LaunchdDisabledOverrides(system: [:], user: [:])

    static func load(from directory: URL?, userID: uid_t) -> LaunchdDisabledOverrides {
        guard let directory else { return .none }
        return LaunchdDisabledOverrides(
            system: readFile(directory.appendingPathComponent("disabled.plist")),
            user: readFile(directory.appendingPathComponent("disabled.\(userID).plist"))
        )
    }

    /// `/Library/LaunchDaemons` jobs live in launchd's system domain; both
    /// LaunchAgents directories load into the user's GUI domain.
    func isDisabled(
        label: String,
        category: LaunchAgentItem.SourceDirectory,
        plistDisabled: Bool
    ) -> Bool {
        let table = category == .libraryLaunchDaemons ? system : user
        return table[label] ?? plistDisabled
    }

    private static func readFile(_ url: URL) -> [String: Bool] {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else {
            return [:]
        }
        return dictionary.compactMapValues { $0 as? Bool }
    }
}
