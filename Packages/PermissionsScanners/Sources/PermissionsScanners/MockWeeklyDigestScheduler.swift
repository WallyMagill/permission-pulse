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
    }

    private var status: DigestAuthorizationStatus
    private var requestNextResult: DigestAuthorizationStatus?
    private var pending: [String] = []
    private var nextFireDates: [String: Date] = [:]
    public private(set) var recorded: [RecordedAction] = []

    public init(initialStatus: DigestAuthorizationStatus = .notDetermined) {
        self.status = initialStatus
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
        recorded.append(.scheduled(
            identifier: identifier,
            weekday: weekday,
            hour: hour,
            minute: minute,
            title: title,
            body: body
        ))
        pending.append(identifier)
        // Compute a representative next-fire date (next matching weekday +
        // h:m from now). Tests that don't care can ignore it; tests that do
        // can override via setNextFireDate.
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        nextFireDates[identifier] = Calendar.current.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime
        )
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
        nextFireDates[identifier] = Date(timeIntervalSinceNow: seconds)
    }

    public func cancelAll(matchingPrefix prefix: String) async {
        recorded.append(.canceledAll(matchingPrefix: prefix))
        let removed = pending.filter { $0.hasPrefix(prefix) }
        pending.removeAll { $0.hasPrefix(prefix) }
        for id in removed { nextFireDates.removeValue(forKey: id) }
    }

    public func pendingIdentifiers() async -> [String] {
        recorded.append(.queriedPending)
        return pending
    }

    public func nextFireDate(for identifier: String) async -> Date? {
        recorded.append(.queriedNextFireDate(identifier: identifier))
        return nextFireDates[identifier]
    }

    // MARK: - Test seams

    public func setAuthorizationStatus(_ newStatus: DigestAuthorizationStatus) {
        status = newStatus
    }

    public func setRequestAuthorizationResult(_ result: DigestAuthorizationStatus) {
        requestNextResult = result
    }

    public func setNextFireDate(_ date: Date, for identifier: String) {
        nextFireDates[identifier] = date
    }
}
