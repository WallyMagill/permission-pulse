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

        WindowGroup("Preferences", id: "preferences") {
            PreferencesWindowView()
                .environment(appDelegate.preferencesViewModel)
        }
        .windowResizability(.contentSize)

        WindowGroup("Permission Pulse", id: "detail") {
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
    lazy var preferencesViewModel = PreferencesViewModel(store: preferencesStore)
    private var coordinator: ScanCoordinator?
    private var mediaCoordinator: MediaUseCoordinator?
    private var snapshotStore: SnapshotStore?
    private var snapshotCoordinator: SnapshotCoordinator?
    private var welcomeWindow: NSWindow?

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
        Task { @MainActor in
            await coordinator?.runScan()
            await snapshotCoordinator?.onScanCompleted()
        }

        mediaCoordinator = MediaUseCoordinator(viewModel: viewModel)
        mediaCoordinator?.start()

        if !UserDefaults.standard.bool(forKey: Self.hasSeenWelcomeKey) {
            showWelcomeWindow()
        }
    }

    func rescan() async {
        await coordinator?.rescan()
        await snapshotCoordinator?.onScanCompleted()
    }

    func markCurrentSnapshotReviewed() {
        snapshotCoordinator?.markCurrentSnapshotReviewed()
    }

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
