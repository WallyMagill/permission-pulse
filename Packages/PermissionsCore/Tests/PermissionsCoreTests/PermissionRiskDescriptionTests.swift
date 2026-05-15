import Foundation
import Testing
@testable import PermissionsCore

@Suite struct PermissionRiskDescriptionTests {
    @Test func everyServiceHasANonEmptyRiskDescription() {
        for service in PermissionService.allCases {
            let description = service.riskDescription
            #expect(!description.isEmpty, "\(service) has empty riskDescription")
        }
    }

    @Test func riskDescriptionsAreSubstantive() {
        // Floor at ~60 chars catches accidental stubs like "TODO" while still
        // being permissive on translated locales. Two short sentences clear
        // 60 easily.
        for service in PermissionService.allCases {
            let count = service.riskDescription.count
            #expect(count >= 60, "\(service) riskDescription only \(count) chars")
        }
    }

    @Test func riskDescriptionsAreDistinct() {
        // Two services pointing at the same copy is almost always a paste
        // error. Catch it early.
        let descriptions = PermissionService.allCases.map(\.riskDescription)
        let unique = Set(descriptions)
        #expect(unique.count == descriptions.count, "duplicate risk descriptions detected")
    }
}
