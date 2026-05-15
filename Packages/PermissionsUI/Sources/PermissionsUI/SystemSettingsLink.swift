import AppKit
import Foundation
import PermissionsCore

// Deep links into System Settings → Privacy & Security panes.
//
// The URL format is `x-apple.systempreferences:com.apple.preference.security?<anchor>`.
// Anchor names are best-effort — Apple does not document them officially and
// they have drifted across macOS versions. The mapping below was verified on
// macOS Tahoe (26). If an anchor is no longer recognized, System Settings
// opens to the top-level Privacy pane instead of failing — acceptable
// graceful degradation. Callers can also use `openPrivacyPane()` directly
// for the top-level pane.
enum SystemSettingsLink {
    static func open(for service: PermissionService) {
        NSWorkspace.shared.open(url(for: service))
    }

    static func openFullDiskAccess() {
        open(for: .fullDiskAccess)
    }

    static func openPrivacyPane() {
        NSWorkspace.shared.open(privacyPaneURL)
    }

    static let loginItemsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    )!

    static func openLoginItems() {
        NSWorkspace.shared.open(loginItemsURL)
    }

    static func url(for service: PermissionService) -> URL {
        URL(string: urlString(for: service))!
    }

    static let privacyPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security"
    )!

    static func urlString(for service: PermissionService) -> String {
        "x-apple.systempreferences:com.apple.preference.security?\(anchor(for: service))"
    }

    private static func anchor(for service: PermissionService) -> String {
        switch service {
        case .accessibility:   "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        case .fullDiskAccess:  "Privacy_AllFiles"
        case .microphone:      "Privacy_Microphone"
        case .camera:          "Privacy_Camera"
        case .automation:      "Privacy_Automation"
        case .filesAndFolders: "Privacy_FilesAndFolders"
        case .photos:          "Privacy_Photos"
        case .calendar:        "Privacy_Calendars"
        case .contacts:        "Privacy_Contacts"
        case .reminders:       "Privacy_Reminders"
        case .bluetooth:       "Privacy_Bluetooth"
        case .mediaLibrary:    "Privacy_Media"
        case .appManagement:   "Privacy_AppBundles"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .developerTool:   "Privacy_DeveloperTool"
        }
    }
}
