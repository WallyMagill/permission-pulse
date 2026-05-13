import Foundation

public enum PermissionService: String, Sendable, CaseIterable, Hashable {
    case accessibility
    case screenRecording
    case fullDiskAccess
    case microphone
    case camera
    case automation
    case filesAndFolders

    public var displayName: String {
        switch self {
        case .accessibility:   String(localized: "Accessibility")
        case .screenRecording: String(localized: "Screen Recording")
        case .fullDiskAccess:  String(localized: "Full Disk Access")
        case .microphone:      String(localized: "Microphone")
        case .camera:          String(localized: "Camera")
        case .automation:      String(localized: "Automation")
        case .filesAndFolders: String(localized: "Files and Folders")
        }
    }
}
