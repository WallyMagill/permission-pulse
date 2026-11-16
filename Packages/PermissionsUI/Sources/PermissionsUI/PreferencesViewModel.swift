import Foundation
import Observation

/// Bridges `PreferencesStore` to the Preferences SwiftUI surface.
///
/// View-bound bindings always use the `Double` mirrors for sliders (SwiftUI
/// `Slider` wants `Double`); the underlying store stores `Int`. Calls into
/// the digest authorization flow go through `onDigestToggle`, which the app
/// target wires to `WeeklyDigestCoordinator.handleAuthorizationToggle`.
@Observable
@MainActor
public final class PreferencesViewModel {
    public enum AuthorizationHint: Sendable, Equatable {
        case notYetRequested
        case scheduled(nextFireDescription: String)
        case denied
        case disabled
        case failed(String)
    }

    /// Change alerts need nothing scheduled, only permission to notify.
    public enum ChangeAlertsHint: Sendable, Equatable {
        case off
        case on
        case denied
        case failed(String)
    }

    public enum TestNotificationResult: Sendable, Equatable {
        case idle
        case scheduling
        case scheduled(in: TimeInterval)
        case notAuthorized
        case failed(String)
    }

    // `var` (not `let`) so SwiftUI can synthesize a writable key-path
    // through `$vm.store.<...>` via @Bindable. The reference never changes.
    public var store: PreferencesStore
    public var authorizationHint: AuthorizationHint = .notYetRequested
    public var nextWeeklyFireDate: Date?
    public var testNotificationResult: TestNotificationResult = .idle
    public var changeAlertsHint: ChangeAlertsHint = .off
    public private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    /// The last register/unregister error, shown under the toggle.
    public private(set) var launchAtLoginError: String?

    private let onDigestToggle: @MainActor (Bool) async -> AuthorizationHint
    private let onDigestScheduleChange: @MainActor () async -> AuthorizationHint
    private let onSendTestNotification: @MainActor () async -> TestNotificationResult
    private let onFetchNextFireDate: @MainActor () async -> Date?
    private let onChangeAlertsToggle: @MainActor (Bool) async -> ChangeAlertsHint
    private let scheduleDebounce: Duration
    private let fetchLaunchAtLoginStatus: @MainActor () -> LaunchAtLoginStatus
    private let onLaunchAtLoginToggle: (@MainActor (Bool) throws -> Void)?
    // Swift 6 deinit is nonisolated. Task is Sendable, and every mutation
    // remains MainActor-isolated; only final cancellation crosses isolation.
    @ObservationIgnored
    nonisolated(unsafe) private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var digestOperationID: UInt = 0

    public init(
        store: PreferencesStore,
        onDigestToggle: @escaping @MainActor (Bool) async -> AuthorizationHint = { _ in .disabled },
        onDigestScheduleChange: @escaping @MainActor () async -> AuthorizationHint = { .disabled },
        onSendTestNotification: @escaping @MainActor () async -> TestNotificationResult = { .idle },
        onFetchNextFireDate: @escaping @MainActor () async -> Date? = { nil },
        onChangeAlertsToggle: @escaping @MainActor (Bool) async -> ChangeAlertsHint = { $0 ? .on : .off },
        scheduleDebounce: Duration = .milliseconds(300),
        fetchLaunchAtLoginStatus: @escaping @MainActor () -> LaunchAtLoginStatus = { .notRegistered },
        onLaunchAtLoginToggle: (@MainActor (Bool) throws -> Void)? = nil
    ) {
        self.store = store
        self.onDigestToggle = onDigestToggle
        self.onDigestScheduleChange = onDigestScheduleChange
        self.onSendTestNotification = onSendTestNotification
        self.onFetchNextFireDate = onFetchNextFireDate
        self.onChangeAlertsToggle = onChangeAlertsToggle
        self.scheduleDebounce = scheduleDebounce
        self.fetchLaunchAtLoginStatus = fetchLaunchAtLoginStatus
        self.launchAtLoginStatus = fetchLaunchAtLoginStatus()
        self.onLaunchAtLoginToggle = onLaunchAtLoginToggle
    }

    deinit {
        scheduleTask?.cancel()
    }

    // MARK: - Slider bindings (Double mirrors)

    public var snapshotRetentionDaysDouble: Double {
        get { Double(store.snapshotRetentionDays) }
        set { store.snapshotRetentionDays = Int(newValue) }
    }

    public var staleThresholdDaysDouble: Double {
        get { Double(store.staleThresholdDays) }
        set { store.staleThresholdDays = Int(newValue) }
    }

    // MARK: - Digest toggle

    public var digestEnabled: Bool {
        get { store.digestEnabled }
        set { store.digestEnabled = newValue }
    }

    public func handleDigestToggle(to newValue: Bool) async {
        scheduleTask?.cancel()
        let operationID = beginDigestOperation()
        store.digestEnabled = newValue
        let hint = await onDigestToggle(newValue)
        guard isCurrent(operationID, enabled: newValue) else { return }
        let nextFire = await fetchNextFireDate(for: hint)
        guard isCurrent(operationID, enabled: newValue) else { return }
        authorizationHint = hint
        nextWeeklyFireDate = nextFire
    }

    public func scheduleDidChange() {
        scheduleTask?.cancel()
        let operationID = beginDigestOperation()
        guard store.digestEnabled else {
            nextWeeklyFireDate = nil
            return
        }

        let debounce = scheduleDebounce
        scheduleTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            guard let self, self.isCurrent(operationID, enabled: true), !Task.isCancelled else { return }

            let hint = await self.onDigestScheduleChange()
            guard self.isCurrent(operationID, enabled: true), !Task.isCancelled else { return }
            let nextFire = await self.fetchNextFireDate(for: hint)
            guard self.isCurrent(operationID, enabled: true), !Task.isCancelled else { return }
            self.authorizationHint = hint
            self.nextWeeklyFireDate = nextFire
        }
    }

    public func refreshAuthorizationHint() async {
        // Called on appear so the hint reflects the latest OS state even if
        // the user toggled notifications in System Settings while the app
        // was alive.
        await refreshChangeAlertsHint()
        scheduleTask?.cancel()
        let operationID = beginDigestOperation()
        let enabled = store.digestEnabled
        let hint = await onDigestToggle(enabled)
        guard isCurrent(operationID, enabled: enabled) else { return }
        let nextFire = await fetchNextFireDate(for: hint)
        guard isCurrent(operationID, enabled: enabled) else { return }
        authorizationHint = hint
        nextWeeklyFireDate = nextFire
    }

    private func beginDigestOperation() -> UInt {
        digestOperationID &+= 1
        return digestOperationID
    }

    private func isCurrent(_ operationID: UInt, enabled: Bool) -> Bool {
        digestOperationID == operationID && store.digestEnabled == enabled
    }

    private func fetchNextFireDate(for hint: AuthorizationHint) async -> Date? {
        guard case .scheduled = hint else { return nil }
        return await onFetchNextFireDate()
    }

    // MARK: - Change alerts

    public var changeAlertsEnabled: Bool {
        get { store.changeAlertsEnabled }
        set { store.changeAlertsEnabled = newValue }
    }

    public func handleChangeAlertsToggle(to newValue: Bool) async {
        store.changeAlertsEnabled = newValue
        let hint = await onChangeAlertsToggle(newValue)
        guard store.changeAlertsEnabled == newValue else { return }
        changeAlertsHint = hint
    }

    private func refreshChangeAlertsHint() async {
        guard store.changeAlertsEnabled else {
            changeAlertsHint = .off
            return
        }
        let hint = await onChangeAlertsToggle(true)
        guard store.changeAlertsEnabled else { return }
        changeAlertsHint = hint
    }

    /// Either notification feature is on but macOS will not deliver.
    public var notificationsDenied: Bool {
        authorizationHint == .denied || changeAlertsHint == .denied
    }

    public var anyNotificationEnabled: Bool {
        store.digestEnabled || store.changeAlertsEnabled
    }

    // MARK: - Test notification

    public func sendTestNotification() async {
        testNotificationResult = .scheduling
        let result = await onSendTestNotification()
        testNotificationResult = result
    }

    public func clearTestNotificationResult() {
        testNotificationResult = .idle
    }

    // MARK: - Launch at login

    /// On while registered, including while macOS waits for the user to
    /// approve it in System Settings.
    public var launchAtLoginEnabled: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    /// Re-reads the system state; the user can change it in System Settings
    /// at any time.
    public func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = fetchLaunchAtLoginStatus()
    }

    public func setLaunchAtLogin(_ enable: Bool) {
        guard let onLaunchAtLoginToggle else { return }
        launchAtLoginError = nil
        do {
            try onLaunchAtLoginToggle(enable)
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLoginStatus()
    }
}
