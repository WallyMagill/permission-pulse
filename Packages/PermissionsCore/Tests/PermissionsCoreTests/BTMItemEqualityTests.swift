import Foundation
import Testing
@testable import PermissionsCore

@Suite struct BTMItemEqualityTests {
    // Helper with every field defaulted so each test varies exactly one.
    private func make(
        identifier: String = "id",
        name: String = "name",
        developerName: String? = "dev",
        bundleIdentifier: String? = "bundle",
        teamIdentifier: String? = "team",
        type: BTMItem.ItemType = .app,
        disposition: BTMItem.Disposition = .enabled,
        dispositionRaw: Int = 1,
        scope: BTMItem.Scope = .system,
        modificationDate: Date = Date(timeIntervalSince1970: 0),
        parentIdentifier: String? = "parent"
    ) -> BTMItem {
        BTMItem(
            identifier: identifier, name: name, developerName: developerName,
            bundleIdentifier: bundleIdentifier, teamIdentifier: teamIdentifier,
            type: type, disposition: disposition, dispositionRaw: dispositionRaw,
            scope: scope, modificationDate: modificationDate, parentIdentifier: parentIdentifier
        )
    }

    // Guards the hand-written ==: each non-raw field must participate. If a future
    // field is added to BTMItem but omitted from ==, the corresponding line here
    // (added per the BTMItem.swift IMPORTANT note) will fail.
    @Test func eachNonRawFieldParticipatesInEquality() {
        let base = make()
        #expect(make(identifier: "other") != base)
        #expect(make(name: "other") != base)
        #expect(make(developerName: "other") != base)
        #expect(make(bundleIdentifier: "other") != base)
        #expect(make(teamIdentifier: "other") != base)
        #expect(make(type: .legacyDaemon) != base)
        #expect(make(disposition: .disabled) != base)
        #expect(make(scope: .user) != base)
        #expect(make(modificationDate: Date(timeIntervalSince1970: 999)) != base)
        #expect(make(parentIdentifier: "other") != base)
    }

    @Test func dispositionRawIsExcludedFromEqualityAndHash() {
        let a = make(dispositionRaw: 5)
        let b = make(dispositionRaw: 9)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
