import Foundation

/// Authorization status mirror so callers don't have to depend on
/// UserNotifications. Matches `UNAuthorizationStatus` cases that we
/// care about (the rest collapse into `.unknown`).
public enum DigestAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unknown
}

/// Surface for scheduling the weekly digest local notification. Lives in
/// `PermissionsCore` so coordinator/test code never has to import
/// `UserNotifications` directly; the live impl wraps
/// `UNUserNotificationCenter`.
public protocol WeeklyDigestScheduler: Sendable {
    func currentAuthorizationStatus() async -> DigestAuthorizationStatus
    func requestAuthorization() async throws -> DigestAuthorizationStatus
    func scheduleWeekly(
        identifier: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) async throws
    /// Schedule a one-shot notification N seconds from now. Used by the
    /// Preferences "Send test notification" affordance to decouple the OS
    /// delivery pipeline from the weekly-calendar-trigger logic — if the
    /// one-shot lands but the weekly doesn't, the bug is in the
    /// calendar-components math; if neither lands, the bug is in the
    /// auth/signing/delivery layer.
    func scheduleOneShot(
        identifier: String,
        after seconds: TimeInterval,
        title: String,
        body: String
    ) async throws
    func cancelAll(matchingPrefix prefix: String) async
    func pendingIdentifiers() async -> [String]
    /// Returns the next time the request with `identifier` is expected to
    /// fire, or `nil` if no such request is pending. Used by the
    /// Preferences hint card to surface a concrete next-fire timestamp.
    func nextFireDate(for identifier: String) async -> Date?
}
