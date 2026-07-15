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
    public private(set) var launchAtLoginEnabled: Bool

    private let onDigestToggle: @MainActor (Bool) async -> AuthorizationHint
    private let onDigestScheduleChange: @MainActor () async -> AuthorizationHint
    private let onSendTestNotification: @MainActor () async -> TestNotificationResult
    private let onFetchNextFireDate: @MainActor () async -> Date?
    private let scheduleDebounce: Duration
    private let onLaunchAtLoginToggle: ((Bool) async -> Bool)?
    // Swift 6 deinit is nonisolated. Task is Sendable, and every mutation
    // remains MainActor-isolated; only final cancellation crosses isolation.
    @ObservationIgnored
    nonisolated(unsafe) private var scheduleTask: Task<Void, Never>?

    public init(
        store: PreferencesStore,
        onDigestToggle: @escaping @MainActor (Bool) async -> AuthorizationHint = { _ in .disabled },
        onDigestScheduleChange: @escaping @MainActor () async -> AuthorizationHint = { .disabled },
        onSendTestNotification: @escaping @MainActor () async -> TestNotificationResult = { .idle },
        onFetchNextFireDate: @escaping @MainActor () async -> Date? = { nil },
        scheduleDebounce: Duration = .milliseconds(300),
        initialLaunchAtLogin: Bool = false,
        onLaunchAtLoginToggle: ((Bool) async -> Bool)? = nil
    ) {
        self.store = store
        self.onDigestToggle = onDigestToggle
        self.onDigestScheduleChange = onDigestScheduleChange
        self.onSendTestNotification = onSendTestNotification
        self.onFetchNextFireDate = onFetchNextFireDate
        self.scheduleDebounce = scheduleDebounce
        self.launchAtLoginEnabled = initialLaunchAtLogin
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
        store.digestEnabled = newValue
        let hint = await onDigestToggle(newValue)
        let nextFire: Date? = if case .scheduled = hint {
            await onFetchNextFireDate()
        } else {
            nil
        }
        authorizationHint = hint
        nextWeeklyFireDate = nextFire
    }

    public func scheduleDidChange() {
        scheduleTask?.cancel()
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
            guard let self, !Task.isCancelled, self.store.digestEnabled else { return }

            let hint = await self.onDigestScheduleChange()
            guard !Task.isCancelled, self.store.digestEnabled else { return }
            let nextFire: Date? = if case .scheduled = hint {
                await self.onFetchNextFireDate()
            } else {
                nil
            }
            guard !Task.isCancelled, self.store.digestEnabled else { return }
            self.authorizationHint = hint
            self.nextWeeklyFireDate = nextFire
        }
    }

    public func refreshAuthorizationHint() async {
        // Called on appear so the hint reflects the latest OS state even if
        // the user toggled notifications in System Settings while the app
        // was alive.
        authorizationHint = await onDigestToggle(store.digestEnabled)
        nextWeeklyFireDate = await onFetchNextFireDate()
    }

    public func sendTestNotification() async {
        testNotificationResult = .scheduling
        let result = await onSendTestNotification()
        testNotificationResult = result
    }

    public func clearTestNotificationResult() {
        testNotificationResult = .idle
    }

    // MARK: - Launch at login

    public func setLaunchAtLogin(_ enable: Bool) async {
        guard let onLaunchAtLoginToggle else { return }
        // Flip optimistically so the checkbox responds on click; the
        // SMAppService round-trip below reconciles to the real state
        // (including reverting on registration failure).
        launchAtLoginEnabled = enable
        launchAtLoginEnabled = await onLaunchAtLoginToggle(enable)
    }
}
