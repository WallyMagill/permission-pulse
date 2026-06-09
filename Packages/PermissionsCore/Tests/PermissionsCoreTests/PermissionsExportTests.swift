import Testing
import Foundation
@testable import PermissionsCore

@Suite("PermissionsExport")
struct PermissionsExportTests {
    private var sampleReport: ExportReport {
        let app = AppIdentity(bundleID: "com.foo.bar", displayName: "Foo", bundlePath: nil)
        let grant = PermissionGrant(
            service: .camera, app: app,
            lastModified: Date(timeIntervalSince1970: 1_700_000_000),
            automationTarget: nil, authValue: 2
        )
        return PermissionsExport.report(
            grants: [grant], launchAgents: [], btmItems: [], staleApps: [],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test("JSON encodes ISO-8601 dates and includes the grant")
    func jsonContainsGrant() throws {
        let data = try PermissionsExport.makeJSON(report: sampleReport)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"appName\" : \"Foo\""))
        #expect(text.contains("\"serviceKey\" : \"camera\""))
        #expect(text.contains("2023-11-14"))
    }

    @Test("JSON round-trips back to an equal report")
    func jsonRoundTrips() throws {
        let data = try PermissionsExport.makeJSON(report: sampleReport)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportReport.self, from: data)
        #expect(decoded == sampleReport)
    }

    @Test("Markdown has section headers and the app name")
    func markdownStructure() {
        let md = PermissionsExport.makeMarkdown(report: sampleReport)
        #expect(md.contains("# Permission Pulse export"))
        #expect(md.contains("## Permissions"))
        #expect(md.contains("Foo"))
    }

    @Test("Markdown escapes pipes and newlines in app-controlled cells")
    func markdownEscapesTableCells() {
        let app = AppIdentity(bundleID: "a|b", displayName: "Ev|il\nApp", bundlePath: nil)
        let grant = PermissionGrant(
            service: .camera, app: app,
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil, authValue: 2
        )
        let report = PermissionsExport.report(
            grants: [grant], launchAgents: [], btmItems: [], staleApps: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let md = PermissionsExport.makeMarkdown(report: report)
        // The raw newline must not survive into the table, and pipes are escaped.
        #expect(md.contains("Ev\\|il App"))
        #expect(md.contains("a\\|b"))
        #expect(!md.contains("Ev|il"))
    }
}
