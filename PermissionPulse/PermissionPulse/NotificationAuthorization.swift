import Foundation
import OSLog
import PermissionsCore

/// The one place either notification toggle asks macOS for permission, so
/// turning on change alerts or the digest triggers the same one-time prompt.
enum NotificationAuthorization {
    enum Outcome: Sendable, Equatable {
        case authorized
        case denied
        case failed(String)
    }

    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "notification-authorization"
    )

    /// Requests permission only while the user has never been asked.
    static func ensure(using scheduler: any WeeklyDigestScheduler) async -> Outcome {
        let initial = await scheduler.currentAuthorizationStatus()
        let final: DigestAuthorizationStatus
        if initial == .notDetermined {
            do {
                final = try await scheduler.requestAuthorization()
            } catch {
                logger.error("requestAuthorization threw: \(error.localizedDescription, privacy: .public)")
                return .failed(error.localizedDescription)
            }
        } else {
            final = initial
        }
        return isAllowed(final) ? .authorized : .denied
    }

    static func isAuthorized(using scheduler: any WeeklyDigestScheduler) async -> Bool {
        isAllowed(await scheduler.currentAuthorizationStatus())
    }

    private static func isAllowed(_ status: DigestAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }
}
