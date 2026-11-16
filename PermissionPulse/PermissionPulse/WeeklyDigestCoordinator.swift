import Foundation
import OSLog
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI

@MainActor
final class WeeklyDigestCoordinator {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "weekly-digest"
    )

    static let identifierPrefix = "com.wallymagill.permissionpulse.digest.weekly"
    static let weeklyIdentifier = "com.wallymagill.permissionpulse.digest.weekly.v1"
    static let testIdentifierPrefix = "com.wallymagill.permissionpulse.digest.test"
    /// A digest that came due while the Mac slept, delivered as a one-shot.
    /// Under `identifierPrefix`, so turning the digest off and Reset All Data
    /// cancel it; outside `weeklyIdentifier`, so a re-arm does not.
    static let overdueIdentifier = "com.wallymagill.permissionpulse.digest.weekly.overdue"

    enum ScheduleResult: Sendable, Equatable {
        case disabled
        case scheduled(nextFire: Date?)
        case notAuthorized
        case failed(String)
    }

    enum TestSendResult: Sendable, Equatable {
        case scheduled(in: TimeInterval)
        case notAuthorized
        case failed(String)
    }

    private let viewModel: AppViewModel
    private let preferencesStore: PreferencesStore
    let scheduler: any WeeklyDigestScheduler
    private let now: @Sendable () -> Date
    private let onScheduleMutationQueued: @MainActor () -> Void
    private var scheduleMutationInProgress = false
    private var scheduleMutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        viewModel: AppViewModel,
        preferencesStore: PreferencesStore,
        scheduler: any WeeklyDigestScheduler = LiveWeeklyDigestScheduler(),
        now: @Sendable @escaping () -> Date = Date.init,
        onScheduleMutationQueued: @MainActor @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.preferencesStore = preferencesStore
        self.scheduler = scheduler
        self.now = now
        self.onScheduleMutationQueued = onScheduleMutationQueued
    }

    /// Read prefs and either cancel pending digests (if disabled) or
    /// cancel-then-schedule a fresh weekly request (if enabled and
    /// authorized). Idempotent — safe to call on every boot and after
    /// the user toggles a preference.
    func reconcileSchedule() async -> ScheduleResult {
        await withScheduleMutation { await reconcileScheduleOwned() }
    }

    private func reconcileScheduleOwned() async -> ScheduleResult {
        let overdue = await weeklyRequestIsOverdue()
        guard scheduleIsActive else { return await cancelDisabledSchedule() }
        await scheduler.cancelAll(matchingPrefix: Self.weeklyIdentifier)

        let status = await scheduler.currentAuthorizationStatus()
        guard scheduleIsActive else { return .disabled }
        guard status == .authorized || status == .provisional else {
            Self.logger.info(
                "Skipping schedule — digest enabled but status is \(String(describing: status), privacy: .public)"
            )
            return .notAuthorized
        }

        let composed = composeDigestBody(diff: viewModel.latestDiffWeek)
        if overdue { await deliverOverdueDigest(composed) }
        do {
            try await scheduler.scheduleWeekly(
                identifier: Self.weeklyIdentifier,
                weekday: preferencesStore.digestWeekday,
                hour: preferencesStore.digestHour,
                minute: preferencesStore.digestMinute,
                title: composed.title,
                body: composed.body
            )
            guard scheduleIsActive else { return await cancelDisabledSchedule() }
            let nextFire = await scheduler.nextFireDate(for: Self.weeklyIdentifier)
            guard scheduleIsActive else { return await cancelDisabledSchedule() }
            return .scheduled(nextFire: nextFire)
        } catch {
            guard scheduleIsActive else { return await cancelDisabledSchedule() }
            Self.logger.error(
                "Failed to schedule weekly digest: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }
    }

    /// A pending weekly request whose armed date has passed came due while
    /// the Mac slept and has not been delivered yet; cancelling it to re-arm
    /// would lose that week's digest. Its next trigger date can't tell: for
    /// a weekday and time that is always in the future.
    private func weeklyRequestIsOverdue() async -> Bool {
        guard await scheduler.pendingIdentifiers().contains(Self.weeklyIdentifier),
              let armed = await scheduler.armedFireDate(for: Self.weeklyIdentifier) else { return false }
        return armed <= now()
    }

    private func deliverOverdueDigest(_ composed: (title: String, body: String)) async {
        do {
            try await scheduler.scheduleOneShot(
                identifier: Self.overdueIdentifier,
                after: ChangeAlertCoordinator.deliveryDelay,
                title: composed.title,
                body: composed.body
            )
        } catch {
            Self.logger.error("Overdue digest failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called when the user flips the digest toggle in Preferences.
    /// Returns the resulting state so the UI can update its hint.
    func handleAuthorizationToggle(turnOn: Bool) async -> ScheduleResult {
        await withScheduleMutation {
            await handleAuthorizationToggleOwned(turnOn: turnOn)
        }
    }

    private func handleAuthorizationToggleOwned(turnOn: Bool) async -> ScheduleResult {
        guard turnOn else {
            await scheduler.cancelAll(matchingPrefix: Self.identifierPrefix)
            return .disabled
        }

        switch await NotificationAuthorization.ensure(using: scheduler) {
        case .authorized: return await reconcileScheduleOwned()
        case .denied: return .notAuthorized
        case .failed(let message): return .failed(message)
        }
    }

    private var scheduleIsActive: Bool {
        preferencesStore.digestEnabled && !Task.isCancelled
    }

    private func cancelDisabledSchedule() async -> ScheduleResult {
        await scheduler.cancelAll(matchingPrefix: Self.identifierPrefix)
        return .disabled
    }

    func cancelWeeklySchedule() async {
        _ = await withScheduleMutation {
            await scheduler.cancelAll(matchingPrefix: Self.identifierPrefix)
            return .disabled
        }
    }

    private func withScheduleMutation(
        _ operation: @MainActor () async -> ScheduleResult
    ) async -> ScheduleResult {
        onScheduleMutationQueued()
        await acquireScheduleMutation()
        defer { releaseScheduleMutation() }
        guard !Task.isCancelled else { return .disabled }
        return await operation()
    }

    private func acquireScheduleMutation() async {
        guard scheduleMutationInProgress else {
            scheduleMutationInProgress = true
            return
        }
        await withCheckedContinuation { scheduleMutationWaiters.append($0) }
    }

    private func releaseScheduleMutation() {
        guard !scheduleMutationWaiters.isEmpty else {
            scheduleMutationInProgress = false
            return
        }
        scheduleMutationWaiters.removeFirst().resume()
    }

    /// Schedule a one-shot test notification N seconds from now. Bypasses
    /// the weekly-calendar-trigger logic entirely so the user can verify the
    /// OS delivery pipeline (auth state, signing, banner presentation)
    /// independently. Identifier carries a unique suffix so multiple test
    /// sends in a row don't collide.
    func sendTestNotification(after seconds: TimeInterval = 5) async -> TestSendResult {
        let status = await scheduler.currentAuthorizationStatus()
        guard status == .authorized || status == .provisional else {
            return .notAuthorized
        }
        let id = "\(Self.testIdentifierPrefix).\(UUID().uuidString)"
        do {
            try await scheduler.scheduleOneShot(
                identifier: id,
                after: seconds,
                title: String(localized: "Permission Pulse · Test"),
                body: String(localized: "If you see this banner, notifications are working.")
            )
            return .scheduled(in: seconds)
        } catch {
            Self.logger.error(
                "Test notification failed: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }
    }

    /// Next fire date for the weekly digest, if any pending. Surfaces in
    /// the Preferences hint card so users see a concrete date.
    func nextWeeklyFireDate() async -> Date? {
        await acquireScheduleMutation()
        defer { releaseScheduleMutation() }
        guard !Task.isCancelled else { return nil }
        return await scheduler.nextFireDate(for: Self.weeklyIdentifier)
    }

    /// Composes title + body from the week-long diff's visible changes, the
    /// same ones Recent Changes lists. All strings go through
    /// `String(localized:)` per project rules. Empty-week deliberately ships
    /// a heartbeat ("No changes") rather than suppressing the notification —
    /// silence would be misread — but never claims it for data that wasn't
    /// compared.
    func composeDigestBody(
        diff: SnapshotDiffs?
    ) -> (title: String, body: String) {
        let title = String(localized: "Permission Pulse · Weekly digest")

        guard let diff else {
            return (title, String(localized: "History is less than a week old, so there's nothing to compare yet."))
        }
        guard !diff.comparedDomains.isEmpty else {
            return (title, String(localized: "This week's history couldn't be compared."))
        }
        let uncompared = ListFormatter.localizedString(
            byJoining: diff.uncomparedDomains.map(\.displayName)
        )
        let entries = viewModel.visibleEntries(of: diff, asOf: now())
        guard !entries.isEmpty else {
            let body = diff.uncomparedDomains.isEmpty
                ? String(localized: "No changes in the last week.")
                : String(localized: "No changes found in compared data; \(uncompared) couldn't be compared this week.")
            return (title, body)
        }

        let added = entries.filter { $0.change == .added }.count
        let removed = entries.filter { $0.change == .removed }.count
        let changed = entries.filter { $0.change == .changed }.count

        var fragments: [String] = []
        if added > 0 { fragments.append(String(localized: "\(added) added")) }
        if removed > 0 { fragments.append(String(localized: "\(removed) removed")) }
        if changed > 0 { fragments.append(String(localized: "\(changed) changed")) }
        // One localized format string so the sentence stays translatable as a
        // unit instead of gluing an " in the last week." shard onto the list.
        let counts = fragments.joined(separator: ", ")
        let body = diff.uncomparedDomains.isEmpty
            ? String(localized: "\(counts) in the last week.")
            : String(localized: "\(counts) in the last week. \(uncompared) couldn't be compared.")
        return (title, body)
    }
}
