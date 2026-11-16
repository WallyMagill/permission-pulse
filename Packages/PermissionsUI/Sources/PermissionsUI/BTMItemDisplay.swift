import Foundation
import PermissionsCore

extension BTMItem.ItemType {
    /// Canonical display name for this item type.
    var displayName: String {
        switch self {
        case .app:                   String(localized: "App")
        case .loginItem:             String(localized: "Login item")
        case .agent:                 String(localized: "App agent")
        case .developerGroup:        String(localized: "Developer group")
        case .spotlightImporter:     String(localized: "Spotlight extension")
        case .dockTilePlugin:        String(localized: "Dock tile extension")
        case .quickLookExtension:    String(localized: "QuickLook extension")
        case .backgroundTasks:       String(localized: "Background tasks")
        case .legacyAgent:           String(localized: "Legacy agent")
        case .legacyDaemon:          String(localized: "Legacy daemon")
        case .unknown(let rawValue): String(localized: "Unknown (0x\(String(rawValue, radix: 16)))")
        }
    }

    /// SF Symbol name for this item type.
    var symbolName: String {
        switch self {
        case .app:                "app.fill"
        case .loginItem:          "person.crop.circle.badge.checkmark"
        case .agent:              "gearshape.fill"
        case .developerGroup:     "folder.fill"
        case .spotlightImporter:  "magnifyingglass"
        case .dockTilePlugin:     "dock.rectangle"
        case .quickLookExtension: "eye.fill"
        case .backgroundTasks:    "clock.arrow.circlepath"
        case .legacyAgent:        "gearshape.fill"
        case .legacyDaemon:       "gearshape.2.fill"
        case .unknown:            "questionmark.circle.fill"
        }
    }
}

extension BTMItem.Scope {
    /// Short canonical label, without UUID detail. Suitable for compact row display.
    var displayName: String {
        switch self {
        case .system:  String(localized: "System-wide")
        case .user:    String(localized: "Root user")
        case .perUser: String(localized: "Current user")
        }
    }

    /// Full label including the per-user UUID where available. Suitable for inspector detail.
    var detailedDisplayName: String {
        switch self {
        case .system:                String(localized: "System-wide")
        case .user:                  String(localized: "Root user")
        case .perUser(let uuid):     String(localized: "Current user (\(uuid))")
        }
    }
}
