import AppKit
import Foundation

enum SystemSettingsLink {
    static let fullDiskAccessURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )!

    static func openFullDiskAccess() {
        NSWorkspace.shared.open(fullDiskAccessURL)
    }
}
