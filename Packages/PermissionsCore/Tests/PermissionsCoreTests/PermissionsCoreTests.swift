import Testing
import Foundation
@testable import PermissionsCore

@Suite struct PermissionsCoreSmokeTests {
    @Test func permissionServiceHasAllExpectedCases() {
        #expect(PermissionService.allCases.count == 16)
    }

    @Test func permissionServiceDisplayNamesAreNonEmpty() {
        for service in PermissionService.allCases {
            #expect(!service.displayName.isEmpty)
        }
    }

    @Test func appIdentityEqualityIsByValue() {
        let a = AppIdentity(bundleID: "com.example.foo", displayName: "Foo")
        let b = AppIdentity(bundleID: "com.example.foo", displayName: "Foo")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func launchAgentSourceDirectoryHasThreeCases() {
        #expect(LaunchAgentItem.SourceDirectory.allCases.count == 3)
    }

    @Test func launchAgentSourceDirectoryPathsAreUnique() {
        let paths = LaunchAgentItem.SourceDirectory.allCases.map(\.path)
        #expect(Set(paths).count == paths.count)
    }
}
