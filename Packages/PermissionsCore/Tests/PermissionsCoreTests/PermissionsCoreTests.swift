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

@Suite struct ScannerErrorLocalizationTests {
    @Test func permissionDeniedExposesReason() {
        let error = ScannerError.permissionDenied(reason: "Grant Full Disk Access")
        #expect(error.localizedDescription == "Grant Full Disk Access")
    }

    @Test func schemaMismatchExposesDetail() {
        let error = ScannerError.schemaMismatch(detail: "missing column auth_value")
        #expect(error.localizedDescription == "missing column auth_value")
    }

    @Test func unsupportedOnThisOSExposesDetail() {
        let error = ScannerError.unsupportedOnThisOS(detail: "access table not found")
        #expect(error.localizedDescription == "access table not found")
    }
}
