import Foundation

public enum PermissionService: String, Sendable, CaseIterable, Hashable {
    case accessibility
    case screenRecording
    case fullDiskAccess
    case microphone
    case camera
    case automation
    case filesAndFolders
    case photos
    case calendar
    case contacts
    case reminders
    case bluetooth
    case mediaLibrary
    case appManagement
    case inputMonitoring
    case developerTool

    public var displayName: String {
        switch self {
        case .accessibility:   String(localized: "Accessibility")
        case .screenRecording: String(localized: "Screen Recording")
        case .fullDiskAccess:  String(localized: "Full Disk Access")
        case .microphone:      String(localized: "Microphone")
        case .camera:          String(localized: "Camera")
        case .automation:      String(localized: "Automation")
        case .filesAndFolders: String(localized: "Files and Folders")
        case .photos:          String(localized: "Photos")
        case .calendar:        String(localized: "Calendar")
        case .contacts:        String(localized: "Contacts")
        case .reminders:       String(localized: "Reminders")
        case .bluetooth:       String(localized: "Bluetooth")
        case .mediaLibrary:    String(localized: "Media Library")
        case .appManagement:   String(localized: "App Management")
        case .inputMonitoring: String(localized: "Input Monitoring")
        case .developerTool:   String(localized: "Developer Tools")
        }
    }

    public static let knownSkipped: Set<String> = [
        "kTCCServiceLiverpool",
        "kTCCServiceUbiquity",
        "kTCCServiceFocusStatus",
        "kTCCServiceFileProviderDomain",
        "kTCCServiceWebBrowserPublicKeyCredential",
        "kTCCServicePostEvent",
    ]

    /// The `tccutil reset <name>` service argument (the `kTCCService` prefix
    /// stripped). `nil` for `.filesAndFolders`, whose grant comes from five
    /// distinct sub-services with no single canonical reset target. (F2)
    public var tccutilServiceName: String? {
        switch self {
        case .accessibility:   "Accessibility"
        case .screenRecording: "ScreenCapture"
        case .fullDiskAccess:  "SystemPolicyAllFiles"
        case .microphone:      "Microphone"
        case .camera:          "Camera"
        case .automation:      "AppleEvents"
        case .filesAndFolders: nil
        case .photos:          "Photos"
        case .calendar:        "Calendar"
        case .contacts:        "AddressBook"
        case .reminders:       "Reminders"
        case .bluetooth:       "BluetoothAlways"
        case .mediaLibrary:    "MediaLibrary"
        case .appManagement:   "SystemPolicyAppBundles"
        case .inputMonitoring: "ListenEvent"
        case .developerTool:   "DeveloperTool"
        }
    }

    public init?(tccServiceString: String) {
        if Self.knownSkipped.contains(tccServiceString) {
            return nil
        }
        switch tccServiceString {
        case "kTCCServiceAccessibility":              self = .accessibility
        case "kTCCServiceScreenCapture":              self = .screenRecording
        case "kTCCServiceSystemPolicyAllFiles":       self = .fullDiskAccess
        case "kTCCServiceMicrophone":                 self = .microphone
        case "kTCCServiceCamera":                     self = .camera
        case "kTCCServiceAppleEvents":                self = .automation
        case "kTCCServiceSystemPolicyDesktopFolder",
             "kTCCServiceSystemPolicyDocumentsFolder",
             "kTCCServiceSystemPolicyDownloadsFolder",
             "kTCCServiceSystemPolicyNetworkVolumes",
             "kTCCServiceSystemPolicyRemovableVolumes":
            self = .filesAndFolders
        case "kTCCServicePhotos":                     self = .photos
        case "kTCCServiceCalendar":                   self = .calendar
        case "kTCCServiceAddressBook":                self = .contacts
        case "kTCCServiceReminders":                  self = .reminders
        case "kTCCServiceBluetoothAlways":            self = .bluetooth
        case "kTCCServiceMediaLibrary":               self = .mediaLibrary
        case "kTCCServiceSystemPolicyAppBundles",
             "kTCCServiceSystemPolicyAppData":
            self = .appManagement
        case "kTCCServiceListenEvent":                self = .inputMonitoring
        case "kTCCServiceDeveloperTool":              self = .developerTool
        default:                                      return nil
        }
    }
}

extension PermissionService {
    /// `tccutil reset` commands for an app, one per mappable service, sorted and
    /// de-duplicated. Empty when the app has no bundle ID (the command needs one).
    /// Display/copy only — Permission Pulse never runs these. (F2)
    public static func tccutilResetCommands(bundleID: String, services: [PermissionService]) -> [String] {
        guard !bundleID.isEmpty else { return [] }
        let names = Set(services.compactMap(\.tccutilServiceName)).sorted()
        return names.map { "tccutil reset \($0) \(bundleID)" }
    }
}
