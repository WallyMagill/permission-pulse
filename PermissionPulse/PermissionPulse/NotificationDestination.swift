import PermissionsUI

/// Where a click on one of Permission Pulse's notifications leads.
enum NotificationDestination: Equatable {
    case detail(AppRoute)
    case fullDiskAccessRecovery

    /// Nil for the Preferences test notification, which has nothing to show.
    static func forRequest(_ identifier: String) -> NotificationDestination? {
        if identifier == ChangeAlertCoordinator.fullDiskAccessIdentifier { return .fullDiskAccessRecovery }
        if identifier.hasPrefix(ChangeAlertCoordinator.identifierPrefix) { return .detail(.recentChanges) }
        if identifier.hasPrefix(WeeklyDigestCoordinator.identifierPrefix)
            || identifier == WeeklyDigestCoordinator.overdueIdentifier {
            return .detail(.recentChangesLastSevenDays)
        }
        return nil
    }
}

/// A notification click can arrive before the runtime exists: the system
/// delivers the click that launched the app as soon as launch finishes,
/// while this copy may still be waiting on the single-instance check. The
/// click is held until the runtime starts, then routed; a copy that hands
/// off to another instance drops it.
struct NotificationOpenGate: Equatable {
    private(set) var runtimeStarted = false
    private(set) var held: String?

    /// The identifier to route now, or nil when it is held.
    mutating func received(_ identifier: String) -> String? {
        if runtimeStarted { return identifier }
        held = identifier
        return nil
    }

    /// The held identifier, if any, to route now that the runtime runs.
    mutating func startRuntime() -> String? {
        runtimeStarted = true
        defer { held = nil }
        return held
    }

    mutating func handOff() {
        held = nil
    }
}
