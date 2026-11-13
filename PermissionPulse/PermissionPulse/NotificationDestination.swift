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
