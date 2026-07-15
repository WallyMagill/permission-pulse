import AppKit
import OSLog
import ServiceManagement
import SwiftUI
import UserNotifications
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI

@main
struct PermissionPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings trampoline — works around the Tahoe MenuBarExtra/openSettings
        // regression by routing through a regular window. Must be declared
        // FIRST (before any Settings scene or other WindowGroup). See
        // docs/03-architecture.md.
        WindowGroup(id: "settings-trampoline") {
            EmptyView().frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)

        MenuBarExtra {
            MenuBarContentView(
                onShowWelcome: { [appDelegate] in
                    appDelegate.showWelcomeWindow()
                },
                onRescan: { [appDelegate] in
                    Task { await appDelegate.rescan() }
                }
            )
                .environment(appDelegate.viewModel)
        } label: {
            Image(systemName: appDelegate.viewModel.menuBarSymbolName)
                // NOTE: SwiftUI may not reliably bridge .accessibilityLabel from a
                // MenuBarExtra label down to the NSStatusBarButton that VoiceOver
                // reads on macOS. This is the correct declarative place for it;
                // VERIFY manually with VoiceOver on Tahoe. If VoiceOver reads the
                // SF Symbol name instead, set NSStatusBarButton.accessibilityLabel
                // directly via an AppKit bridge in AppDelegate. (A1)
                .accessibilityLabel(appDelegate.viewModel.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)

        // Singleton scenes — Window (not WindowGroup) so openWindow(id:) reuses
        // the existing window instead of stacking a new one each click.
        Window("Preferences", id: "preferences") {
            PreferencesWindowView(
                onResetAllData: { [appDelegate] in
                    appDelegate.requestResetAllData()
                },
                scanInProgress: { [appDelegate] in
                    appDelegate.viewModel.scanInProgress
                }
            )
            .environment(appDelegate.preferencesViewModel)
            .environment(appDelegate.viewModel)
        }
        .windowResizability(.contentSize)

        Window("Permission Pulse", id: "detail") {
            DetailWindowView(
                onRefresh: { [appDelegate] in
                    await appDelegate.rescan()
                },
                onWhatChangedSelected: { [appDelegate] in
                    appDelegate.markCurrentSnapshotReviewed()
                }
            )
            .environment(appDelegate.viewModel)
            .environment(appDelegate.dismissedDiffEntries)
            .environment(appDelegate.dismissedStaleApps)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "app-delegate"
    )

    static let hasSeenWelcomeKey = "com.wallymagill.permissionpulse.hasSeenWelcome"
    static let testDefaultsSuiteName =
        "com.wallymagill.permissionpulse.test-host.\(ProcessInfo.processInfo.processIdentifier)"

    private let runtimeEnvironment: AppRuntimeEnvironment
    private let runtimeDefaults: UserDefaults
    let viewModel: AppViewModel
    let preferencesStore: PreferencesStore
    // UNUserNotificationCenter.delegate is weak — must be retained here.
    private let notificationPresentationDelegate: NotificationPresentationDelegate
    let dismissedDiffEntries: DismissedDiffEntryStore
    let dismissedStaleApps: DismissedStaleAppStore
    lazy var weeklyDigestCoordinator = WeeklyDigestCoordinator(
        viewModel: viewModel,
        preferencesStore: preferencesStore,
        scheduler: weeklyDigestScheduler
    )
    lazy var preferencesViewModel = PreferencesViewModel(
        store: preferencesStore,
        onDigestToggle: { [weak self] turnOn in
            guard let self else { return .disabled }
            let result = await self.weeklyDigestCoordinator.handleAuthorizationToggle(turnOn: turnOn)
            return Self.hint(for: result)
        },
        onDigestScheduleChange: { [weak self] in
            guard let self else { return .disabled }
            let result = await self.weeklyDigestCoordinator.reconcileSchedule()
            return Self.hint(for: result)
        },
        onSendTestNotification: { [weak self] in
            guard let self else { return .idle }
            let result = await self.weeklyDigestCoordinator.sendTestNotification()
            return Self.testResult(for: result)
        },
        onFetchNextFireDate: { [weak self] in
            await self?.weeklyDigestCoordinator.nextWeeklyFireDate()
        },
        initialLaunchAtLogin: SMAppService.mainApp.status == .enabled,
        onLaunchAtLoginToggle: { enable in
            do {
                if enable { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                Logger(
                    subsystem: "com.wallymagill.permissionpulse",
                    category: "app-delegate"
                ).error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
            }
            return SMAppService.mainApp.status == .enabled
        }
    )
    private var coordinator: ScanCoordinator?
    private var mediaCoordinator: MediaUseCoordinator?
    private var snapshotStore: SnapshotStore?
    private var snapshotCoordinator: SnapshotCoordinator?
    private var welcomeWindow: NSWindow?
    private let resetMessagePresenter: (@MainActor (String) -> Void)?
    private let resetOperation: (@MainActor () async -> Void)?
    private let weeklyDigestScheduler: any WeeklyDigestScheduler
    private var resetTask: Task<Void, Never>?

    override convenience init() {
        self.init(runtimeEnvironment: AppRuntimeEnvironment())
    }

    init(
        runtimeEnvironment: AppRuntimeEnvironment,
        resetMessagePresenter: (@MainActor (String) -> Void)? = nil,
        resetOperation: (@MainActor () async -> Void)? = nil,
        weeklyDigestScheduler: any WeeklyDigestScheduler = LiveWeeklyDigestScheduler()
    ) {
        let defaults = Self.makeRuntimeDefaults(for: runtimeEnvironment)
        self.runtimeEnvironment = runtimeEnvironment
        self.runtimeDefaults = defaults
        self.viewModel = AppViewModel()
        self.preferencesStore = PreferencesStore(defaults: defaults)
        self.notificationPresentationDelegate = NotificationPresentationDelegate()
        self.dismissedDiffEntries = DismissedDiffEntryStore(defaults: defaults)
        self.dismissedStaleApps = DismissedStaleAppStore(defaults: defaults)
        self.resetMessagePresenter = resetMessagePresenter
        self.resetOperation = resetOperation
        self.weeklyDigestScheduler = weeklyDigestScheduler
        super.init()
    }

    private static func makeRuntimeDefaults(
        for runtimeEnvironment: AppRuntimeEnvironment
    ) -> UserDefaults {
        guard runtimeEnvironment.isRunningTests else { return .standard }

        let suiteName = testDefaultsSuiteName
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func hint(
        for result: WeeklyDigestCoordinator.AuthorizationResult
    ) -> PreferencesViewModel.AuthorizationHint {
        switch result {
        case .scheduled:                  return .scheduled(nextFireDescription: "")
        case .deniedNeedsSystemSettings:  return .denied
        case .disabled:                   return .disabled
        }
    }

    private static func hint(
        for result: WeeklyDigestCoordinator.ScheduleResult
    ) -> PreferencesViewModel.AuthorizationHint {
        switch result {
        case .disabled:              return .disabled
        case .scheduled:             return .scheduled(nextFireDescription: "")
        case .notAuthorized:         return .denied
        case .failed(let message):   return .failed(message)
        }
    }

    private static func testResult(
        for result: WeeklyDigestCoordinator.TestSendResult
    ) -> PreferencesViewModel.TestNotificationResult {
        switch result {
        case .scheduled(let seconds):  return .scheduled(in: seconds)
        case .notAuthorized:           return .notAuthorized
        case .failed(let message):     return .failed(message)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !runtimeEnvironment.isRunningTests else {
            Self.logger.debug("Skipping production launch services in test mode")
            return
        }

        // Set before anything schedules: without a willPresent delegate,
        // macOS suppresses banners while the app is frontmost, so the
        // Preferences test notification never visibly fires.
        UNUserNotificationCenter.current().delegate = notificationPresentationDelegate

        do {
            let url = try SnapshotPath.canonicalURL()
            snapshotStore = try SnapshotStore(path: url.path(percentEncoded: false))
        } catch {
            Self.logger.error(
                "SnapshotStore init failed: \(error.localizedDescription, privacy: .public)"
            )
            viewModel.snapshotStoreUnavailable = true
        }
        if let snapshotStore {
            installSnapshotRuntime(snapshotStore)
        }

        coordinator = ScanCoordinator(viewModel: viewModel)
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
        Task { @MainActor in
            viewModel.scanInProgress = true
            await coordinator?.runScan()
            await updateSnapshotHistoryAfterScan()
            viewModel.lastScanDate = Date()
            viewModel.scanInProgress = false
            _ = await weeklyDigestCoordinator.reconcileSchedule()
        }

        mediaCoordinator = MediaUseCoordinator(viewModel: viewModel)
        mediaCoordinator?.start()

        if !runtimeDefaults.bool(forKey: Self.hasSeenWelcomeKey) {
            showWelcomeWindow()
        }
    }

    func rescan() async {
        guard resetTask == nil else {
            Self.logger.debug("Rescan ignored — a reset is already in progress")
            return
        }
        _ = await performRescanIfIdle()
    }

    @discardableResult
    private func performRescanIfIdle() async -> Bool {
        // Don't start a second scan while one is in flight (e.g. user hits
        // Refresh during the initial launch scan). Concurrent scans can both
        // pass SnapshotCoordinator's once-per-day write guard before the first
        // persists lastSnapshotDate, producing duplicate snapshot rows. (R2)
        guard !viewModel.scanInProgress else {
            Self.logger.debug("Rescan ignored — a scan is already in progress")
            return false
        }
        viewModel.scanInProgress = true
        defer { viewModel.scanInProgress = false }
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
        await coordinator?.rescan()
        await updateSnapshotHistoryAfterScan()
        viewModel.lastScanDate = Date()
        return true
    }

    func markCurrentSnapshotReviewed() {
        snapshotCoordinator?.markCurrentSnapshotReviewed()
    }

    func requestResetAllData() {
        guard !viewModel.scanInProgress else {
            Self.logger.debug("Reset request ignored — a scan is already in progress")
            return
        }
        guard resetTask == nil else {
            Self.logger.debug("Reset request ignored — a reset is already in progress")
            return
        }
        resetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.resetTask = nil }
            if let resetOperation = self.resetOperation {
                await resetOperation()
            } else {
                await self.performReset()
            }
        }
    }

    func waitForResetCompletion() async {
        await resetTask?.value
    }

    private func performReset() async {
        let url: URL
        do {
            url = try SnapshotPath.canonicalURL()
        } catch {
            Self.logger.error("Reset aborted — cannot resolve data path: \(error.localizedDescription, privacy: .public)")
            presentResetError(
                message: String(localized: "Reset failed: Permission Pulse couldn't locate its data folder.")
            )
            return
        }
        _ = await performReset(at: url, fileManager: FileManager.default)
    }

    @discardableResult
    func performReset(
        at url: URL,
        fileManager: any ResetFileManaging
    ) async -> ResetResult {
        await performReset(
            at: url,
            fileManager: fileManager,
            rescan: { [weak self] in
                guard let self else { return false }
                return await self.performResetRecoveryScan()
            }
        )
    }

    @discardableResult
    func performReset(
        at url: URL,
        fileManager: any ResetFileManaging,
        rescan: @MainActor @escaping () async -> Bool
    ) async -> ResetResult {
        let service = ResetAllDataService(
            viewModel: viewModel,
            snapshotPathURL: url,
            releaseSnapshotStore: { [weak self] in
                self?.snapshotCoordinator = nil
                self?.snapshotStore = nil
            },
            onSnapshotStoreReinit: { [weak self] newStore in
                self?.installSnapshotRuntime(newStore)
            },
            weeklyDigestCoordinator: weeklyDigestCoordinator,
            preferencesStore: preferencesStore,
            dismissedDiffEntries: dismissedDiffEntries,
            dismissedStaleApps: dismissedStaleApps,
            fileManager: fileManager,
            defaults: runtimeDefaults,
            rescan: rescan
        )
        let result = await service.reset()
        handleResetResult(result)
        return result
    }

    private func performResetRecoveryScan() async -> Bool {
        guard await performRescanIfIdle() else { return false }
        return viewModel.tccScanError == nil
            && viewModel.btmScanError == nil
            && viewModel.launchAgentScanError == nil
    }

    func handleResetResult(_ result: ResetResult) {
        switch result {
        case .completed(scanSucceeded: false):
            Self.logger.error("Reset completed, but the fresh scan did not fully succeed")
            presentResetError(
                message: String(localized: "Data was reset, but the fresh scan didn't complete. Choose Refresh to try the scan again.")
            )
        case .completed(scanSucceeded: true):
            break
        case .failed(let phase, let message):
            snapshotStore = nil
            snapshotCoordinator = nil
            viewModel.snapshotStoreUnavailable = true
            Self.logger.error(
                "Reset failed in phase \(String(describing: phase), privacy: .public): \(message, privacy: .public)"
            )
            presentResetError(message: Self.resetFailureMessage(for: phase))
        }
    }

    private func makeSnapshotCoordinator(store: SnapshotStore) -> SnapshotCoordinator {
        SnapshotCoordinator(
            viewModel: viewModel,
            store: store,
            defaults: runtimeDefaults,
            snapshotRetentionDays: { [weak preferencesStore] in
                preferencesStore?.snapshotRetentionDays
                    ?? SnapshotCoordinator.defaultSnapshotRetentionDays
            },
            staleThresholdDays: { [weak preferencesStore] in
                preferencesStore?.staleThresholdDays
                    ?? SnapshotCoordinator.defaultStaleThresholdDays
            },
            dismissedStaleApps: dismissedStaleApps
        )
    }

    var hasSnapshotRuntime: Bool {
        snapshotStore != nil && snapshotCoordinator != nil
    }

    var snapshotRuntimeReferences: (hasStore: Bool, hasCoordinator: Bool) {
        (snapshotStore != nil, snapshotCoordinator != nil)
    }

    func installSnapshotRuntime(_ store: SnapshotStore) {
        snapshotStore = store
        snapshotCoordinator = makeSnapshotCoordinator(store: store)
    }

    func updateSnapshotHistoryAfterScan() async {
        await snapshotCoordinator?.onScanCompleted()
    }

    private static func resetFailureMessage(for phase: ResetPhase) -> String {
        switch phase {
        case .deleteHistory:
            return String(localized: "Permission Pulse couldn't remove its existing history. Restart the app, then try Reset All Data again.")
        case .recreateHistory:
            return String(localized: "Data was cleared, but Permission Pulse couldn't recreate its database. Restart the app to recover.")
        case .cancelNotifications, .releaseHistory, .resetLiveStores, .clearDefaults, .rescan:
            return String(localized: "Reset All Data couldn't finish. Restart Permission Pulse, then try again.")
        }
    }

    // AppKit: NSAlert is the idiomatic one-shot modal error dialog; SwiftUI has
    // no equivalent for an app-level (non-window-hosted) modal here.
    private func presentResetError(message: String) {
        if let resetMessagePresenter {
            resetMessagePresenter(message)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Reset Permission Pulse")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        // Blocking modal is intentional: the user must acknowledge the failure
        // before any subsequent scan begins.
        alert.runModal()
    }

    func showWelcomeWindow() {
        // Singleton: re-front the existing window instead of orphaning it. The
        // menu-bar "Welcome & About" entry can call this repeatedly. (U5)
        if let welcomeWindow {
            welcomeWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = WelcomeWindowView(onDismiss: { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.hasSeenWelcomeKey)
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome")
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = window
    }
}
