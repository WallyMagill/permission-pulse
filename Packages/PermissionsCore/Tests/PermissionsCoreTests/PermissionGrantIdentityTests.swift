import Foundation
import Testing
@testable import PermissionsCore

@Suite struct PermissionGrantIdentityTests {
    private func grant(bundleID: String, path: String?) -> PermissionGrant {
        PermissionGrant(
            service: .filesAndFolders,
            app: AppIdentity(
                bundleID: bundleID,
                displayName: "X",
                bundlePath: path.map { URL(fileURLWithPath: $0) }
            ),
            lastModified: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func bundleIDGrantUsesBundleIDAsAppKey() {
        let g = grant(bundleID: "com.example.app", path: "/Applications/Example.app")
        #expect(g.appKey == "com.example.app")
        #expect(g.identityKey == "filesAndFolders|com.example.app|")
        #expect(g.id == g.identityKey)
    }

    @Test func pathOnlyGrantsWithDistinctPathsDoNotCollapse() {
        let a = grant(bundleID: "", path: "/usr/local/bin/tool-a")
        let b = grant(bundleID: "", path: "/usr/local/bin/tool-b")
        #expect(a.appKey == "/usr/local/bin/tool-a")
        #expect(a.identityKey != b.identityKey)
    }

    @Test func bundleIdentityUsesPrefixedBundleKeyWithPrecedenceOverPath() {
        let app = AppIdentity(
            bundleID: "com.example.app",
            displayName: "App",
            bundlePath: URL(fileURLWithPath: "/Applications/App.app")
        )

        #expect(app.stableKey == "bundle:com.example.app")
    }

    @Test func whitespaceBundleIdentityIsNonemptyAndKeepsBundlePrecedence() {
        let app = AppIdentity(
            bundleID: "   ",
            displayName: "App",
            bundlePath: URL(fileURLWithPath: "/Applications/App.app")
        )

        #expect(app.stableKey == "bundle:   ")
    }

    @Test func pathOnlyIdentityUsesStandardizedNonPercentEncodedPathKey() {
        let app = AppIdentity(
            bundleID: "",
            displayName: "Tool",
            bundlePath: URL(fileURLWithPath: "/Applications/Sub/../My Tool.app")
        )

        #expect(app.stableKey == "path:/Applications/My Tool.app")
    }

    @Test func identityWithoutBundleOrPathHasNoStableKey() {
        #expect(AppIdentity(bundleID: "", displayName: "Unknown").stableKey == nil)
    }

    @Test func identityWithEmptyFileURLPathHasNoStableKey() throws {
        let emptyFileURL = try #require(URL(string: "file:"))
        let app = AppIdentity(bundleID: "", displayName: "Unknown", bundlePath: emptyFileURL)

        #expect(app.stableKey == nil)
    }

    @Test func stableIdentityDoesNotChangePersistedPermissionGrantKeys() {
        let bundleGrant = grant(bundleID: "com.example.app", path: "/Applications/Example.app")
        let pathGrant = grant(bundleID: "", path: "/Applications/Path Only.app")

        #expect(bundleGrant.app.stableKey == "bundle:com.example.app")
        #expect(bundleGrant.appKey == "com.example.app")
        #expect(bundleGrant.identityKey == "filesAndFolders|com.example.app|")
        #expect(pathGrant.app.stableKey == "path:/Applications/Path Only.app")
        #expect(pathGrant.appKey == "/Applications/Path Only.app")
        #expect(pathGrant.identityKey == "filesAndFolders|/Applications/Path Only.app|")
    }
}
