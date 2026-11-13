import AppKit
import SwiftUI
import PermissionsUI

// AppKit: the Welcome and Full Disk Access windows are one-shot dialogs the
// delegate opens itself, outside the SwiftUI scene graph.
extension AppDelegate: NSWindowDelegate {
    func showWelcomeWindow() {
        // Singleton: re-front the existing window instead of orphaning it. The
        // menu-bar "Welcome Tour" entry can call this repeatedly. (U5)
        if let welcomeWindow {
            welcomeWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = WelcomeWindowView(
            recovery: fullDiskAccessRecovery,
            showsSystemLevelOnlyNote: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
            onOpenedSettings: { [weak self] in
                // The user is on their way; a reopen must not show Welcome again.
                self?.runtimeDefaults.set(true, forKey: Self.hasSeenWelcomeKey)
            },
            onDismiss: welcomeDismissAction()
        )
        welcomeWindow = presentWindow(
            title: String(localized: "Welcome"),
            size: NSSize(width: 480, height: 520),
            rootView: view
        )
    }

    func welcomeDismissAction() -> () -> Void {
        { [weak self] in
            guard let self else { return }
            self.runtimeDefaults.set(true, forKey: Self.hasSeenWelcomeKey)
            self.welcomeWindow?.close()
            self.welcomeWindow = nil
        }
    }

    func presentWindow<Content: View>(title: String, size: NSSize, rootView: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === welcomeWindow { welcomeWindow = nil }
        if window === fullDiskAccessWindow { fullDiskAccessWindow = nil }
        if welcomeWindow == nil && fullDiskAccessWindow == nil {
            fullDiskAccessRecovery.end()
        }
    }
}
