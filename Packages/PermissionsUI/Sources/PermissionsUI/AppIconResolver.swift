import AppKit
import SwiftUI
import PermissionsCore

// Resolves a SwiftUI Image for an AppIdentity, trying multiple fallback paths
// so we don't show the `app.dashed` placeholder when the real app is actually
// installed.
//
// The TCC scanner does not always populate `AppIdentity.bundlePath` (TCC.db
// stores client_type=0 bundleID-only rows without a path). LaunchServices
// can resolve bundleID → URL for any installed app, which is what we want.
enum AppIconResolver {
    @ViewBuilder
    static func iconView(for app: AppIdentity, size: CGFloat) -> some View {
        if let nsImage = resolveIcon(for: app) {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.78))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    static func resolveIcon(for app: AppIdentity) -> NSImage? {
        // 1. Use bundlePath if the scanner provided one AND the file exists.
        if let path = app.bundlePath {
            let fsPath = path.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: fsPath) {
                return NSWorkspace.shared.icon(forFile: fsPath)
            }
        }
        // 2. Ask LaunchServices for the installed app by bundle ID.
        if !app.bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        }
        // 3. Give up — caller renders the dashed placeholder.
        return nil
    }
}
