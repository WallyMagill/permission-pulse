// AppKit: SwiftUI has no API to activate the app or order a window to the
// front when the request comes from the background (a reopen event, a
// notification click, the delegate's own windows).
import AppKit

@MainActor
public enum WindowActivation {
    /// On macOS 14 and later `activate(ignoringOtherApps:)` no longer forces
    /// activation, so also order the window front regardless of whether the
    /// system grants it.
    public static func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// The window a SwiftUI scene with this id opened, if it is open.
    public static func bringToFront(sceneID: String) {
        NSApp.activate()
        let window = NSApp.windows.first { window in
            guard let identifier = window.identifier?.rawValue else { return false }
            return identifier == sceneID || identifier.hasPrefix("\(sceneID)-")
        }
        if let window { bringToFront(window) }
    }
}
