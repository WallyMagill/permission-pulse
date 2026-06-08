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
}
