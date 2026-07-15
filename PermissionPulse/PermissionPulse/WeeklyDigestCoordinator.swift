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

    enum AuthorizationResult: Sendable, Equatable {
        case scheduled
        case deniedNeedsSystemSettings
        case disabled
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

    init(
        viewModel: AppViewModel,
        preferencesStore: PreferencesStore,
        scheduler: any WeeklyDigestScheduler = LiveWeeklyDigestScheduler(),
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.viewModel = viewModel
        self.preferencesStore = preferencesStore
        self.scheduler = scheduler
        self.now = now
    }

    /// Read prefs and either cancel pending digests (if disabled) or
    /// cancel-then-schedule a fresh weekly request (if enabled and
    /// authorized). Idempotent — safe to call on every boot and after
    /// the user toggles a preference.
    func reconcileSchedule() async {
        await scheduler.cancelAll(matchingPrefix: Self.identifierPrefix)
        guard preferencesStore.digestEnabled else { return }

        let status = await scheduler.currentAuthorizationStatus()
        guard status == .authorized || status == .provisional else {
            Self.logger.info(
                "Skipping schedule — digest enabled but status is \(String(describing: status), privacy: .public)"
            )
            return
        }

        let composed = composeDigestBody(diff: viewModel.latestDiffWeek)
        do {
            try await scheduler.scheduleWeekly(
                identifier: Self.weeklyIdentifier,
                weekday: preferencesStore.digestWeekday,
                hour: preferencesStore.digestHour,
                minute: preferencesStore.digestMinute,
                title: composed.title,
                body: composed.body
            )
        } catch {
            Self.logger.error(
                "Failed to schedule weekly digest: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Called when the user flips the digest toggle in Preferences.
    /// Returns the resulting state so the UI can update its hint.
    func handleAuthorizationToggle(turnOn: Bool) async -> AuthorizationResult {
        guard turnOn else {
            await scheduler.cancelAll(matchingPrefix: Self.identifierPrefix)
            return .disabled
        }

        let initial = await scheduler.currentAuthorizationStatus()
        let final: DigestAuthorizationStatus
        if initial == .notDetermined {
            do {
                final = try await scheduler.requestAuthorization()
            } catch {
                Self.logger.error(
                    "requestAuthorization threw: \(error.localizedDescription, privacy: .public)"
                )
                return .deniedNeedsSystemSettings
            }
        } else {
            final = initial
        }

        switch final {
        case .authorized, .provisional:
            await reconcileSchedule()
            return .scheduled
        case .denied, .notDetermined, .unknown:
            return .deniedNeedsSystemSettings
        }
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
        await scheduler.nextFireDate(for: Self.weeklyIdentifier)
    }

    /// Pure, testable. Composes title + body from the week-long diff.
    /// All strings go through `String(localized:)` per project rules.
    /// Empty-week deliberately ships a heartbeat ("No changes") rather
    /// than suppressing the notification — silence would be misread.
    func composeDigestBody(
        diff: SnapshotDiffs?
    ) -> (title: String, body: String) {
        let title = String(localized: "Permission Pulse · Weekly digest")

        guard let diff, diff.hasContent else {
            return (title, String(localized: "No changes in the last week."))
        }

        let added = diff.tcc.added.count + diff.btm.added.count + diff.launchAgents.added.count
        let removed = diff.tcc.removed.count + diff.btm.removed.count + diff.launchAgents.removed.count
        let changed = diff.tcc.changed.count + diff.btm.changed.count + diff.launchAgents.changed.count

        var fragments: [String] = []
        if added > 0 { fragments.append(String(localized: "\(added) added")) }
        if removed > 0 { fragments.append(String(localized: "\(removed) removed")) }
        if changed > 0 { fragments.append(String(localized: "\(changed) changed")) }
        // One localized format string so the sentence stays translatable as a
        // unit instead of gluing an " in the last week." shard onto the list.
        let counts = fragments.joined(separator: ", ")
        let body = String(localized: "\(counts) in the last week.")
        return (title, body)
    }
}
