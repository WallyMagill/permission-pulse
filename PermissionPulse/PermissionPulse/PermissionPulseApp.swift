import AppKit
import SwiftUI
import PermissionsUI

@main
struct PermissionPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = AppViewModel()
    @State private var coordinator: ScanCoordinator?

    var body: some Scene {
        // Settings trampoline — works around the Tahoe MenuBarExtra/openSettings
        // regression by routing through a regular window. Must be declared
        // before any Settings scene. See docs/03-architecture.md.
        WindowGroup(id: "settings-trampoline") {
            EmptyView().frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)

        MenuBarExtra("Permission Pulse", systemImage: "shield.lefthalf.filled") {
            MenuBarContentView()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Permission Pulse", id: "detail") {
            DetailWindowView(onRefresh: { [coordinator] in
                await coordinator?.rescan()
            })
                .environment(viewModel)
                .task {
                    if coordinator == nil {
                        coordinator = ScanCoordinator(viewModel: viewModel)
                    }
                    await coordinator?.runScan()
                }
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let hasSeenWelcomeKey = "com.wallymagill.permissionpulse.hasSeenWelcome"
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: Self.hasSeenWelcomeKey) {
            showWelcomeWindow()
        }
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
