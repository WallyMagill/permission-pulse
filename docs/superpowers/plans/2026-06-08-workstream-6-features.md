# Workstream 6 — Read-only Feature Additions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the read-only, in-scope features from Thread A Workstream 6 — a hygiene risk-summary line, JSON/Markdown export, a copy-the-`tccutil reset`-command affordance, Reveal-in-Finder consistency, a menu-bar "Rescan Now", and (optional) a "first seen by Permission Pulse" date.

**Architecture:** Pure logic lives in `PermissionsCore` (risk summary, export DTOs/serialization, the `tccutil` reverse map) and `PermissionsStore` (the first-seen query), each carrying real Swift Testing coverage. UI triggers (toolbar Export menu, sheet action footer, menu-bar row) live in `PermissionsUI`, with one closure wired from the app target. Every new file respects the read-only hard rules: export writes only to a user-chosen `NSSavePanel` location; the `tccutil` feature only *copies text to the pasteboard* (the caption makes clear Permission Pulse never runs it); Reveal-in-Finder only selects an existing bundle.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSSavePanel`, `NSPasteboard`, `NSWorkspace` — each behind a `// AppKit:` comment), Swift Testing, GRDB (one new read query, no schema change).

**Scope note:**
- **F5 ("first seen" date) is OPTIONAL — Task 6.** It is the heaviest item (a new `SnapshotStore` query with the path-based-grant identity edge, plus injecting an async lookup into a deeply-nested sheet) for the least user value. Recommend deferring it to a focused follow-up; included here fully so it can be done if wanted.
- **F2's reverse `tccutil` map returns `nil` for `.filesAndFolders`** (its grant comes from five different sub-service strings — `tccutil reset` is per-sub-service, so there is no single canonical command). The button simply omits that service.
- All new user-facing strings go through `String(localized:)`.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Packages/PermissionsCore/Sources/PermissionsCore/PermissionRiskDescription.swift` | **MODIFY** — move `riskSeverity` here as `public`; add `PermissionRiskSummary`. | 1 |
| `Packages/PermissionsUI/Sources/PermissionsUI/DetailSheetStyle.swift` | **MODIFY** — delete the now-duplicated internal `riskSeverity`. | 1 |
| `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionRiskSummaryTests.swift` | **NEW** — risk-summary tests. | 1 |
| `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` | **MODIFY** — render the risk line (T1); add "Rescan Now" row + `onRescan` (T4). | 1, 4 |
| `Packages/PermissionsCore/Sources/PermissionsCore/PermissionsExport.swift` | **NEW** — Codable export DTOs + JSON/Markdown serializers. | 2 |
| `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionsExportTests.swift` | **NEW** — export serialization tests. | 2 |
| `Packages/PermissionsUI/Sources/PermissionsUI/ExportToolbar.swift` | **NEW** — Export toolbar menu + `NSSavePanel` saver. | 2 |
| `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` | **MODIFY** — add the Export toolbar item. | 2 |
| `Packages/PermissionsCore/Sources/PermissionsCore/PermissionService.swift` | **MODIFY** — add `tccutilServiceName` + `tccutilResetCommands`. | 3 |
| `Packages/PermissionsCore/Tests/PermissionsCoreTests/TccutilResetTests.swift` | **NEW** — reverse-map + command-builder tests. | 3 |
| `Packages/PermissionsUI/Sources/PermissionsUI/AppPermissionsDetailSheet.swift` | **MODIFY** — action footer (Copy reset commands + Reveal in Finder). | 3 |
| `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift` | **MODIFY** — Reveal in Finder in the row menu. | 3 |
| `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` | **MODIFY** — wire `onRescan`. | 4 |
| `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift` | **MODIFY (optional)** — `firstSeenDate(forGrant:)`. | 6 |
| `Packages/PermissionsStore/Tests/PermissionsStoreTests/FirstSeenDateTests.swift` | **NEW (optional)** | 6 |
| `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` + sheet | **MODIFY (optional)** — `firstSeenProvider` + surface the date. | 6 |

---

## Task 1: Risk-summary line (F4)

**Files:**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/PermissionRiskDescription.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailSheetStyle.swift:238-262`
- Create: `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionRiskSummaryTests.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` (`overviewSection`)

- [ ] **Step 1: Write the failing test**

Create `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionRiskSummaryTests.swift`:

```swift
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
            grant(.camera, bundleID: "c"), // low-risk, not surfaced
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
```

(Verify the `PermissionGrant` initializer signature against `PermissionGrant.swift` before running — the explorer reported `init(service:app:lastModified:automationTarget:authValue:)` with `authValue` defaulting to 2. If the memberwise init differs, match it.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path Packages/PermissionsCore --filter PermissionRiskSummaryTests`
Expected: FAIL — `cannot find 'PermissionRiskSummary' in scope`.

- [ ] **Step 3: Move `riskSeverity` to Core (public) + add the summary**

In `PermissionRiskDescription.swift`, append to the file (the file already has `extension PermissionService { public var riskDescription: String { ... } }`):

```swift
extension PermissionService {
    /// Severity rank for risk panels and summaries. Higher = more privileged.
    /// FDA is the most privileged TCC scope, then UI/event-hijack, then capture,
    /// then automation, then everything else. (moved from PermissionsUI for reuse)
    public var riskSeverity: Int {
        switch self {
        case .fullDiskAccess:  100
        case .accessibility:    90
        case .inputMonitoring:  80
        case .screenRecording:  70
        case .camera:           60
        case .microphone:       60
        case .automation:       50
        case .appManagement:    40
        case .developerTool:    35
        case .filesAndFolders:  30
        case .photos:           20
        case .contacts:         15
        case .calendar:         10
        case .reminders:        10
        case .mediaLibrary:      8
        case .bluetooth:         5
        }
    }
}

/// One-line menu-bar hygiene signal counting distinct apps that hold each
/// surfaced high-risk service. (F4)
public enum PermissionRiskSummary {
    /// High-risk services worth surfacing, in display order.
    private static let surfaced: [PermissionService] = [
        .fullDiskAccess, .accessibility, .inputMonitoring, .screenRecording,
    ]

    /// e.g. "3 Full Disk Access · 1 Accessibility". `nil` when none are held.
    public static func line(for grants: [PermissionGrant]) -> String? {
        let parts: [String] = surfaced.compactMap { service in
            let apps = Set(grants.filter { $0.service == service }.map(\.appKey))
            guard !apps.isEmpty else { return nil }
            return "\(apps.count) \(service.displayName)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 4: Delete the duplicate `riskSeverity` in PermissionsUI**

In `DetailSheetStyle.swift`, delete the entire trailing block (lines ~238-262):

```swift
// Severity rank for the multi-service Risk panel. Higher rank = shown first.
// ...
extension PermissionService {
    var riskSeverity: Int {
        switch self {
        ...
        }
    }
}
```

`AppPermissionsDetailSheet.highestRiskService` and any other caller now resolve against the `public` Core version (PermissionsUI depends on PermissionsCore).

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --package-path Packages/PermissionsCore --filter PermissionRiskSummaryTests`
Expected: PASS — 3 tests.

- [ ] **Step 6: Render the risk line in the menu bar**

In `MenuBarContentView.swift`, `overviewSection`, append the risk line after the three `StatRow`s (inside the `VStack`):

```swift
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(
                title: String(localized: "Overview"),
                trailing: String(localized: "\(totalItemCount) items")
            )
            StatRow(icon: "lock.fill", tint: .blue, title: String(localized: "Permissions"), count: viewModel.grants.count)
            StatRow(icon: "clock.fill", tint: .purple, title: String(localized: "Launch Agents"), count: viewModel.launchAgents.count)
            StatRow(icon: "square.stack.3d.up.fill", tint: .teal, title: String(localized: "Background Items"), count: viewModel.btmItems.count)
            if let risk = PermissionRiskSummary.line(for: viewModel.grants) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(risk)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Elevated access: \(risk)"))
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }
```

- [ ] **Step 7: Build both packages**

Run: `swift build --package-path Packages/PermissionsCore` → clean.
Run: `swift build --package-path Packages/PermissionsUI` → clean (confirms the `riskSeverity` move didn't break callers).

- [ ] **Step 8: Run the full PermissionsCore suite**

Run: `swift test --package-path Packages/PermissionsCore`
Expected: all pass (prior count + 3 new).

- [ ] **Step 9: Commit**

```bash
git add Packages/PermissionsCore/Sources/PermissionsCore/PermissionRiskDescription.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/DetailSheetStyle.swift \
        Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionRiskSummaryTests.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift
git commit -m "feat(core): public riskSeverity + menu-bar risk-summary line (F4)"
```

---

## Task 2: Export to JSON / Markdown (F1)

**Approach:** Serialize via dedicated `Codable` export DTOs (NOT by conforming domain models) — keeps export concerns out of the GRDB-backed models and sidesteps the hand-written `Codable` that `BTMItem`'s associated-value enums would otherwise need.

**Files:**
- Create: `Packages/PermissionsCore/Sources/PermissionsCore/PermissionsExport.swift`
- Create: `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionsExportTests.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/ExportToolbar.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (toolbar)

- [ ] **Step 1: Write the failing test**

Create `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionsExportTests.swift`:

```swift
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
        #expect(text.contains("2023-11-14")) // ISO-8601 of 1_700_000_000
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
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/PermissionsCore --filter PermissionsExportTests`
Expected: FAIL — `cannot find 'PermissionsExport'` / `'ExportReport'`.

- [ ] **Step 3: Implement the export module**

Create `Packages/PermissionsCore/Sources/PermissionsCore/PermissionsExport.swift`:

```swift
import Foundation

// Codable export representation, decoupled from the GRDB-backed domain models.
// Each DTO is plain String/Int/Bool/Date so JSON synthesis is automatic and the
// BTM associated-value enums collapse to stable strings. (F1)

public struct ExportReport: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let grants: [ExportGrant]
    public let launchAgents: [ExportLaunchAgent]
    public let backgroundItems: [ExportBackgroundItem]
    public let staleApps: [ExportStaleApp]
}

public struct ExportGrant: Codable, Sendable, Equatable {
    public let service: String
    public let serviceKey: String
    public let appName: String
    public let bundleID: String
    public let bundlePath: String?
    public let lastModified: Date
    public let automationTarget: String?
}

public struct ExportLaunchAgent: Codable, Sendable, Equatable {
    public let label: String
    public let source: String
    public let programPath: String?
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let isDisabled: Bool
}

public struct ExportBackgroundItem: Codable, Sendable, Equatable {
    public let identifier: String
    public let name: String
    public let developerName: String?
    public let bundleIdentifier: String?
    public let type: String
    public let disposition: String
    public let scope: String
    public let modificationDate: Date
}

public struct ExportStaleApp: Codable, Sendable, Equatable {
    public let appName: String
    public let bundleID: String
    public let lastUsedDate: Date
    public let dateSource: String
    public let daysSinceUsed: Int
    public let grantedServices: [String]
}

public enum PermissionsExport {
    public static func report(
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem],
        staleApps: [StaleApp],
        generatedAt: Date
    ) -> ExportReport {
        ExportReport(
            generatedAt: generatedAt,
            grants: grants.map(Self.map),
            launchAgents: launchAgents.map(Self.map),
            backgroundItems: btmItems.map(Self.map),
            staleApps: staleApps.map(Self.map)
        )
    }

    public static func makeJSON(report: ExportReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    public static func makeMarkdown(report: ExportReport) -> String {
        var out = "# Permission Pulse export\n\n"
        out += "_Generated \(Self.iso(report.generatedAt)) · read-only snapshot of current state._\n\n"

        out += "## Permissions\n\n"
        if report.grants.isEmpty {
            out += "_None._\n\n"
        } else {
            out += "| App | Bundle ID | Service | Last modified |\n|---|---|---|---|\n"
            for g in report.grants {
                out += "| \(g.appName) | \(g.bundleID) | \(g.service) | \(Self.iso(g.lastModified)) |\n"
            }
            out += "\n"
        }

        out += "## Launch Agents\n\n"
        if report.launchAgents.isEmpty {
            out += "_None._\n\n"
        } else {
            out += "| Label | Source | runAtLoad | keepAlive |\n|---|---|---|---|\n"
            for a in report.launchAgents {
                out += "| \(a.label) | \(a.source) | \(a.runAtLoad) | \(a.keepAlive) |\n"
            }
            out += "\n"
        }

        out += "## Background Items\n\n"
        if report.backgroundItems.isEmpty {
            out += "_None._\n\n"
        } else {
            out += "| Name | Developer | Type | Disposition |\n|---|---|---|---|\n"
            for b in report.backgroundItems {
                out += "| \(b.name) | \(b.developerName ?? "—") | \(b.type) | \(b.disposition) |\n"
            }
            out += "\n"
        }

        out += "## Stale Apps\n\n"
        if report.staleApps.isEmpty {
            out += "_None._\n\n"
        } else {
            out += "| App | Last used | Days | Services |\n|---|---|---|---|\n"
            for s in report.staleApps {
                out += "| \(s.appName) | \(Self.iso(s.lastUsedDate)) | \(s.daysSinceUsed) | \(s.grantedServices.joined(separator: ", ")) |\n"
            }
            out += "\n"
        }
        return out
    }

    // MARK: - Mapping

    private static func map(_ g: PermissionGrant) -> ExportGrant {
        ExportGrant(
            service: g.service.displayName,
            serviceKey: g.service.rawValue,
            appName: g.app.displayName,
            bundleID: g.app.bundleID,
            bundlePath: g.app.bundlePath?.path(percentEncoded: false),
            lastModified: g.lastModified,
            automationTarget: g.automationTarget
        )
    }

    private static func map(_ a: LaunchAgentItem) -> ExportLaunchAgent {
        ExportLaunchAgent(
            label: a.label,
            source: a.sourceDirectory.rawValue,
            programPath: a.programPath,
            runAtLoad: a.runAtLoad,
            keepAlive: a.keepAlive,
            isDisabled: a.isDisabled
        )
    }

    private static func map(_ b: BTMItem) -> ExportBackgroundItem {
        ExportBackgroundItem(
            identifier: b.identifier,
            name: b.name,
            developerName: b.developerName,
            bundleIdentifier: b.bundleIdentifier,
            type: Self.string(for: b.type),
            disposition: Self.string(for: b.disposition),
            scope: Self.string(for: b.scope),
            modificationDate: b.modificationDate
        )
    }

    private static func map(_ s: StaleApp) -> ExportStaleApp {
        ExportStaleApp(
            appName: s.app.displayName,
            bundleID: s.app.bundleID,
            lastUsedDate: s.lastUsedDate,
            dateSource: s.dateSource == .spotlight ? "spotlight" : "fileSystem",
            daysSinceUsed: s.daysSinceUsed,
            grantedServices: s.grantedServices.map(\.rawValue)
        )
    }

    private static func string(for type: BTMItem.ItemType) -> String {
        switch type {
        case .app: "app"
        case .legacyDaemon: "legacyDaemon"
        case .developerGroup: "developerGroup"
        case .unknown(let raw): "unknown(\(raw))"
        }
    }

    private static func string(for disposition: BTMItem.Disposition) -> String {
        switch disposition {
        case .enabled: "enabled"
        case .disabled: "disabled"
        case .unknown(let raw): "unknown(\(raw))"
        }
    }

    private static func string(for scope: BTMItem.Scope) -> String {
        switch scope {
        case .system: "system"
        case .user: "user"
        case .perUser(let uuid): "perUser(\(uuid))"
        }
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: date)
    }
}
```

(Before finalizing, confirm the exact case names of `BTMItem.ItemType`/`.Disposition`/`.Scope` and the `LaunchAgentItem`/`StaleApp` property names against the model files. The explorer reported: `ItemType{app,legacyDaemon,developerGroup,unknown(rawValue:)}`, `Disposition{enabled,disabled,unknown(rawValue:)}`, `Scope{system,user,perUser(uuid:)}`, `StaleApp.DateSource{spotlight,fileSystem}`. Fix any mismatch.)

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/PermissionsCore --filter PermissionsExportTests`
Expected: PASS — 3 tests. (If the ISO date substring assertion fails, print the JSON and adjust the literal to the actual ISO output for `1_700_000_000` — it is `2023-11-14T...`.)

- [ ] **Step 5: Create the Export toolbar + saver**

Create `Packages/PermissionsUI/Sources/PermissionsUI/ExportToolbar.swift`:

```swift
// AppKit: NSSavePanel is the only way to let the user choose an export
// location; writing there is explicitly allowed by the read-only hard rules.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PermissionsCore

struct ExportToolbarMenu: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Menu {
            Button(String(localized: "Export as JSON…")) { export(.json) }
            Button(String(localized: "Export as Markdown…")) { export(.markdown) }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .help(String(localized: "Export current state"))
        .accessibilityLabel(String(localized: "Export"))
    }

    private enum Format { case json, markdown }

    private func export(_ format: Format) {
        let report = PermissionsExport.report(
            grants: viewModel.grants,
            launchAgents: viewModel.launchAgents,
            btmItems: viewModel.btmItems,
            staleApps: viewModel.staleApps,
            generatedAt: Date()
        )
        let data: Data
        let ext: String
        let contentType: UTType
        switch format {
        case .json:
            guard let json = try? PermissionsExport.makeJSON(report: report) else { return }
            data = json; ext = "json"; contentType = .json
        case .markdown:
            data = Data(PermissionsExport.makeMarkdown(report: report).utf8)
            ext = "md"; contentType = UTType(filenameExtension: "md") ?? .plainText
        }
        ExportSaver.run(data: data, suggestedName: "PermissionPulse-Export.\(ext)", contentType: contentType)
    }
}

private enum ExportSaver {
    // AppKit: NSSavePanel + Data.write to a user-chosen URL.
    static func run(data: Data, suggestedName: String, contentType: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 6: Add the Export toolbar item**

In `DetailWindowView.swift`, the detail `.toolbar { ... }` currently has the Refresh + Preferences `ToolbarItem`s. Add an Export item before the Preferences item:

```swift
                .toolbar {
                    if let onRefresh {
                        ToolbarItem(placement: .primaryAction) {
                            RefreshToolbarButton {
                                await onRefresh()
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ExportToolbarMenu()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        PreferencesToolbarButton {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "preferences")
                        }
                    }
                }
```

- [ ] **Step 7: Build packages**

Run: `swift build --package-path Packages/PermissionsCore` → clean.
Run: `swift build --package-path Packages/PermissionsUI` → clean.

- [ ] **Step 8: Run PermissionsCore tests**

Run: `swift test --package-path Packages/PermissionsCore`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add Packages/PermissionsCore/Sources/PermissionsCore/PermissionsExport.swift \
        Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionsExportTests.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/ExportToolbar.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift
git commit -m "feat(ui): export current state to JSON/Markdown via NSSavePanel (F1)"
```

---

## Task 3: tccutil reset command + Reveal in Finder (F2 + F6)

**Files:**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/PermissionService.swift`
- Create: `Packages/PermissionsCore/Tests/PermissionsCoreTests/TccutilResetTests.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppPermissionsDetailSheet.swift` (footer)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift` (row menu)

- [ ] **Step 1: Write the failing test**

Create `Packages/PermissionsCore/Tests/PermissionsCoreTests/TccutilResetTests.swift`:

```swift
import Testing
@testable import PermissionsCore

@Suite("tccutil reset mapping")
struct TccutilResetTests {
    @Test("known services map to their tccutil service name")
    func knownMappings() {
        #expect(PermissionService.screenRecording.tccutilServiceName == "ScreenCapture")
        #expect(PermissionService.fullDiskAccess.tccutilServiceName == "SystemPolicyAllFiles")
        #expect(PermissionService.contacts.tccutilServiceName == "AddressBook")
        #expect(PermissionService.inputMonitoring.tccutilServiceName == "ListenEvent")
    }

    @Test("filesAndFolders has no single canonical reset command")
    func filesAndFoldersIsNil() {
        #expect(PermissionService.filesAndFolders.tccutilServiceName == nil)
    }

    @Test("builds one sorted command per mappable service for an app")
    func buildsCommands() {
        let cmds = tccutilResetCommands(
            bundleID: "com.foo.bar",
            services: [.camera, .screenRecording, .filesAndFolders]
        )
        #expect(cmds == [
            "tccutil reset Camera com.foo.bar",
            "tccutil reset ScreenCapture com.foo.bar",
        ])
    }

    @Test("no commands when bundle ID is empty")
    func emptyBundleID() {
        #expect(tccutilResetCommands(bundleID: "", services: [.camera]).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/PermissionsCore --filter TccutilResetTests`
Expected: FAIL — `tccutilServiceName` / `tccutilResetCommands` not found.

- [ ] **Step 3: Add the reverse map + command builder**

Append to `PermissionService.swift`:

```swift
extension PermissionService {
    /// The `tccutil reset <name>` service argument (the `kTCCService` prefix
    /// stripped). `nil` for `.filesAndFolders`, whose grant comes from five
    /// distinct sub-services with no single canonical reset target. (F2)
    public var tccutilServiceName: String? {
        switch self {
        case .accessibility:   "Accessibility"
        case .screenRecording: "ScreenCapture"
        case .fullDiskAccess:  "SystemPolicyAllFiles"
        case .microphone:      "Microphone"
        case .camera:          "Camera"
        case .automation:      "AppleEvents"
        case .filesAndFolders: nil
        case .photos:          "Photos"
        case .calendar:        "Calendar"
        case .contacts:        "AddressBook"
        case .reminders:       "Reminders"
        case .bluetooth:       "BluetoothAlways"
        case .mediaLibrary:    "MediaLibrary"
        case .appManagement:   "SystemPolicyAppBundles"
        case .inputMonitoring: "ListenEvent"
        case .developerTool:   "DeveloperTool"
        }
    }
}

/// `tccutil reset` commands for an app, one per mappable service, sorted and
/// de-duplicated. Empty when the app has no bundle ID (the command needs one).
/// Display/copy only — Permission Pulse never runs these. (F2)
public func tccutilResetCommands(bundleID: String, services: [PermissionService]) -> [String] {
    guard !bundleID.isEmpty else { return [] }
    let names = Set(services.compactMap(\.tccutilServiceName)).sorted()
    return names.map { "tccutil reset \($0) \(bundleID)" }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/PermissionsCore --filter TccutilResetTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Replace the sheet footer with an action footer**

In `AppPermissionsDetailSheet.swift`: add `@Environment(\.dismiss)`, replace `SheetCloseFooter()` (line 56) with a custom footer, and add helper members. First add to the struct's stored/environment members (after `private let grants`):

```swift
    @Environment(\.dismiss) private var dismiss
```

Replace `SheetCloseFooter()` in `body` with:

```swift
            actionFooter
```

Add these computed/method members (e.g. after `mostRecentDate(for:)`):

```swift
    private var resetCommands: [String] {
        tccutilResetCommands(bundleID: app.bundleID, services: distinctServices)
    }

    @ViewBuilder
    private var actionFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !resetCommands.isEmpty {
                Text(String(localized: "Permission Pulse won't run these — paste them into Terminal yourself."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                if app.bundlePath != nil {
                    Button(String(localized: "Reveal in Finder")) { revealInFinder() }
                }
                if !resetCommands.isEmpty {
                    Button(String(localized: "Copy Reset Commands")) { copyResetCommands() }
                }
                Button(String(localized: "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // AppKit: NSPasteboard is the system clipboard; we only copy text the user
    // pastes into Terminal themselves. Permission Pulse never executes it.
    private func copyResetCommands() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resetCommands.joined(separator: "\n"), forType: .string)
    }

    // AppKit: NSWorkspace reveals an existing bundle in Finder (read-only).
    private func revealInFinder() {
        guard let url = app.bundlePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
```

- [ ] **Step 6: Add Reveal in Finder to the stale-app row menu**

In `StaleAppsTabView.swift`, the `StaleAppRow`'s `Menu` currently contains only "Skip forever". Add a "Reveal in Finder" item above it when the app has a bundle path, and a reveal helper. The `Menu` becomes:

```swift
                Menu {
                    if app.app.bundlePath != nil {
                        Button(String(localized: "Reveal in Finder")) { revealInFinder() }
                    }
                    Button(String(localized: "Skip forever")) { onSkipForever() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.tertiary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(String(localized: "Options"))
                .accessibilityHint(String(localized: "Reveal in Finder or skip this app"))
```

Add to `StaleAppRow` (it already `import AppKit` at file top):

```swift
    // AppKit: NSWorkspace reveals the app bundle in Finder (read-only).
    private func revealInFinder() {
        guard let url = app.app.bundlePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
```

(Update the existing `.accessibilityHint` from "Skip this app forever" to the combined hint shown above.)

- [ ] **Step 7: Build packages**

Run: `swift build --package-path Packages/PermissionsCore` → clean.
Run: `swift build --package-path Packages/PermissionsUI` → clean.

- [ ] **Step 8: Run PermissionsCore + PermissionsUI tests**

Run: `swift test --package-path Packages/PermissionsCore` → pass.
Run: `swift test --package-path Packages/PermissionsUI` → pass.

- [ ] **Step 9: Commit**

```bash
git add Packages/PermissionsCore/Sources/PermissionsCore/PermissionService.swift \
        Packages/PermissionsCore/Tests/PermissionsCoreTests/TccutilResetTests.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/AppPermissionsDetailSheet.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift
git commit -m "feat(ui): copy tccutil reset command + Reveal in Finder in detail sheet & stale rows (F2, F6)"
```

---

## Task 4: Menu-bar "Rescan Now" (F3)

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` (init + footer)
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` (wire `onRescan`)

- [ ] **Step 1: Add `onRescan` to `MenuBarContentView`**

The struct currently has `private let onShowWelcome: (() -> Void)?` and `public init(onShowWelcome:)` (from W5). Extend:

```swift
public struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppViewModel.self) private var viewModel
    private let onShowWelcome: (() -> Void)?
    private let onRescan: (() -> Void)?

    public init(
        onShowWelcome: (() -> Void)? = nil,
        onRescan: (() -> Void)? = nil
    ) {
        self.onShowWelcome = onShowWelcome
        self.onRescan = onRescan
    }
```

- [ ] **Step 2: Add the "Rescan Now" footer row**

In `footer`, insert as the FIRST row (before "What Changed"), gated on the closure and disabled mid-scan:

```swift
            if let onRescan {
                MenuRowButton(
                    icon: "arrow.clockwise",
                    title: String(localized: "Rescan Now"),
                    shortcutKey: "r",
                    shortcutDisplay: "⌘R"
                ) {
                    onRescan()
                }
                .disabled(viewModel.scanInProgress)
            }
```

- [ ] **Step 3: Wire it from the app target**

In `PermissionPulseApp.swift`, extend the `MenuBarContentView(...)` construction (currently passes `onShowWelcome`):

```swift
        MenuBarExtra {
            MenuBarContentView(
                onShowWelcome: { [appDelegate] in
                    appDelegate.showWelcomeWindow()
                },
                onRescan: { [appDelegate] in
                    Task { await appDelegate.rescan() }
                }
            )
                .environment(appDelegate.viewModel)
        } label: {
```

(`rescan()` already guards on `scanInProgress` internally, so the `.disabled` is belt-and-suspenders.)

- [ ] **Step 4: Build package, then app target**

Run: `swift build --package-path Packages/PermissionsUI` → clean.
Run: `xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -configuration Debug build 2>&1 | tail -3` → `BUILD SUCCEEDED`.

- [ ] **Step 5: Run PermissionsUI tests**

Run: `swift test --package-path Packages/PermissionsUI` → pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift \
        PermissionPulse/PermissionPulse/PermissionPulseApp.swift
git commit -m "feat(ui): menu-bar Rescan Now (F3)"
```

---

## Task 5: Final whole-branch review

- [ ] After Tasks 1-4 (and optionally 6), run the final whole-branch review and the app-target build, then proceed to finishing-a-development-branch.

```bash
xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -configuration Debug build 2>&1 | tail -3
swift test --package-path Packages/PermissionsCore
swift test --package-path Packages/PermissionsUI
```

---

## Task 6 (OPTIONAL — recommend deferring): "First seen by Permission Pulse" date (F5)

> Heaviest item for the least value. Only do this if explicitly chosen. It adds one `SnapshotStore` query and surfaces the date in the per-app sheet via a provider on `AppViewModel`.

**Files:**
- Modify: `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift`
- Create: `Packages/PermissionsStore/Tests/PermissionsStoreTests/FirstSeenDateTests.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` + `AppPermissionsDetailSheet.swift`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` (set the provider)

- [ ] **Step 1: Failing test for the store query**

Create `Packages/PermissionsStore/Tests/PermissionsStoreTests/FirstSeenDateTests.swift`:

```swift
import Testing
import Foundation
import PermissionsCore
@testable import PermissionsStore

@Suite("SnapshotStore.firstSeenDate")
struct FirstSeenDateTests {
    private func grant(_ bundleID: String) -> PermissionGrant {
        PermissionGrant(
            service: .camera,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: nil),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil, authValue: 2
        )
    }

    @Test("returns the earliest snapshot date containing the grant")
    func earliest() async throws {
        let store = try SnapshotStore.inMemory()
        let g = grant("com.foo.bar")
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        _ = try await store.writeFullSnapshot(date: early, grants: [g], launchAgents: [], btmItems: [])
        _ = try await store.writeFullSnapshot(date: late, grants: [g], launchAgents: [], btmItems: [])
        let seen = try await store.firstSeenDate(forGrant: g)
        #expect(seen == early)
    }

    @Test("nil when the grant was never captured")
    func missing() async throws {
        let store = try SnapshotStore.inMemory()
        _ = try await store.writeFullSnapshot(date: Date(timeIntervalSince1970: 1_000), grants: [grant("a")], launchAgents: [], btmItems: [])
        #expect(try await store.firstSeenDate(forGrant: grant("b")) == nil)
    }
}
```

(Confirm `writeFullSnapshot`'s exact signature in `SnapshotStore.swift:106` before running and match it — the explorer noted `writeFullSnapshot(date:grants:launchAgents:btmItems:)` but verify parameter labels/return.)

- [ ] **Step 2: Run to verify it fails** — `swift test --package-path Packages/PermissionsStore --filter FirstSeenDateTests` → FAIL (`firstSeenDate` not found).

- [ ] **Step 3: Implement the query**

Add to `SnapshotStore.swift` (model it after the existing `readTCCGrants`/`latestSnapshotID` GRDB read methods — use the same `dbQueue.read { db in ... }` style and the same date-decoding the store already uses for `created_at`). The WHERE clause matches the grant identity, handling the path-based edge (empty `bundle_id` → match `bundle_path`):

```swift
/// Earliest snapshot `created_at` that contains a grant matching this grant's
/// identity, or nil if never captured. Handles path-based grants (empty
/// bundle_id) by matching bundle_path instead. (F5)
public func firstSeenDate(forGrant grant: PermissionGrant) async throws -> Date? {
    let service = grant.service.rawValue
    let bundleID = grant.app.bundleID
    let bundlePath = grant.app.bundlePath?.path(percentEncoded: false) ?? ""
    let automation = grant.automationTarget ?? ""
    return try await dbQueue.read { db in
        let row: Row?
        if bundleID.isEmpty {
            row = try Row.fetchOne(db, sql: """
                SELECT MIN(s.created_at) AS first
                FROM tcc_grants g JOIN snapshots s ON s.id = g.snapshot_id
                WHERE g.service = ? AND g.bundle_id = '' AND g.bundle_path = ?
                  AND COALESCE(g.automation_target, '') = ?
                """, arguments: [service, bundlePath, automation])
        } else {
            row = try Row.fetchOne(db, sql: """
                SELECT MIN(s.created_at) AS first
                FROM tcc_grants g JOIN snapshots s ON s.id = g.snapshot_id
                WHERE g.service = ? AND g.bundle_id = ?
                  AND COALESCE(g.automation_target, '') = ?
                """, arguments: [service, bundleID, automation])
        }
        guard let first: Date = row?["first"] else { return nil }
        return first
    }
}
```

(The store stores `created_at` as a GRDB-encoded `Date`; `row["first"]` decodes it via GRDB's `Date` support, consistent with the store's existing reads. If the store uses a custom date column type, mirror that decoding — read `readTCCGrants` to match exactly.)

- [ ] **Step 4: Run to verify it passes** — `swift test --package-path Packages/PermissionsStore --filter FirstSeenDateTests` → PASS.

- [ ] **Step 5: Surface in the sheet via a provider on the view model**

In `AppViewModel.swift`, add a provider closure (set by the app target; the sheet reads it):

```swift
    /// Resolves the earliest snapshot date a grant was captured, or nil.
    /// Injected by the app target (backed by SnapshotStore). (F5)
    public var firstSeenProvider: (@Sendable (PermissionGrant) async -> Date?)?
```

In `PermissionPulseApp.swift` `applicationDidFinishLaunching`, after the snapshot store is created, set:

```swift
        viewModel.firstSeenProvider = { [weak snapshotStore] grant in
            guard let snapshotStore else { return nil }
            return try? await snapshotStore.firstSeenDate(forGrant: grant)
        }
```

In `AppPermissionsDetailSheet.swift`, read `@Environment(AppViewModel.self) private var viewModel`, add `@State private var firstSeen: Date?`, load it in `.task`, and show one line under the header when present:

```swift
            if let firstSeen {
                Text(String(localized: "First seen by Permission Pulse \(sheetFormattedDate(firstSeen))"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 12)
            }
```

and:

```swift
        .task {
            // Use the highest-risk grant as the representative for the app-level date.
            guard let provider = viewModel.firstSeenProvider,
                  let representative = grants.max(by: { $0.service.riskSeverity < $1.service.riskSeverity }) else { return }
            firstSeen = await provider(representative)
        }
```

- [ ] **Step 6: Build + test + app-target build**, then commit:

```bash
swift test --package-path Packages/PermissionsStore
swift build --package-path Packages/PermissionsUI
xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -configuration Debug build 2>&1 | tail -3
git add Packages/PermissionsStore PermissionPulse/PermissionPulse/PermissionPulseApp.swift Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift Packages/PermissionsUI/Sources/PermissionsUI/AppPermissionsDetailSheet.swift
git commit -m "feat: first-seen-by-Permission-Pulse date in the per-app sheet (F5)"
```

---

## Self-Review

**Spec coverage:** F1 → Task 2 (export DTOs + JSON/MD + NSSavePanel toolbar). F2 → Task 3 (`tccutilServiceName`/`tccutilResetCommands` + sheet "Copy Reset Commands" + caption). F3 → Task 4 (menu-bar "Rescan Now" + `onRescan`). F4 → Task 1 (public `riskSeverity` + `PermissionRiskSummary` + menu-bar line). F5 → Task 6 (optional `firstSeenDate` query + sheet surfacing). F6 → Task 3 (Reveal in Finder in the sheet footer + stale-app row). All six IDs covered.

**Placeholder scan:** Every code step shows complete code. Three steps say "confirm the exact signature against the source before running" (PermissionGrant init, BTM enum case names, writeFullSnapshot signature) — these are verification instructions for the implementer, not placeholders, because the explorer reported them second-hand; the implementer must reconcile to source.

**Type consistency:** `PermissionRiskSummary.line(for:)` defined T1S3, consumed T1S6. `riskSeverity` moved to Core public T1S3, deleted from PermissionsUI T1S4 (callers `AppPermissionsDetailSheet.highestRiskService` + T6's `.task` resolve against Core). `ExportReport`/`PermissionsExport.report/makeJSON/makeMarkdown` defined T2S3, consumed in tests T2S1 and `ExportToolbarMenu` T2S5. `tccutilServiceName`/`tccutilResetCommands(bundleID:services:)` defined T3S3, consumed T3S1 tests + T3S5 sheet. `MenuBarContentView.init(onShowWelcome:onRescan:)` extended T4S1, called T4S3. `firstSeenDate(forGrant:)` defined T6S3, consumed T6S1 + T6S5 provider. `firstSeenProvider` defined T6S5 on `AppViewModel`, set in app target, read in sheet.

**Read-only safety:** Export → user-chosen `NSSavePanel` URL only (allowed). `tccutil` → `NSPasteboard` text only, never executed, caption states so. Reveal → `NSWorkspace.activateFileViewerSelecting` on an existing bundle (read-only). Rescan → existing guarded `rescan()`. No writes outside the support dir, no sudo, no new entitlements.
