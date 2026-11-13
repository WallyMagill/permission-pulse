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
        return report(grants: [grant], generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private static let complete = ExportDomainCoverage(
        coverage: .complete, lastSuccessfulScan: Date(timeIntervalSince1970: 1_700_000_000)
    )

    private func report(
        grants: [PermissionGrant] = [],
        launchAgents: [LaunchAgentItem] = [],
        generatedAt: Date = Date(timeIntervalSince1970: 0),
        permissions: ExportDomainCoverage = complete,
        backgroundItems: ExportDomainCoverage = complete
    ) -> ExportReport {
        PermissionsExport.report(
            grants: grants, launchAgents: launchAgents, btmItems: [], staleApps: [],
            generatedAt: generatedAt,
            environment: ExportEnvironment(appVersion: "0.7.2", appBuild: "42", macOSVersion: "27.2.0"),
            coverage: ExportCoverage(
                permissions: permissions,
                launchAgents: Self.complete,
                backgroundItems: backgroundItems
            )
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

    @Test("JSON launch-agent record carries readability and the file name")
    func jsonLaunchAgentCarriesReadabilityAndFileName() throws {
        let locked = LaunchAgentItem(
            label: "com.example.locked",
            sourceDirectory: .libraryLaunchDaemons,
            programPath: nil,
            programArguments: [],
            runAtLoad: false,
            keepAlive: false,
            detailsReadable: false,
            fileName: "com.example.locked.plist"
        )
        let text = String(decoding: try PermissionsExport.makeJSON(report: report(launchAgents: [locked])), as: UTF8.self)
        #expect(text.contains("\"detailsReadable\" : false"))
        #expect(text.contains("\"fileName\" : \"com.example.locked.plist\""))
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
        let md = PermissionsExport.makeMarkdown(report: report(grants: [grant]))
        // The raw newline must not survive into the table, and pipes are escaped.
        #expect(md.contains("Ev\\|il App"))
        #expect(md.contains("a\\|b"))
        #expect(!md.contains("Ev|il"))
    }

    @Test("JSON records the format version, app, OS, coverage and grant auth value")
    func jsonCarriesEnvironmentAndCoverage() throws {
        let reduced = ExportDomainCoverage(
            coverage: .reduced, lastSuccessfulScan: Date(timeIntervalSince1970: 1_700_000_000),
            unavailableServices: ["camera"]
        )
        let base = report(permissions: reduced)
        let text = String(decoding: try PermissionsExport.makeJSON(report: base), as: UTF8.self)
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(text.contains("\"appVersion\" : \"0.7.2\""))
        #expect(text.contains("\"appBuild\" : \"42\""))
        #expect(text.contains("\"macOSVersion\" : \"27.2.0\""))
        #expect(text.contains("\"coverage\" : \"reduced\""))
        #expect(text.contains("\"unavailableServices\" : [\n        \"camera\""))
        let withGrant = String(decoding: try PermissionsExport.makeJSON(report: sampleReport), as: UTF8.self)
        #expect(withGrant.contains("\"authValue\" : 2"))
    }

    @Test("Markdown opens with scan coverage and names what macOS hides")
    func markdownCoverageBlock() throws {
        let reduced = ExportDomainCoverage(
            coverage: .reduced, lastSuccessfulScan: Date(timeIntervalSince1970: 0),
            unavailableServices: ["camera", "microphone"]
        )
        let md = PermissionsExport.makeMarkdown(report: report(permissions: reduced))
        let coverageIndex = try #require(md.range(of: "## Scan coverage"))
        let permissionsIndex = try #require(md.range(of: "## Permissions"))
        #expect(coverageIndex.lowerBound < permissionsIndex.lowerBound)
        #expect(md.contains("macOS 27.2.0"))
        #expect(md.contains("Hidden by macOS: Camera, Microphone."))
    }

    @Test("A domain that was never read says why instead of None")
    func markdownNotScanned() {
        let denied = ExportDomainCoverage(coverage: .failed, lastSuccessfulScan: nil, failureReason: .fullDiskAccessOff)
        let md = PermissionsExport.makeMarkdown(report: report(permissions: denied, backgroundItems: denied))
        let permissionsSection = md.components(separatedBy: "## Permissions\n\n")[1]
            .components(separatedBy: "## Launch Agents")[0]
        #expect(permissionsSection == "_Not scanned: Full Disk Access is off._\n\n")
        #expect(md.contains("_Not checked: permissions were not scanned._"))
    }

    @Test("A failed scan with history labels its rows as last-known")
    func markdownLastKnown() {
        let stale = ExportDomainCoverage(
            coverage: .failed, lastSuccessfulScan: Date(timeIntervalSince1970: 0), failureReason: .sourceUnavailable
        )
        let md = PermissionsExport.makeMarkdown(report: report(backgroundItems: stale))
        let section = md.components(separatedBy: "## Background Items\n\n")[1]
        #expect(section.hasPrefix("_Last-known data from 1970-01-01T00:00:00Z._\n\n_None._"))
    }
}
