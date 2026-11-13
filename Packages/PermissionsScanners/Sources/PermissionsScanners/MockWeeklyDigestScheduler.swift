import Foundation
import PermissionsCore

/// In-memory `WeeklyDigestScheduler` for tests. Records every call as a
/// `RecordedAction` so suites can assert against the exact order and
/// payloads. Authorization status is configurable per-instance and
/// pluggable mid-test via `setAuthorizationStatus`.
public actor MockWeeklyDigestScheduler: WeeklyDigestScheduler {
    public enum RecordedAction: Sendable, Equatable {
        case requestedAuthorization
        case scheduled(
            identifier: String,
            weekday: Int,
            hour: Int,
            minute: Int,
            title: String,
            body: String
        )
        case scheduledOneShot(
            identifier: String,
            after: TimeInterval,
            title: String,
            body: String
        )
        case canceledAll(matchingPrefix: String)
        case queriedPending
        case queriedNextFireDate(identifier: String)
        case queriedArmedFireDate(identifier: String)
    }

    private var status: DigestAuthorizationStatus
    private var requestNextResult: DigestAuthorizationStatus?
    private var nextScheduleError: (any Error & Sendable)?
    private var pending: [String] = []
    private var nextFireDates: [String: Date] = [:]
    private var calendarRequests: [String: (components: DateComponents, armed: Date?)] = [:]
    private let now: @Sendable () -> Date
    public private(set) var recorded: [RecordedAction] = []

    public init(
        initialStatus: DigestAuthorizationStatus = .notDetermined,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.status = initialStatus
        self.now = now
    }

    public func currentAuthorizationStatus() async -> DigestAuthorizationStatus {
        status
    }

    public func requestAuthorization() async throws -> DigestAuthorizationStatus {
        recorded.append(.requestedAuthorization)
        if let next = requestNextResult {
            status = next
            requestNextResult = nil
        } else if status == .notDetermined {
            // Default to grant unless the test overrides; matches a "user
            // taps Allow" baseline.
            status = .authorized
        }
        return status
    }

    public func scheduleWeekly(
        identifier: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) async throws {
        if let error = nextScheduleError {
            nextScheduleError = nil
            throw error
        }
        recorded.append(.scheduled(
            identifier: identifier,
            weekday: weekday,
            hour: hour,
            minute: minute,
            title: title,
            body: body
        ))
        pending.append(identifier)
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        calendarRequests[identifier] = (components, Self.nextDate(after: now(), matching: components))
    }

    public func scheduleOneShot(
        identifier: String,
        after seconds: TimeInterval,
        title: String,
        body: String
    ) async throws {
        recorded.append(.scheduledOneShot(
            identifier: identifier,
            after: seconds,
            title: title,
            body: body
        ))
        pending.append(identifier)
        nextFireDates[identifier] = now().addingTimeInterval(seconds)
    }

    public func cancelAll(matchingPrefix prefix: String) async {
        recorded.append(.canceledAll(matchingPrefix: prefix))
        let removed = pending.filter { $0.hasPrefix(prefix) }
        pending.removeAll { $0.hasPrefix(prefix) }
        for id in removed {
            nextFireDates.removeValue(forKey: id)
            calendarRequests.removeValue(forKey: id)
        }
    }

    public func pendingIdentifiers() async -> [String] {
        recorded.append(.queriedPending)
        return pending
    }

    /// Like `UNCalendarNotificationTrigger.nextTriggerDate()`, a pending
    /// calendar request reports the next match after now, never a past date.
    public func nextFireDate(for identifier: String) async -> Date? {
        recorded.append(.queriedNextFireDate(identifier: identifier))
        if let request = calendarRequests[identifier] {
            return Self.nextDate(after: now(), matching: request.components)
        }
        return nextFireDates[identifier]
    }

    public func armedFireDate(for identifier: String) async -> Date? {
        recorded.append(.queriedArmedFireDate(identifier: identifier))
        return calendarRequests[identifier]?.armed
    }

    private static func nextDate(after date: Date, matching components: DateComponents) -> Date? {
        Calendar.current.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
    }

    // MARK: - Test seams

    public func setAuthorizationStatus(_ newStatus: DigestAuthorizationStatus) {
        status = newStatus
    }

    public func setRequestAuthorizationResult(_ result: DigestAuthorizationStatus) {
        requestNextResult = result
    }

    public func setNextScheduleError(_ error: (any Error & Sendable)?) {
        nextScheduleError = error
    }
}
