import Foundation
import OSLog
import UserNotifications
import PermissionsCore

/// Production-side `WeeklyDigestScheduler` backed by
/// `UNUserNotificationCenter.current()`. Permission Pulse does not own
/// a delegate yet — taps on the delivered notification will simply
/// activate the app (v0.7.1 candidate to route into Recent Changes).
public struct LiveWeeklyDigestScheduler: WeeklyDigestScheduler {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "digest-scheduler"
    )

    public init() {}

    public func currentAuthorizationStatus() async -> DigestAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    public func requestAuthorization() async throws -> DigestAuthorizationStatus {
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        // `requestAuthorization` returns Bool; re-read the settings to get
        // the precise status (handles .provisional too).
        if granted == false {
            Self.logger.info("Notification authorization denied")
        }
        return await currentAuthorizationStatus()
    }

    public func scheduleWeekly(
        identifier: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) async throws {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    public func scheduleOneShot(
        identifier: String,
        after seconds: TimeInterval,
        title: String,
        body: String
    ) async throws {
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, seconds),
            repeats: false
        )

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    public func cancelAll(matchingPrefix prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let toCancel = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        if !toCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toCancel)
        }
    }

    public func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current()
            .pendingNotificationRequests()
            .map(\.identifier)
    }

    public func nextFireDate(for identifier: String) async -> Date? {
        let pending = await UNUserNotificationCenter.current()
            .pendingNotificationRequests()
        guard let request = pending.first(where: { $0.identifier == identifier }) else {
            return nil
        }
        if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger {
            return calendarTrigger.nextTriggerDate()
        }
        if let intervalTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
            return intervalTrigger.nextTriggerDate()
        }
        return nil
    }

    // MARK: - Private

    private static func map(_ status: UNAuthorizationStatus) -> DigestAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied:        return .denied
        case .authorized:    return .authorized
        case .provisional:   return .provisional
        case .ephemeral:     return .authorized
        @unknown default:    return .unknown
        }
    }
}
