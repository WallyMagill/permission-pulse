import Testing
import Foundation
@testable import PermissionsCore

@Suite("PermissionRiskSummary.line")
struct PermissionRiskSummaryTests {
    private func grant(_ service: PermissionService, bundleID: String) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: nil),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil,
            authValue: 2
        )
    }

    @Test("counts distinct apps per surfaced high-risk service")
    func countsDistinctApps() {
        let grants = [
            grant(.fullDiskAccess, bundleID: "a"),
            grant(.fullDiskAccess, bundleID: "b"),
            grant(.inputMonitoring, bundleID: "a"),
            grant(.camera, bundleID: "c"),
        ]
        #expect(PermissionRiskSummary.line(for: grants) == "2 Full Disk Access · 1 Input Monitoring")
    }

    @Test("nil when no surfaced high-risk grants")
    func nilWhenNone() {
        #expect(PermissionRiskSummary.line(for: [grant(.camera, bundleID: "c")]) == nil)
        #expect(PermissionRiskSummary.line(for: []) == nil)
    }

    @Test("de-duplicates the same app holding the same service twice")
    func dedupesSameApp() {
        let grants = [grant(.fullDiskAccess, bundleID: "a"), grant(.fullDiskAccess, bundleID: "a")]
        #expect(PermissionRiskSummary.line(for: grants) == "1 Full Disk Access")
    }
}
