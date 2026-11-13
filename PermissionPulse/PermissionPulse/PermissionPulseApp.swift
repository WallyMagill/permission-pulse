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
            WindowOpeningTrampoline()
                .environment(appDelegate.viewModel)
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
                },
                onBecameVisible: { [appDelegate] in
                    appDelegate.scanScheduler?.noteBecameVisible()
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
        Window("Settings", id: "preferences") {
            PreferencesWindowView(
                onResetAllData: { [appDelegate] in
                    appDelegate.requestResetAllData()
                },
                scanInProgress: { [appDelegate] in
                    appDelegate.viewModel.scanInProgress
                },
                makeDiagnostics: { [appDelegate] in
                    await appDelegate.diagnosticsText()
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
                onRecentChangesReviewed: { [appDelegate] in
                    appDelegate.markCurrentSnapshotReviewed()
                },
                onBecameVisible: { [appDelegate] in
                    appDelegate.scanScheduler?.noteBecameVisible()
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

    let runtimeEnvironment: AppRuntimeEnvironment
    let runtimeDefaults: UserDefaults
    let appVersion: AppVersion
    let fullDiskAccessRecovery = FullDiskAccessRecovery()
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
    lazy var changeAlertCoordinator = ChangeAlertCoordinator(
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
        onChangeAlertsToggle: { [weak self] turnOn in
            await self?.changeAlertCoordinator.handleToggle(turnOn: turnOn) ?? .off
        },
        fetchLaunchAtLoginStatus: { LaunchAtLoginStatus(SMAppService.mainApp.status) },
        onLaunchAtLoginToggle: { enable in
            do {
                if enable { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                Logger(
                    subsystem: "com.wallymagill.permissionpulse",
                    category: "app-delegate"
                ).error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    )
    private var coordinator: ScanCoordinator?
    private(set) var scanScheduler: ScanScheduler?
    private var mediaCoordinator: MediaUseCoordinator?
    private(set) var snapshotStore: SnapshotStore?
    private(set) var snapshotCoordinator: SnapshotCoordinator?
    var welcomeWindow: NSWindow?
    var fullDiskAccessWindow: NSWindow?
    let fullDiskAccessPromptPresenter: (@MainActor (FullDiskAccessLoss) -> Void)?
    private let resetMessagePresenter: (@MainActor (String) -> Void)?
    private let resetOperation: (@MainActor () async -> Void)?
    let weeklyDigestScheduler: any WeeklyDigestScheduler
    private(set) var resetTask: Task<Void, Never>?
    /// Set by the snapshot coordinator when the current scan wrote a snapshot.
    private var snapshotWrite: (previous: SnapshotID?, written: SnapshotID)?

    override convenience init() {
        self.init(runtimeEnvironment: AppRuntimeEnvironment())
    }

    init(
        runtimeEnvironment: AppRuntimeEnvironment,
        resetMessagePresenter: (@MainActor (String) -> Void)? = nil,
        resetOperation: (@MainActor () async -> Void)? = nil,
        weeklyDigestScheduler: any WeeklyDigestScheduler = LiveWeeklyDigestScheduler(),
        appVersion: AppVersion = .running,
        fullDiskAccessPromptPresenter: (@MainActor (FullDiskAccessLoss) -> Void)? = nil
    ) {
        let defaults = Self.makeRuntimeDefaults(for: runtimeEnvironment)
        self.runtimeEnvironment = runtimeEnvironment
        self.runtimeDefaults = defaults
        self.appVersion = appVersion
        self.fullDiskAccessPromptPresenter = fullDiskAccessPromptPresenter
        self.viewModel = AppViewModel()
        self.preferencesStore = PreferencesStore(defaults: defaults)
        self.notificationPresentationDelegate = NotificationPresentationDelegate()
        self.dismissedDiffEntries = DismissedDiffEntryStore(defaults: defaults)
        self.dismissedStaleApps = DismissedStaleAppStore(defaults: defaults)
        self.resetMessagePresenter = resetMessagePresenter
        self.resetOperation = resetOperation
        self.weeklyDigestScheduler = weeklyDigestScheduler
        super.init()
        viewModel.dismissedDiffEntries = dismissedDiffEntries
        if runtimeEnvironment.isRunningTests {
            // Test mode skips applicationDidFinishLaunching, but reset recovery
            // still needs a real deterministic scan rather than treating
            // never-scanned availability as success.
            self.coordinator = ScanCoordinator(
                viewModel: viewModel,
                tccScanner: MockTCCScanner(),
                tccDataSource: .mock,
                launchAgentScanner: MockLaunchAgentScanner(),
                launchAgentsDataSource: .mock,
                btmScanner: MockBTMScanner(),
                btmDataSource: .mock
            )
        }
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
        Task { @MainActor [weak self] in
            guard await SingleInstanceGuard.resolve() else { return }
            self?.startRuntime()
        }
    }

    private func startRuntime() {
        // Set before anything schedules: without a willPresent delegate,
        // macOS suppresses banners while the app is frontmost, so the
        // Preferences test notification never visibly fires.
        UNUserNotificationCenter.current().delegate = notificationPresentationDelegate
        openSnapshotStore()
        viewModel.isTranslocated = AppLocation.isTranslocated(Bundle.main.bundlePath)

        coordinator = ScanCoordinator(viewModel: viewModel)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRescanIfIdle()
            self.scanScheduler = ScanScheduler(
                lastScanDate: { [weak self] in self?.viewModel.lastScanDate },
                requestScan: { [weak self] in
                    Task { await self?.rescan() }
                }
            )
            self.scanScheduler?.start()
        }

        mediaCoordinator = MediaUseCoordinator(viewModel: viewModel)
        mediaCoordinator?.start()

        if !runtimeDefaults.bool(forKey: Self.hasSeenWelcomeKey) {
            showWelcomeWindow()
        }
    }

    private func openSnapshotStore() {
        do {
            let url = try SnapshotPath.canonicalURL()
            snapshotStore = try SnapshotStore(path: url.path(percentEncoded: false))
        } catch {
            Self.logger.error(
                "SnapshotStore init failed: \(error.localizedDescription, privacy: .public)"
            )
            viewModel.snapshotStoreProblem = Self.storeProblem(for: error)
        }
        if let snapshotStore {
            installSnapshotRuntime(snapshotStore)
        }
    }

    /// Double-clicking the running app in Finder: it has no Dock icon, and
    /// its menu-bar icon may be hidden, so show the main window on Overview.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDetailWindow(route: .overview)
        return false
    }

    func showDetailWindow(route: AppRoute) {
        viewModel.pendingRoute = route
        viewModel.windowToOpen = "detail"
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !runtimeEnvironment.isRunningTests else { return }
        preferencesViewModel.refreshLaunchAtLoginStatus()
        Task { [weak self] in await self?.recheckFullDiskAccessIfReturning() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        fullDiskAccessRecovery.appResignedActive()
    }

    func rescan() async {
        guard resetTask == nil else {
            Self.logger.debug("Rescan ignored — a reset is already in progress")
            return
        }
        _ = await performRescanIfIdle()
    }

    /// The one scan path: the launch scan, every scheduled or manual rescan,
    /// and Reset's recovery scan all end here, so whatever depends on fresh
    /// results (the digest body above all) is refreshed after each scan.
    @discardableResult
    func performRescanIfIdle() async -> Bool {
        // Don't start a second scan while one is in flight (e.g. user hits
        // Refresh during the initial launch scan, or a wake and a menu open
        // land together). Concurrent scans could both see changed evidence
        // before either writes, producing duplicate snapshot rows. (R2)
        guard !viewModel.scanInProgress else {
            Self.logger.debug("Rescan ignored — a scan is already in progress")
            return false
        }
        // Nil until launch finishes (a relaunched copy may still be waiting
        // for the old process); recording this build's version or touching
        // notifications before then would act on no scan at all.
        guard let coordinator else {
            Self.logger.debug("Rescan ignored — launch has not finished")
            return false
        }
        viewModel.scanInProgress = true
        defer { viewModel.scanInProgress = false }
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
        snapshotWrite = nil
        await coordinator.rescan()
        let fullDiskAccessLoss = await classifyFullDiskAccessLoss()
        await updateSnapshotHistoryAfterScan()
        viewModel.lastScanDate = Date()
        await handleFullDiskAccessLoss(fullDiskAccessLoss)
        await postChangeAlertIfNeeded()
        _ = await weeklyDigestCoordinator.reconcileSchedule()
        return true
    }

    private func postChangeAlertIfNeeded() async {
        guard preferencesStore.changeAlertsEnabled, let write = snapshotWrite else { return }
        snapshotWrite = nil
        guard let previous = write.previous else { return }
        let changes = await snapshotCoordinator?.changes(from: previous, to: write.written)
        await changeAlertCoordinator.snapshotWritten(changes: changes)
    }

    func markCurrentSnapshotReviewed() {
        snapshotCoordinator?.markCurrentSnapshotReviewed()
    }

    static func storeProblem(for error: any Error) -> SnapshotStoreProblem {
        switch error as? SnapshotStoreOpenError {
        case .createdByNewerVersion: .createdByNewerVersion
        case .corrupt: .corrupt
        case nil: .unavailable
        }
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
        return viewModel.tccAvailability.isComplete
            && viewModel.btmAvailability.isComplete
            && viewModel.launchAgentAvailability.isComplete
    }

    func handleResetResult(_ result: ResetResult) {
        switch result {
        case .completed(scanSucceeded: false):
            Self.logger.error("Reset completed, but the fresh scan did not fully succeed")
            presentResetError(
                message: String(localized: "Data was reset, but the fresh scan didn't complete. Choose Rescan to try the scan again.")
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
        let coordinator = makeSnapshotCoordinator(store: store)
        coordinator.onSnapshotWritten = { [weak self] previous, written in
            self?.snapshotWrite = (previous, written)
        }
        snapshotCoordinator = coordinator
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
}

extension LaunchAtLoginStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered: self = .notRegistered
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}
