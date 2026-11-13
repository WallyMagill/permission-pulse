import AppKit // AppKit: NSWorkspace resolves bundle IDs through Launch Services (read-only).
import Darwin
import SwiftUI
import PermissionsCore

/// Whether the app behind a TCC grant is gone from this Mac. Display-time
/// only, and it answers "missing" only when sure: a bundle ID that neither
/// Launch Services nor any parent bundle ID resolves, or a client path the
/// file system reports as nonexistent.
@MainActor
enum AppPresence {
    static func isMissing(
        _ app: AppIdentity,
        appIsInstalled: @MainActor (String) -> Bool = installedApp,
        pathIsAbsent: @MainActor (URL) -> Bool = fileSystemReportsAbsent
    ) -> Bool {
        if !app.bundleID.isEmpty {
            guard app.bundlePath == nil else { return false }
            return !parentBundleIDs(of: app.bundleID).contains(where: appIsInstalled)
        }
        guard let path = app.bundlePath else { return false }
        return pathIsAbsent(path)
    }

    /// `com.nordvpn.macos.Shield` → `com.nordvpn.macos`, `com.nordvpn`.
    /// System extensions and helpers hold grants under IDs Launch Services
    /// does not index; their app's ID is a prefix of theirs.
    static func parentBundleIDs(of bundleID: String) -> [String] {
        let parts = bundleID.split(separator: ".")
        guard parts.count > 2 else { return [] }
        return (2..<parts.count).reversed().map { parts.prefix($0).joined(separator: ".") }
    }

    private static func installedApp(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Only ENOENT counts. A path that cannot be checked, such as one inside
    /// a folder Permission Pulse may not read, is not called missing.
    static func fileSystemReportsAbsent(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) != 0 else { return false }
        return errno == ENOENT
    }
}

/// Neutral badge for a grant whose app is no longer on this Mac.
struct AppNotFoundBadge: View {
    var body: some View {
        Text(String(localized: "App not found on this Mac"))
            .ppFont(.badge)
            .foregroundStyle(PPBadgeStyle.disabled.foreground)
            .padding(.horizontal, PPSpacing.xs)
            .padding(.vertical, PPSpacing.xxs)
            .background(PPBadgeStyle.disabled.background, in: .capsule)
            .lineLimit(1)
            .fixedSize()
    }
}
