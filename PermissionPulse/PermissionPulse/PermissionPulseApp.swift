import AppKit
import OSLog
import ServiceManagement
import SwiftUI
import UserNotifications
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

    let viewModel = AppViewModel()
    let preferencesStore = PreferencesStore()
    // UNUserNotificationCenter.delegate is weak — must be retained here.
    private let notificationPresentationDelegate = NotificationPresentationDelegate()
    let dismissedDiffEntries = DismissedDiffEntryStore()
    let dismissedStaleApps = DismissedStaleAppStore()
    lazy var weeklyDigestCoordinator = WeeklyDigestCoordinator(
        viewModel: viewModel,
        preferencesStore: preferencesStore
    )
    lazy var preferencesViewModel = PreferencesViewModel(
        store: preferencesStore,
        onDigestToggle: { [weak self] turnOn in
            guard let self else { return .disabled }
            let result = await self.weeklyDigestCoordinator.handleAuthorizationToggle(turnOn: turnOn)
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

    private static func hint(
        for result: WeeklyDigestCoordinator.AuthorizationResult
    ) -> PreferencesViewModel.AuthorizationHint {
        switch result {
        case .scheduled:                  return .scheduled(nextFireDescription: "")
        case .deniedNeedsSystemSettings:  return .denied
        case .disabled:                   return .disabled
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
        guard !AppRuntimeEnvironment().isRunningTests else {
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
            snapshotCoordinator = SnapshotCoordinator(
                viewModel: viewModel,
                store: snapshotStore,
                snapshotRetentionDays: preferencesStore.snapshotRetentionDays,
                staleThresholdDays: preferencesStore.staleThresholdDays,
                dismissedStaleApps: dismissedStaleApps
            )
        }

        coordinator = ScanCoordinator(viewModel: viewModel)
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
        Task { @MainActor in
            viewModel.scanInProgress = true
            await coordinator?.runScan()
            await snapshotCoordinator?.onScanCompleted()
            viewModel.lastScanDate = Date()
            viewModel.scanInProgress = false
            await weeklyDigestCoordinator.reconcileSchedule()
        }

        mediaCoordinator = MediaUseCoordinator(viewModel: viewModel)
        mediaCoordinator?.start()

        if !UserDefaults.standard.bool(forKey: Self.hasSeenWelcomeKey) {
            showWelcomeWindow()
        }
    }

    func rescan() async {
        // Don't start a second scan while one is in flight (e.g. user hits
        // Refresh during the initial launch scan). Concurrent scans can both
        // pass SnapshotCoordinator's once-per-day write guard before the first
        // persists lastSnapshotDate, producing duplicate snapshot rows. (R2)
        guard !viewModel.scanInProgress else {
            Self.logger.debug("Rescan ignored — a scan is already in progress")
            return
        }
        viewModel.scanInProgress = true
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
        await coordinator?.rescan()
        await snapshotCoordinator?.onScanCompleted()
        viewModel.lastScanDate = Date()
        viewModel.scanInProgress = false
    }

    func markCurrentSnapshotReviewed() {
        snapshotCoordinator?.markCurrentSnapshotReviewed()
    }

    func requestResetAllData() {
        Task { await performReset() }
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
        let service = ResetAllDataService(
            viewModel: viewModel,
            snapshotPathURL: url,
            onSnapshotStoreReinit: { [weak self] newStore in
                self?.snapshotStore = newStore
                if let self {
                    self.snapshotCoordinator = SnapshotCoordinator(
                        viewModel: self.viewModel,
                        store: newStore,
                        snapshotRetentionDays: self.preferencesStore.snapshotRetentionDays,
                        staleThresholdDays: self.preferencesStore.staleThresholdDays,
                        dismissedStaleApps: self.dismissedStaleApps
                    )
                }
            },
            weeklyDigestCoordinator: weeklyDigestCoordinator,
            defaults: .standard,
            rescan: { [weak self] in
                await self?.rescan()
                await self?.weeklyDigestCoordinator.reconcileSchedule()
            }
        )
        let reinitSucceeded = await service.reset()
        if !reinitSucceeded {
            // Don't let scans write to a store we couldn't recreate.
            snapshotStore = nil
            snapshotCoordinator = nil
            viewModel.snapshotStoreUnavailable = true
            presentResetError(
                message: String(localized: "Data was cleared, but Permission Pulse couldn't recreate its database. Restart the app to recover.")
            )
        }
    }

    // AppKit: NSAlert is the idiomatic one-shot modal error dialog; SwiftUI has
    // no equivalent for an app-level (non-window-hosted) modal here.
    private func presentResetError(message: String) {
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
