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
    func cancelAll(matchingPrefix prefix: String) async
    func pendingIdentifiers() async -> [String]
}
