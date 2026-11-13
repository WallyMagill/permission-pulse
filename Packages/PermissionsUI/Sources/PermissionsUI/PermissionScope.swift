import Foundation
import PermissionsCore

/// What the Permissions scan can see. On macOS 27 the per-user permission
/// records are hidden from every app, so only `PermissionService.systemLevel`
/// is visible; every screen asks this one type before it claims "no app has
/// Camera access" when the truth is "macOS no longer lets apps see this".
public struct PermissionScope: Sendable, Equatable {
    public let isReduced: Bool

    public init(isReduced: Bool) {
        self.isReduced = isReduced
    }

    public init(unavailableSources: [ScannerSource]) {
        self.init(isReduced: unavailableSources.contains(.userTCCDatabase))
    }

    public static let full = PermissionScope(isReduced: false)
    public static let systemLevelOnly = PermissionScope(isReduced: true)

    /// System-level services in display order.
    public static let systemLevelServices: [PermissionService] = PermissionService.allCases
        .filter { PermissionService.systemLevel.contains($0) }

    public func isHidden(_ service: PermissionService) -> Bool {
        isReduced && !PermissionService.systemLevel.contains(service)
    }

    /// The hidden service a search names, when the scope is reduced: the
    /// query is part of the service's name ("cam", "Camera") or contains it
    /// ("camera access"). Two-letter queries match too much to mean one service.
    public func hiddenService(matching query: String) -> PermissionService? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReduced, trimmed.count >= 3 else { return nil }
        return PermissionService.allCases.first { service in
            isHidden(service)
                && (service.displayName.localizedCaseInsensitiveContains(trimmed)
                    || trimmed.localizedCaseInsensitiveContains(service.displayName))
        }
    }

    public static func hiddenServiceMessage(_ service: PermissionService) -> String {
        String(localized: "macOS 27 doesn't let apps see which apps have \(service.displayName) access")
    }

    public static func openServiceSettingsTitle(_ service: PermissionService) -> String {
        String(localized: "Open \(service.displayName) in System Settings")
    }

    /// The Overview's "Permission coverage" value. `hasData` is false until
    /// a permissions scan has succeeded.
    public func coverageText(hasData: Bool) -> String {
        if isReduced { return String(localized: "System-level only (macOS 27)") }
        return hasData ? String(localized: "All permissions") : String(localized: "Unknown")
    }

    static var systemLevelServiceList: String {
        ListFormatter.localizedString(byJoining: systemLevelServices.map(\.displayName))
    }
}

extension AppViewModel {
    public var permissionScope: PermissionScope {
        PermissionScope(unavailableSources: tccUnavailableSources)
    }

    /// False until a permissions scan has succeeded; last-known data counts.
    public var hasPermissionData: Bool {
        tccAvailability.lastSuccessful != nil
    }
}
