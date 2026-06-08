import AppKit
import OSLog
import SwiftUI
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
            MenuBarContentView()
                .environment(appDelegate.viewModel)
        } label: {
            Image(systemName: appDelegate.viewModel.menuBarSymbolName)
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
        do {
            let url = try SnapshotPath.canonicalURL()
            snapshotStore = try SnapshotStore(path: url.path(percentEncoded: false))
        } catch {
            Self.logger.error(
                "SnapshotStore init failed: \(error.localizedDescription, privacy: .public)"
            )
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
        viewModel.scanInProgress = true
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
        await coordinator?.rescan()
        await snapshotCoordinator?.onScanCompleted()
        viewModel.scanInProgress = false
    }

    func markCurrentSnapshotReviewed() {
        snapshotCoordinator?.markCurrentSnapshotReviewed()
    }

    func requestResetAllData() {
        let sheet = ResetConfirmationSheet(
            onCancel: { [weak self] in
                self?.resetConfirmationWindow?.close()
                self?.resetConfirmationWindow = nil
            },
            onConfirm: { [weak self] in
                guard let self else { return }
                self.resetConfirmationWindow?.close()
                self.resetConfirmationWindow = nil
                Task { @MainActor in await self.performReset() }
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Reset Permission Pulse")
        window.contentView = NSHostingView(rootView: sheet)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        resetConfirmationWindow = window
    }

    private func performReset() async {
        guard let url = try? SnapshotPath.canonicalURL() else { return }
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
        await service.reset()
    }

    private var resetConfirmationWindow: NSWindow?

    private func showWelcomeWindow() {
        let view = WelcomeWindowView(onDismiss: { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.hasSeenWelcomeKey)
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
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
