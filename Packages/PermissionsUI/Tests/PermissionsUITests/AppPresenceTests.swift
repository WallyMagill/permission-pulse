import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite @MainActor struct AppPresenceTests {
    private func bundleClient(_ id: String, path: String? = nil) -> AppIdentity {
        AppIdentity(bundleID: id, displayName: id, bundlePath: path.map(URL.init(fileURLWithPath:)))
    }

    @Test func unresolvedBundleIDIsMissingUnlessAParentAppIsInstalled() {
        func missing(_ app: AppIdentity) -> Bool {
            AppPresence.isMissing(app, appIsInstalled: { $0 == "com.nordvpn.macos" })
        }

        #expect(missing(bundleClient("com.jordanbaird.Ice")))
        #expect(!missing(bundleClient("com.nordvpn.macos.Shield")))
        #expect(!missing(bundleClient("us.zoom.xos", path: "/Applications/zoom.us.app")))
    }

    @Test func pathClientIsMissingOnlyWhenTheFileSystemSaysSo() throws {
        let gone = AppIdentity(bundleID: "", displayName: "claude",
                               bundlePath: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/claude"))
        let present = AppIdentity(bundleID: "", displayName: "sh", bundlePath: URL(fileURLWithPath: "/bin/sh"))

        #expect(AppPresence.isMissing(gone))
        #expect(!AppPresence.isMissing(present))
    }

    @Test func unreadablePathIsNotCalledMissing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pp-presence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let hidden = AppIdentity(bundleID: "", displayName: "tool", bundlePath: dir.appendingPathComponent("tool"))
        // Root ignores the mode bits, so the check is only meaningful as a user.
        guard getuid() != 0 else { return }
        #expect(!AppPresence.isMissing(hidden))
    }
}
