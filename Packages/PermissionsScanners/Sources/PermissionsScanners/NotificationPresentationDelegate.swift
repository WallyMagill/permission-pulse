import Foundation
import UserNotifications

/// Asks the system to present banners even while Permission Pulse is the
/// frontmost app, and hands a clicked notification's request identifier to
/// the app so it can open the matching window. Without a delegate, macOS
/// delivers foreground notifications silently into Notification Center
/// (`presented = 0`), which makes "Send test notification" look broken to a
/// user sitting in Preferences watching for the banner.
public final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Show the banner, keep it in Notification Center, and play the sound
    /// the request asked for. Applies to all our notifications — both the
    /// one-shot test and the weekly digest are explicit user-requested
    /// signals, never spam, so foreground suppression is never wanted.
    public static let foregroundPresentationOptions: UNNotificationPresentationOptions = [
        .banner, .list, .sound,
    ]

    private let onOpen: @MainActor @Sendable (String) -> Void

    /// `onOpen` receives the request identifier of a notification the user
    /// clicked.
    public init(onOpen: @escaping @MainActor @Sendable (String) -> Void = { _ in }) {
        self.onOpen = onOpen
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundPresentationOptions
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let identifier = response.notification.request.identifier
        await onOpen(identifier)
    }
}
