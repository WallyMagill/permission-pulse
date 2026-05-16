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
        case canceledAll(matchingPrefix: String)
        case queriedPending
    }

    private var status: DigestAuthorizationStatus
    private var requestNextResult: DigestAuthorizationStatus?
    private var pending: [String] = []
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
    }

    public func cancelAll(matchingPrefix prefix: String) async {
        recorded.append(.canceledAll(matchingPrefix: prefix))
        pending.removeAll { $0.hasPrefix(prefix) }
    }

    public func pendingIdentifiers() async -> [String] {
        recorded.append(.queriedPending)
        return pending
    }

    // MARK: - Test seams

    public func setAuthorizationStatus(_ newStatus: DigestAuthorizationStatus) {
        status = newStatus
    }

    public func setRequestAuthorizationResult(_ result: DigestAuthorizationStatus) {
        requestNextResult = result
    }
}
