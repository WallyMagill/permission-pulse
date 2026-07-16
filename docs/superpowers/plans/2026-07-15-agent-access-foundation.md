# Permission Pulse Agent Access Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local, read-only Agent Access area that detects ten AI coding-agent families, fully interprets persistent Codex and Claude Code permissions, correlates supported desktop TCC evidence without merging process boundaries, and records trustworthy daily drift.

**Architecture:** Add normalized Agent Access evidence and scanner protocols to `PermissionsCore`; implement bounded detection, parsing, precedence, and host correlation in `PermissionsScanners`; extend `SnapshotStore` to schema v6 with an independent Agent Access capture marker; and integrate the domain through an app coordinator into focused SwiftUI page, inspector, preferences, history, digest, and export components. Existing TCC, BTM, and LaunchAgent scans and snapshots remain independently valid when Agent Access is incomplete.

**Tech Stack:** Swift 6.3, Swift Testing, SwiftUI/Observation, GRDB.swift 7.x, Foundation JSON decoding, and `dduan/TOMLDecoder` 0.4.5 constrained to `PermissionsScanners`.

## Global Constraints

- The approved design is `docs/superpowers/specs/2026-07-15-agent-access-foundation-design.md`; it is the implementation contract.
- Permission Pulse remains local-only, read-only, telemetry-free, and must never launch an agent CLI, hook, plugin, extension, or MCP server.
- The only new file-content reads are allowlisted agent configuration and policy files. Never read source, documents, prompts, transcripts, sessions, credentials, authentication stores, arbitrary files, or cloud-managed caches.
- Never persist, log, notify, dismiss-key, or export raw configuration, tokens, headers, environment values, OAuth material, hook commands, or MCP credentials.
- Support level (`full`, `partial`, `detectedOnly`) and scan availability (`never`, `complete`, `degraded`, `failed`) remain separate truths.
- Unknown security-relevant syntax, unsupported versions, unresolved includes, ambiguous precedence, or exceeded safety bounds degrade the affected adapter; unknown never means safe.
- Keep CLI, desktop app, IDE, and host surfaces separate even when grouped under one vendor family.
- A host relationship requires the desktop bundle itself, documented local integration metadata, or an explicit user association. Never infer that a CLI ran through Terminal or an IDE.
- Foundation ceilings are 32 developer roots, 10,000 visited directory entries per root, 2,000 candidate files per adapter, 1 MiB per file, eight nested includes, 64 decoded container levels, and 16 symlink resolutions per candidate.
- Existing TCC, BTM, and LaunchAgent snapshot writes continue when Agent Access is degraded or failed; those snapshots set `agent_access_captured = false` and contain no Agent Access rows.
- Agent diffs use only two snapshots where `agent_access_captured = true`; same-day recovery updates live state but never mutates that day's prior snapshot.
- All user-facing strings use `String(localized:)`; every new UI state has VoiceOver and keyboard coverage.
- `TOMLDecoder` is pinned at 0.4.5, used only by `PermissionsScanners`, decode-only, and hidden behind `AgentTOMLDecoding`.
- Do not assign a release version or change `MARKETING_VERSION` without separate approval.

---

## File map

Create focused core files `AgentSurface.swift`, `AgentPermissionFact.swift`, `AgentCoverage.swift`, and `AgentAccessScanning.swift`. Scanner work is split into `AgentDiscovery`, `AgentSurfaceDetector`, `CodexConfigAdapter`, `ClaudeCodeConfigAdapter`, `AgentHostCorrelator`, and `AgentAccessScanner`; each adapter owns only one vendor's allowlist and precedence. Store work uses a dedicated `AgentAccessDiff.swift` while schema/SQL remains in `SnapshotStore.swift`. UI work is split into `AgentAccessPage`, `AgentAccessInspector`, `AgentAccessPresentation`, and `PermissionDebt`, leaving `DetailWindowView` as navigation composition rather than adding another large page body.

The app target gains `AgentAccessCoordinator.swift`; `ScanCoordinator` remains responsible only for existing system domains. `SnapshotCoordinator` receives the already-published Agent Access state and owns the combined daily capture decision. Preferences persist standardized roots and explicit host associations through the existing bundle-prefixed `UserDefaults` domain.

### Task 1: Define normalized Agent Access evidence and scanner contracts

**Files:**
- Create: `Packages/PermissionsCore/Sources/PermissionsCore/AgentSurface.swift`
- Create: `Packages/PermissionsCore/Sources/PermissionsCore/AgentPermissionFact.swift`
- Create: `Packages/PermissionsCore/Sources/PermissionsCore/AgentCoverage.swift`
- Create: `Packages/PermissionsCore/Sources/PermissionsCore/AgentAccessScanning.swift`
- Test: `Packages/PermissionsCore/Tests/PermissionsCoreTests/AgentAccessModelTests.swift`

**Interfaces:**
- Produces: `AgentSurfaceID`, `AgentVendor`, `AgentSurfaceKind`, `AgentSurface`, `AgentSupportLevel`, `AgentCapability`, `AgentDecision`, `AgentScope`, `AgentEvidenceSource`, `AgentPermissionFact`, `AgentCoverageReport`, `AgentHostEvidence`, `AgentAccessScanRequest`, `AgentAccessSnapshot`, `AgentAccessScan`, `AgentAdapterResult`, `AgentConfigAdapter`, `AgentAccessScanning`, and `AgentHostCorrelating`.
- Consumed by: every later task.

- [ ] **Step 1: Write failing identity, unknown-value, and redaction-boundary tests**

```swift
import Foundation
import Testing
@testable import PermissionsCore

@Test func decisionIsMutableButExcludedFromFactIdentity() {
    let source = AgentEvidenceSource(layer: .project, safePath: "/repo/.codex/config.toml", locator: "approval_policy")
    let base = AgentPermissionFact(surfaceID: "openai.codex.cli:user", capability: .approvalPolicy, decision: .ask, scope: .global, matcher: "on-request", source: source, explanation: "Prompts when required")
    let changed = AgentPermissionFact(surfaceID: base.surfaceID, capability: base.capability, decision: .allow, scope: base.scope, matcher: base.matcher, source: base.source, explanation: "Never prompts")
    #expect(base.id == changed.id)
    #expect(base != changed)
}

@Test func matcherChangeCreatesANewFactIdentity() {
    let source = AgentEvidenceSource(layer: .user, safePath: "~/.claude/settings.json", locator: "permissions.allow[0]")
    let one = AgentPermissionFact(surfaceID: "anthropic.claude-code.cli:user", capability: .toolRule, decision: .allow, scope: .project("/repo"), matcher: "Bash(git status)", source: source, explanation: "Allows one command")
    let two = AgentPermissionFact(surfaceID: one.surfaceID, capability: one.capability, decision: one.decision, scope: one.scope, matcher: "Bash(git *)", source: one.source, explanation: "Allows git commands")
    #expect(one.id != two.id)
}

@Test func unknownRawValuesRoundTripWithoutBecomingSafeDefaults() throws {
    let vendor = AgentVendor(rawValue: "future-vendor")
    let data = try JSONEncoder().encode(vendor)
    #expect(try JSONDecoder().decode(AgentVendor.self, from: data).rawValue == "future-vendor")
}
```

- [ ] **Step 2: Run the core tests and confirm the red state**

```bash
swift test --package-path Packages/PermissionsCore --filter AgentAccessModelTests
```

Expected: compilation fails because the Agent Access types do not exist.

- [ ] **Step 3: Implement the exact model boundaries**

Use raw-string wrapper structs for forward-compatible vendor, capability, and decision values; use explicit enums only where the closed shape is needed for identity:

```swift
public struct AgentSurfaceID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public struct AgentVendor: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let openAI = Self(rawValue: "openai")
    public static let anthropic = Self(rawValue: "anthropic")
    public static let cursor = Self(rawValue: "cursor")
    public static let google = Self(rawValue: "google")
    public static let pi = Self(rawValue: "pi")
    public static let ohMyPi = Self(rawValue: "oh-my-pi")
    public static let xAI = Self(rawValue: "xai")
    public static let openCode = Self(rawValue: "opencode")
    public static let github = Self(rawValue: "github")
    public static let amazon = Self(rawValue: "amazon")
}

public enum AgentSurfaceKind: String, Codable, Hashable, Sendable { case cli, desktopApp, ide, host }
public enum AgentSupportLevel: String, Codable, Hashable, Sendable { case full, partial, detectedOnly }

public struct AgentSurface: Codable, Hashable, Identifiable, Sendable {
    public let id: AgentSurfaceID
    public let vendor: AgentVendor
    public let productName: String
    public let kind: AgentSurfaceKind
    public let supportLevel: AgentSupportLevel
    public let bundleID: String?
    public let installationPath: String?
    public let configurationRoot: String?
}
```

Define raw wrappers and scope identity exactly:

```swift
public struct AgentCapability: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let approvalPolicy = Self(rawValue: "approval-policy")
    public static let sandbox = Self(rawValue: "sandbox")
    public static let filesystem = Self(rawValue: "filesystem")
    public static let network = Self(rawValue: "network")
    public static let toolRule = Self(rawValue: "tool-rule")
    public static let mcpServer = Self(rawValue: "mcp-server")
    public static let mcpTool = Self(rawValue: "mcp-tool")
    public static let hook = Self(rawValue: "hook")
    public static let projectTrust = Self(rawValue: "project-trust")
    public static let permissionMode = Self(rawValue: "permission-mode")
    public static let managedRestriction = Self(rawValue: "managed-restriction")
}
public struct AgentDecision: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let allow = Self(rawValue: "allow")
    public static let ask = Self(rawValue: "ask")
    public static let deny = Self(rawValue: "deny")
    public static let unknown = Self(rawValue: "unknown")
    public static let detected = Self(rawValue: "detected")
}
public enum AgentScope: Codable, Hashable, Sendable {
    case global, project(String), path(String), network(String), server(String)
    public var identityValue: String {
        switch self {
        case .global: "global"
        case .project(let value): "project:\(value)"
        case .path(let value): "path:\(value)"
        case .network(let value): "network:\(value)"
        case .server(let value): "server:\(value)"
        }
    }
}
```

Give `AgentScope` custom Codable keys `kind` and `value`; `kind` uses `global`, `project`, `path`, `network`, or `server`, and only `global` omits `value`.

```swift
public struct AgentEvidenceSource: Codable, Hashable, Sendable {
    public enum Layer: String, Codable, Hashable, Sendable { case managed, user, profile, project, localProject, application, detection }
    public let layer: Layer
    public let safePath: String
    public let locator: String
}

public struct AgentPermissionFact: Codable, Hashable, Identifiable, Sendable {
    public let surfaceID: AgentSurfaceID
    public let capability: AgentCapability
    public let decision: AgentDecision
    public let scope: AgentScope
    public let matcher: String
    public let source: AgentEvidenceSource
    public let explanation: String

    public var id: String {
        [surfaceID.rawValue, source.layer.rawValue, source.safePath, source.locator,
         capability.rawValue, scope.identityValue, matcher].joined(separator: "|")
    }
}
```

Define coverage with typed categories and safe reason codes, never raw parser errors:

```swift
public enum AgentScanAvailability: String, Codable, Hashable, Sendable { case never, complete, degraded, failed }
public enum AgentCoverageReason: String, Codable, Hashable, Sendable {
    case unreadable, invalidSyntax, unsupportedVersion, unknownSecurityKey
    case unresolvedInclude, ambiguousPrecedence, limitExceeded, unavailableRuntimeState
}
public struct AgentCoverageIssue: Codable, Hashable, Sendable {
    public let category: String
    public let safePath: String?
    public let reason: AgentCoverageReason
}
public struct AgentCoverageReport: Codable, Hashable, Sendable {
    public let surfaceID: AgentSurfaceID
    public let supportLevel: AgentSupportLevel
    public let capturesPersistentPosture: Bool
    public let availability: AgentScanAvailability
    public let expectedCategories: [String]
    public let inspectedCategories: [String]
    public let issues: [AgentCoverageIssue]
    public let unsupportedRuntimeCategories: [String]
    public let capturedAt: Date
}
```

Define host and discovery inputs before the scanner protocols:

```swift
public struct AgentHostAssociation: Codable, Hashable, Sendable {
    public let surfaceID: AgentSurfaceID
    public let hostBundleID: String
}
public struct AgentHostEvidence: Codable, Hashable, Sendable {
    public enum Basis: String, Codable, Hashable, Sendable {
        case sameDesktopBundle, documentedIntegration, userAssociation
    }
    public let surfaceID: AgentSurfaceID
    public let permissionGrantIdentityKey: String
    public let basis: Basis
}
public enum AgentHostCoverage: String, Codable, Hashable, Sendable { case complete, unavailable }
public struct AgentDiscoveryContext: Sendable {
    public let homeDirectory: URL
    public let developerRoots: [URL]
}
```

Finish the protocols with these signatures:

```swift
public struct AgentAccessScanRequest: Sendable {
    public let homeDirectory: URL
    public let developerRoots: [URL]
}
public struct AgentAdapterResult: Sendable, Equatable {
    public let surface: AgentSurface
    public let facts: [AgentPermissionFact]
    public let coverage: AgentCoverageReport
}
public struct AgentAccessScan: Sendable, Equatable {
    public let surfaces: [AgentSurface]
    public let facts: [AgentPermissionFact]
    public let coverage: [AgentCoverageReport]
    public let hostEvidence: [AgentHostEvidence]
    public let hostCoverage: AgentHostCoverage
    public let capturedAt: Date
    public var isCompleteForHistory: Bool {
        coverage.filter(\.capturesPersistentPosture).allSatisfy { $0.availability == .complete }
    }
    public var snapshot: AgentAccessSnapshot {
        AgentAccessSnapshot(surfaces: surfaces, facts: facts, coverage: coverage, capturedAt: capturedAt)
    }
}
public struct AgentAccessSnapshot: Sendable, Equatable {
    public let surfaces: [AgentSurface]
    public let facts: [AgentPermissionFact]
    public let coverage: [AgentCoverageReport]
    public let capturedAt: Date
    public var isCompleteForHistory: Bool {
        coverage.filter(\.capturesPersistentPosture).allSatisfy { $0.availability == .complete }
    }
}
public protocol AgentConfigAdapter: Sendable {
    var vendor: AgentVendor { get }
    func scan(surface: AgentSurface, context: AgentDiscoveryContext) async -> AgentAdapterResult
}
public protocol AgentAccessScanning: Sendable {
    func scan(_ request: AgentAccessScanRequest) async throws -> AgentAccessScan
}
public protocol AgentHostCorrelating: Sendable {
    func correlate(
        surfaces: [AgentSurface],
        grants: [PermissionGrant],
        associations: [AgentHostAssociation]
    ) -> [AgentHostEvidence]
}
```

Give every public struct an explicit `public init` covering all stored properties; synthesized memberwise initializers are not public across package boundaries.

- [ ] **Step 4: Run the full core suite and commit**

```bash
swift test --package-path Packages/PermissionsCore
git add Packages/PermissionsCore/Sources/PermissionsCore/Agent*.swift \
  Packages/PermissionsCore/Tests/PermissionsCoreTests/AgentAccessModelTests.swift
git commit -m "feat: define agent access evidence contracts"
```

Expected: the complete `PermissionsCore` suite passes.

### Task 2: Add the TOML seam and bounded filesystem discovery

**Files:**
- Modify: `Packages/PermissionsScanners/Package.swift`
- Modify: `Packages/PermissionsScanners/Package.resolved`
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/AgentTOMLDecoder.swift`
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/AgentStructuredTextPreflight.swift`
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/AgentManagedPreferencesReader.swift`
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/AgentDiscovery.swift`
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentDiscoveryTests.swift`
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentTOMLDecoderTests.swift`

**Interfaces:**
- Consumes: `AgentDiscoveryContext` from Task 1.
- Produces: `AgentTOMLDecoding.decode(_:from:)`, `LiveAgentTOMLDecoder`, `AgentFileSystem`, `LiveAgentFileSystem`, `AgentManagedPreferencesReading`, `AgentDiscoveryLimits`, and bounded `AgentDiscovery.files(relativePaths:context:)`.

- [ ] **Step 1: Write failing path-boundary and decoder-seam tests**

```swift
@Test func rejectsSymlinkThatEscapesMonitoredRoot() throws {
    let fs = RecordingAgentFileSystem(files: ["/roots/repo/.codex/config.toml": .symlink("/outside/config.toml")])
    let discovery = AgentDiscovery(fileSystem: fs)
    let result = discovery.files(relativePaths: [".codex/config.toml"], context: .test(roots: [URL(fileURLWithPath: "/roots")]))
    #expect(result.files.isEmpty)
    #expect(result.issues.map(\.reason) == [.unresolvedInclude])
    #expect(fs.readPaths.isEmpty)
}

@Test func refusesFilesLargerThanOneMiBBeforeDecode() throws {
    let decoder = RecordingTOMLDecoder()
    let subject = SizeLimitedTOMLDecoder(base: decoder, maximumBytes: 1_048_576)
    #expect(throws: AgentParserError.inputTooLarge) {
        try subject.decode(TestDocument.self, from: Data(repeating: 0x20, count: 1_048_577))
    }
    #expect(decoder.decodeCount == 0)
}
```

- [ ] **Step 2: Verify the scanner tests fail before adding the dependency**

```bash
swift test --package-path Packages/PermissionsScanners --filter AgentDiscoveryTests
swift test --package-path Packages/PermissionsScanners --filter AgentTOMLDecoderTests
```

Expected: compilation fails because discovery and TOML seams do not exist.

- [ ] **Step 3: Pin TOMLDecoder and implement decode-only isolation**

Add to `Package.swift`:

```swift
.package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.5")
```

Add `.product(name: "TOMLDecoder", package: "TOMLDecoder")` only to the `PermissionsScanners` target and its test target. Resolve with:

```bash
swift package resolve --package-path Packages/PermissionsScanners
```

Implement the seam using the verified 0.4.5 API:

```swift
import TOMLDecoder

protocol AgentTOMLDecoding: Sendable {
    func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T
}

struct LiveAgentTOMLDecoder: AgentTOMLDecoding {
    func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
        try TOMLDecoder(isLenient: false).decode(type, from: data)
    }
}
```

- [ ] **Step 4: Implement bounded discovery and a filesystem spy seam**

`AgentDiscoveryLimits.foundation` must equal `(roots: 32, entriesPerRoot: 10_000, filesPerAdapter: 2_000, bytesPerFile: 1_048_576, includes: 8, decodedDepth: 64, symlinks: 16)`. Standardize every URL, resolve symlinks one hop at a time, reject a resolved target outside documented global paths or monitored roots, and enumerate only adapter-provided relative paths. Missing optional files return no issue; existing unreadable files return `.unreadable`.

Before either decoder runs, `AgentStructuredTextPreflight` tokenizes strings and comments without retaining values, then rejects more than 64 nested TOML dotted/table components or JSON arrays/objects. This enforces the depth ceiling before TOMLDecoder or Foundation allocates a decoded tree. The preflight never returns or logs input values.

```swift
protocol AgentFileSystem: Sendable {
    func itemExists(at url: URL) -> Bool
    func resolvedURL(_ url: URL, maximumHops: Int) throws -> URL
    func readData(at url: URL, maximumBytes: Int) throws -> Data
    func children(of url: URL) throws -> [URL]
}

struct AgentDiscoveryResult: Sendable, Equatable {
    let files: [DiscoveredAgentFile]
    let issues: [AgentCoverageIssue]
}

protocol AgentManagedPreferencesReading: Sendable {
    func values(applicationID: String) -> [String: SendablePropertyListValue]
}
enum SendablePropertyListValue: Sendable, Equatable {
    case string(String), bool(Bool), integer(Int), data(Data)
    case array([SendablePropertyListValue])
    case dictionary([String: SendablePropertyListValue])
}
```

The live preferences reader uses CFPreferences APIs in-process and returns only string, Boolean, integer, array, data, and dictionary property-list values. It never invokes the `defaults` command. Codex and Claude adapters select their own allowlisted security keys from this dictionary; unrelated managed preference values are discarded before normalization.

The tests must also assert that `auth.json`, `history.jsonl`, `.env`, source files, `CLAUDE.md`, transcripts, and arbitrary JSON/TOML names are never passed to `readData`.

- [ ] **Step 5: Run the scanner suite and commit**

```bash
swift test --package-path Packages/PermissionsScanners
git add Packages/PermissionsScanners/Package.swift Packages/PermissionsScanners/Package.resolved \
  Packages/PermissionsScanners/Sources/PermissionsScanners/AgentDiscovery.swift \
  Packages/PermissionsScanners/Sources/PermissionsScanners/AgentManagedPreferencesReader.swift \
  Packages/PermissionsScanners/Sources/PermissionsScanners/AgentStructuredTextPreflight.swift \
  Packages/PermissionsScanners/Sources/PermissionsScanners/AgentTOMLDecoder.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentDiscoveryTests.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentTOMLDecoderTests.swift
git commit -m "feat: add bounded agent config discovery"
```

### Task 3: Detect all foundation agent and desktop surfaces without execution

**Files:**
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/AgentSurfaceDetector.swift`
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentSurfaceDetectorTests.swift`

**Interfaces:**
- Consumes: `AgentFileSystem`, `AgentSurface`, and `AgentDiscoveryContext`.
- Produces: `AgentSurfaceDetecting.detect(context:) async -> [AgentSurface]` and `AgentSurfaceDetector`.

- [ ] **Step 1: Write the table-driven failing detection test**

```swift
@Test(arguments: [
    DetectionCase("codex", .openAI, "Codex", .cli, .full),
    DetectionCase("/Applications/Codex.app", .openAI, "Codex", .desktopApp, .full),
    DetectionCase("/Applications/ChatGPT.app", .openAI, "ChatGPT", .desktopApp, .partial),
    DetectionCase("claude", .anthropic, "Claude Code", .cli, .full),
    DetectionCase("/Applications/Claude.app", .anthropic, "Claude", .desktopApp, .partial),
    DetectionCase("cursor", .cursor, "Cursor", .ide, .detectedOnly),
    DetectionCase("gemini", .google, "Gemini CLI", .cli, .detectedOnly),
    DetectionCase("pi", .pi, "Pi", .cli, .detectedOnly),
    DetectionCase("omp", .ohMyPi, "Oh My Pi", .cli, .detectedOnly),
    DetectionCase("grok", .xAI, "Grok Build", .cli, .detectedOnly),
    DetectionCase("opencode", .openCode, "OpenCode", .cli, .detectedOnly),
    DetectionCase("copilot", .github, "GitHub Copilot CLI", .cli, .detectedOnly),
    DetectionCase("kiro-cli", .amazon, "Kiro CLI", .cli, .detectedOnly),
]) func detectsKnownSurfaceWithoutLaunchingIt(_ expected: DetectionCase) async {
    let environment = DetectionEnvironment.presentingOnly(expected.marker)
    let surfaces = await AgentSurfaceDetector(environment: environment).detect(context: .test())
    #expect(surfaces.contains { $0.vendor == expected.vendor && $0.productName == expected.name && $0.kind == expected.kind && $0.supportLevel == expected.support })
    #expect(environment.processLaunchCount == 0)
}
```

- [ ] **Step 2: Verify the focused test fails**

```bash
swift test --package-path Packages/PermissionsScanners --filter AgentSurfaceDetectorTests
```

Expected: compilation fails because the detector does not exist.

- [ ] **Step 3: Implement an allowlist-only detector**

Use known bundle identifiers, `/Applications`/`~/Applications` bundle names, executable metadata returned by the injected environment, and documented configuration presence. Current macOS aliases include `com.openai.codex`, `com.anthropic.claudefordesktop`, and `com.todesktop.230313mzl4w4u92`. Because `com.openai.codex` can present as ChatGPT or Codex depending on the installed release, inspect `CFBundleDisplayName` and `CFBundleName` and emit exactly one desktop surface for one installed bundle; never manufacture both rows from one installation.

Check executable basenames only at `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, and `~/.npm-global/bin`: `codex`, `claude`, `cursor`, `gemini`, `pi`, `omp`, `grok`, `opencode`, `copilot`, and `kiro-cli`. A generic `pi` basename requires either its resolved installation metadata to name the Pi coding agent or the allowlisted Pi configuration root; it must not classify an unrelated executable. Secondary configuration-presence markers are `~/.codex`, `~/.claude`, `~/.gemini`, `~/.pi`, `~/.omp`, `~/.grok`, `~/.config/opencode`, `~/.copilot`, and `~/.kiro`; detection checks existence only and does not read their contents.

Never search `$PATH` by launching `which`, never execute `--version`, and never open configuration content for detection. Use stable IDs of the form `vendor.product.kind:<standardized-install-or-config-root>`.

Keep Pi and Oh My Pi definitions distinct. Desktop rows carry their own bundle ID; ChatGPT and Claude desktop remain `.partial` because their foundation evidence is TCC-only.

- [ ] **Step 4: Run tests and commit**

```bash
swift test --package-path Packages/PermissionsScanners --filter AgentSurfaceDetectorTests
git add Packages/PermissionsScanners/Sources/PermissionsScanners/AgentSurfaceDetector.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentSurfaceDetectorTests.swift
git commit -m "feat: detect supported agent surfaces"
```

### Task 4: Implement authoritative Codex persistent-posture parsing

**Files:**
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/CodexConfigAdapter.swift`
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/CodexRuleParser.swift`
- Create: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/Fixtures/Codex/base-config.toml`
- Create: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/Fixtures/Codex/project-config.toml`
- Create: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/Fixtures/Codex/requirements.toml`
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/CodexConfigAdapterTests.swift`

**Interfaces:**
- Consumes: `AgentConfigAdapter`, `AgentDiscovery`, and `AgentTOMLDecoding`.
- Produces: `CodexConfigAdapter.scan(surface:context:)` with facts for approval, sandbox/permission profiles, writable roots, network, MCP approval, hooks, project trust, profile files, rules, and locally readable requirements.

- [ ] **Step 1: Write failing golden precedence and privacy tests**

```swift
@Test func requirementsConstrainProjectAndUserPosture() async {
    let result = await fixtureAdapter().scan(surface: .codexCLI, context: .codexGolden)
    #expect(result.coverage.availability == .complete)
    #expect(result.facts.contains { $0.capability == .approvalPolicy && $0.source.layer == .managed && $0.matcher == "on-request" })
    #expect(result.facts.contains { $0.capability == .sandbox && $0.scope == .project("/repo") && $0.matcher == "workspace-write" })
    #expect(result.facts.contains { $0.capability == .network && $0.decision == .allow })
}

@Test func neverEmitsCredentialOrHeaderValues() async {
    let result = await fixtureAdapter(secretValues: ["sk-fake-secret", "Bearer fake", "PRIVATE_HEADER_VALUE"]).scan(surface: .codexCLI, context: .test())
    let encoded = String(decoding: try! JSONEncoder().encode(result.facts), as: UTF8.self)
    #expect(!encoded.contains("sk-fake-secret"))
    #expect(!encoded.contains("Bearer fake"))
    #expect(!encoded.contains("PRIVATE_HEADER_VALUE"))
}
```

- [ ] **Step 2: Verify the Codex tests fail**

```bash
swift test --package-path Packages/PermissionsScanners --filter CodexConfigAdapterTests
```

Expected: compilation fails because `CodexConfigAdapter` does not exist.

- [ ] **Step 3: Implement current documented layers and explicit unknowns**

Read only these posture files:

- `~/.codex/config.toml`, `~/.codex/*.config.toml` profile files, `~/.codex/hooks.json`, and `~/.codex/rules/*.rules`;
- `<monitored-root>/**/.codex/config.toml`, adjacent `.codex/hooks.json`, and `.codex/rules/*.rules`, bounded by Task 2;
- `/etc/codex/requirements.toml`;
- the `requirements_toml_base64` value from the `com.openai.codex` managed-preferences domain, decoded in-process and subjected to the same byte/depth limits.

Never read `~/.codex/auth.json`, `history.jsonl`, logs, caches, sessions, memories, prompts, or cloud requirement caches. The current documentation does not publish a safe local path for legacy `managed_config.toml`, so do not search for it. Coverage must name cloud-managed requirements, legacy managed configuration, command-line flags, active session profile, and in-memory approvals as unavailable runtime state.

Implement scalar precedence as system requirements over project-nearest-to-root over selected profile over user. Because the active profile is session-only, emit profile facts scoped to `profile:<name>` and do not claim they are effective. Project `.codex` facts are effective only for a trusted project declared in allowlisted Codex config; otherwise mark project trust unknown. Apply documented field-specific composition for rule arrays, hooks, filesystem restrictions, and MCP entries; emit `.ambiguousPrecedence` rather than inventing a winner.

`CodexRuleParser` recognizes only the documented declarative `prefix_rule(...)` shape and extracts the command-prefix matcher plus allow/prompt/forbid decision. It never evaluates Starlark or imports. Any executable construct or unknown decision degrades rule coverage and produces no fact from that expression.

- [ ] **Step 4: Add hostile-input and unsupported-version coverage**

```swift
@Test func malformedTomlDegradesWithoutFactsFromThatLayer() async {
    let result = await fixtureAdapter(config: "approval_policy = [").scan(surface: .codexCLI, context: .test())
    #expect(result.coverage.availability == .degraded)
    #expect(result.coverage.issues.map(\.reason).contains(.invalidSyntax))
    #expect(result.facts.allSatisfy { $0.source.safePath != "~/.codex/config.toml" })
}
```

Add equivalent assertions for oversized input, include depth, decoded depth, unknown security keys, and symlink escape. Presentation-only unknown keys must keep coverage complete.

- [ ] **Step 5: Run the scanner suite and commit**

```bash
swift test --package-path Packages/PermissionsScanners
git add Packages/PermissionsScanners/Sources/PermissionsScanners/CodexConfigAdapter.swift \
  Packages/PermissionsScanners/Sources/PermissionsScanners/CodexRuleParser.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/CodexConfigAdapterTests.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/Fixtures/Codex
git commit -m "feat: interpret codex persistent permissions"
```

### Task 5: Implement authoritative Claude Code persistent-posture parsing

**Files:**
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/ClaudeCodeConfigAdapter.swift`
- Create: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/Fixtures/Claude/user-settings.json`
- Create: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/Fixtures/Claude/project-settings.json`
- Create: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/Fixtures/Claude/local-settings.json`
- Create: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/Fixtures/Claude/managed-settings.json`
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/ClaudeCodeConfigAdapterTests.swift`

**Interfaces:**
- Consumes: `AgentConfigAdapter` and `AgentDiscovery`.
- Produces: `ClaudeCodeConfigAdapter.scan(surface:context:)` with allow/ask/deny rules, permission mode, bypass restrictions, additional directories, sandbox, trust, MCP posture, hooks, and managed restrictions.

- [ ] **Step 1: Write failing deny-first, layer-precedence, and redaction tests**

```swift
@Test func denyWinsOverAskAndAllowForTheSameMatcher() async {
    let result = await fixtureAdapter().scan(surface: .claudeCode, context: .claudeGolden)
    let facts = result.facts.filter { $0.capability == .toolRule && $0.matcher == "Bash(curl *)" }
    #expect(facts.contains { $0.decision == .deny && $0.source.layer == .managed })
    #expect(facts.contains { $0.decision == .ask })
    #expect(facts.contains { $0.decision == .allow })
    #expect(result.coverage.availability == .complete)
}

@Test func mcpCredentialsAndHookCommandsNeverEnterFacts() async {
    let result = await secretFixtureAdapter().scan(surface: .claudeCode, context: .test())
    let data = try! JSONEncoder().encode(result.facts)
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("FAKE_TOKEN"))
    #expect(!text.contains("curl https://private.example"))
}
```

- [ ] **Step 2: Verify the Claude tests fail**

```bash
swift test --package-path Packages/PermissionsScanners --filter ClaudeCodeConfigAdapterTests
```

Expected: compilation fails because the Claude adapter does not exist.

- [ ] **Step 3: Implement current documented paths and precedence**

Read only:

- `/Library/Application Support/ClaudeCode/managed-settings.d/*.json` then `managed-settings.json`;
- allowlisted posture keys from the `com.anthropic.claudecode` managed-preferences domain;
- `~/.claude/settings.json`;
- `<monitored-root>/**/.claude/settings.json` and `.claude/settings.local.json`;
- `<monitored-root>/**/.mcp.json`;
- the posture-bearing `projects.<standardized-path>.mcpServers` entries inside `~/.claude.json`, while discarding all non-MCP app/session state and all server values.

Managed settings outrank local project, shared project, then user settings. Arrays such as `permissions.allow`, `permissions.ask`, `permissions.deny`, and sandbox write paths merge and deduplicate across scopes; rule evaluation is deny, ask, allow. Represent hook presence, event, matcher, and handler type, but never command, prompt, URL, headers, or arguments. Represent MCP server identity, transport category, scope, and approval restriction, but never URLs containing credentials, headers, environment values, or command arguments.

Server-managed and endpoint-managed settings are not locally authoritative without reading managed delivery/auth state; report them as unsupported runtime categories. `--settings`, `--add-dir`, command-line permission modes, session `/permissions`, and in-memory trust remain unknown.

- [ ] **Step 4: Prove malformed and ambiguous inputs degrade only Claude**

```swift
@Test func invalidProjectJsonKeepsUserFactsButDegradesCoverage() async {
    let result = await fixtureAdapter(projectJSON: Data("{".utf8)).scan(surface: .claudeCode, context: .test())
    #expect(result.coverage.availability == .degraded)
    #expect(result.facts.contains { $0.source.layer == .user })
    #expect(result.facts.allSatisfy { $0.source.layer != .project })
}
```

Add explicit assertions for managed drop-in ordering, missing optional files, unreadable referenced `.mcp.json`, unsupported permission modes, unknown security keys, symlink escape, file and depth ceilings, and broad `additionalDirectories` facts.

- [ ] **Step 5: Run the scanner suite and commit**

```bash
swift test --package-path Packages/PermissionsScanners
git add Packages/PermissionsScanners/Sources/PermissionsScanners/ClaudeCodeConfigAdapter.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/ClaudeCodeConfigAdapterTests.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/Fixtures/Claude
git commit -m "feat: interpret claude code persistent permissions"
```

### Task 6: Correlate host evidence and aggregate independent adapters

**Files:**
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/AgentHostCorrelator.swift`
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/AgentAccessScanner.swift`
- Create: `Packages/PermissionsScanners/Sources/PermissionsScanners/MockAgentAccessScanner.swift`
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentHostCorrelatorTests.swift`
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentAccessScannerTests.swift`

**Interfaces:**
- Consumes: detector and adapters for scanning; `PermissionGrant` and explicit `AgentHostAssociation` values only for the separate pure correlator.
- Produces: an `AgentHostCorrelating` implementation plus concrete/mock `AgentAccessScanning` implementations. The scanner returns posture with empty host evidence and `.unavailable` host coverage; the app coordinator attaches fresh host context after its concurrent system scan completes.

- [ ] **Step 1: Write failing no-inference and failure-isolation tests**

```swift
@Test func terminalGrantDoesNotImplyClaudeOrCodexUse() {
    let evidence = AgentHostCorrelator().correlate(surfaces: [.codexCLI, .claudeCode], grants: [.terminalFullDiskAccess], associations: [])
    #expect(evidence.isEmpty)
}

@Test func explicitAssociationCarriesItsVisibleBasis() {
    let association = AgentHostAssociation(surfaceID: .codexCLI.id, hostBundleID: "com.apple.Terminal")
    let evidence = AgentHostCorrelator().correlate(surfaces: [.codexCLI], grants: [.terminalFullDiskAccess], associations: [association])
    #expect(evidence.map(\.basis) == [.userAssociation])
}

@Test func claudeFailureDoesNotEraseCompleteCodexEvidence() async throws {
    let scan = try await scanner(codex: .complete, claude: .failed).scan(.test())
    #expect(scan.facts.contains { $0.surfaceID == .codexCLI.id })
    #expect(scan.coverage.first { $0.surfaceID == .claudeCode.id }?.availability == .failed)
    #expect(!scan.isCompleteForHistory)
}
```

- [ ] **Step 2: Verify focused tests fail**

```bash
swift test --package-path Packages/PermissionsScanners --filter AgentHostCorrelatorTests
swift test --package-path Packages/PermissionsScanners --filter AgentAccessScannerTests
```

- [ ] **Step 3: Implement evidence-basis-only correlation**

`AgentHostEvidence` stores `surfaceID`, the referenced TCC `PermissionGrant.identityKey`, and basis `.sameDesktopBundle`, `.documentedIntegration`, or `.userAssociation`. Same-bundle matching is exact bundle ID. Documented integration entries are a static allowlist with source comments. User associations require both the configured surface ID and exact host bundle ID. TCC failure is represented by absent host evidence plus an independent host-context status; it does not degrade agent configuration coverage. `AgentHostCorrelator` conforms to `AgentHostCorrelating` and performs no filesystem work.

- [ ] **Step 4: Aggregate adapters with deterministic ordering and stale-safe output**

Run Codex and Claude adapters concurrently with a cap of two; detection-only surfaces receive complete detection coverage and no permission facts. Sort surfaces by vendor/product/kind/ID and facts by stable ID. Each nonthrowing adapter catches its own parser/filesystem errors and returns safe failed or degraded coverage without raw parser messages; only a scanner-wide discovery failure throws. The scanner sets host evidence to `[]` and host coverage to `.unavailable`; it never consumes stale TCC input. `MockAgentAccessScanner` accepts a fixed `AgentAccessScan` or safe `ScannerError` and never becomes the production default.

- [ ] **Step 5: Run scanner tests and commit**

```bash
swift test --package-path Packages/PermissionsScanners
git add Packages/PermissionsScanners/Sources/PermissionsScanners/AgentHostCorrelator.swift \
  Packages/PermissionsScanners/Sources/PermissionsScanners/AgentAccessScanner.swift \
  Packages/PermissionsScanners/Sources/PermissionsScanners/MockAgentAccessScanner.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentHostCorrelatorTests.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/AgentAccessScannerTests.swift
git commit -m "feat: aggregate agent access evidence"
```

### Task 7: Migrate the snapshot store to schema v6 and persist secret-free evidence

**Files:**
- Modify: `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift`
- Create: `Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotV5Fixture.swift`
- Create: `Packages/PermissionsStore/Tests/PermissionsStoreTests/AgentAccessPersistenceTests.swift`
- Modify: `Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotRetentionTests.swift`

**Interfaces:**
- Consumes: normalized Codable core models.
- Produces: schema v6, `writeFullSnapshot(..., agentAccess: AgentAccessSnapshot?)`, `readAgentAccess(snapshotID:)`, and captured-baseline lookup.

- [ ] **Step 1: Write failing v5 migration, round-trip, and redaction tests**

```swift
@Test func v5MigratesWithAgentAccessUncaptured() async throws {
    let store = try SnapshotV5Fixture.migratedStore()
    #expect(try store.schemaVersion() == 6)
    let oldID = try #require(await store.latestSnapshotID())
    #expect(try await store.agentAccessCaptured(snapshotID: oldID) == false)
}

@Test func completeAgentEvidenceRoundTripsWithoutRawConfiguration() async throws {
    let store = try SnapshotStore.inMemory()
    let id = try await store.writeFullSnapshot(grants: [], launchAgents: [], btmItems: [], agentAccess: AgentAccessScan.fixtureComplete.snapshot, at: .fixture)
    #expect(try await store.readAgentAccess(snapshotID: id) == AgentAccessScan.fixtureComplete.snapshot)
    #expect(try await store.unsafeAgentRawTextMatches(["sk-fake", "Bearer fake", "hook command"]) == [])
}
```

- [ ] **Step 2: Verify store tests fail**

```bash
swift test --package-path Packages/PermissionsStore --filter AgentAccessPersistenceTests
```

- [ ] **Step 3: Add the v6 migration and atomic write contract**

Add `snapshots.agent_access_captured INTEGER NOT NULL DEFAULT 0`, plus:

```sql
CREATE TABLE agent_surfaces (
  snapshot_id INTEGER NOT NULL REFERENCES snapshots(id) ON DELETE CASCADE,
  surface_id TEXT NOT NULL, vendor TEXT NOT NULL, product_name TEXT NOT NULL,
  surface_kind TEXT NOT NULL, support_level TEXT NOT NULL,
  bundle_id TEXT, installation_path TEXT, configuration_root TEXT,
  PRIMARY KEY (snapshot_id, surface_id)
);
CREATE TABLE agent_permission_facts (
  snapshot_id INTEGER NOT NULL REFERENCES snapshots(id) ON DELETE CASCADE,
  surface_id TEXT NOT NULL, fact_id TEXT NOT NULL, capability TEXT NOT NULL,
  decision TEXT NOT NULL, scope_json TEXT NOT NULL, matcher TEXT NOT NULL,
  source_layer TEXT NOT NULL, safe_source_path TEXT NOT NULL,
  safe_locator TEXT NOT NULL, explanation TEXT NOT NULL,
  PRIMARY KEY (snapshot_id, surface_id, fact_id),
  FOREIGN KEY (snapshot_id, surface_id)
    REFERENCES agent_surfaces(snapshot_id, surface_id) ON DELETE CASCADE
);
CREATE TABLE agent_coverage (
  snapshot_id INTEGER NOT NULL REFERENCES snapshots(id) ON DELETE CASCADE,
  surface_id TEXT NOT NULL, report_json TEXT NOT NULL,
  PRIMARY KEY (snapshot_id, surface_id),
  FOREIGN KEY (snapshot_id, surface_id)
    REFERENCES agent_surfaces(snapshot_id, surface_id) ON DELETE CASCADE
);
```

Update `schema_version` to 6. `writeFullSnapshot` accepts `agentAccess: AgentAccessSnapshot?`; nil writes marker `0` and no agent rows, nonnil requires `isCompleteForHistory`, writes marker `1`, and inserts all rows in the existing transaction. Do not persist host evidence by duplicating TCC; rebuild it live from current TCC evidence.

- [ ] **Step 4: Verify cascade retention and duplicate rejection**

Extend `unsafeChildRowCounts` with agent surface/fact/coverage counts. Assert pruning deletes all three, duplicate fact IDs fail atomically, and no partial parent row remains after a child insert error.

- [ ] **Step 5: Run store tests and commit**

```bash
swift test --package-path Packages/PermissionsStore
git add Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift \
  Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotV5Fixture.swift \
  Packages/PermissionsStore/Tests/PermissionsStoreTests/AgentAccessPersistenceTests.swift \
  Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotRetentionTests.swift
git commit -m "feat: persist agent access snapshots in schema v6"
```

### Task 8: Add captured-only Agent Access drift semantics

**Files:**
- Create: `Packages/PermissionsStore/Sources/PermissionsStore/AgentAccessDiff.swift`
- Modify: `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift`
- Test: `Packages/PermissionsStore/Tests/PermissionsStoreTests/AgentAccessDiffTests.swift`

**Interfaces:**
- Produces: `AgentAccessDiff`, `AgentCoverageChange`, `diffAgentAccess(from:to:)`, and `latestAgentAccessSnapshotID(atOrBefore:)`.
- Consumed by: Tasks 10 and 13.

- [ ] **Step 1: Write failing captured-baseline and identity tests**

```swift
@Test func uncapturedSnapshotIsNeverAnAgentBaseline() async throws {
    let store = try SnapshotStore.inMemory()
    _ = try await store.writeFullSnapshot(grants: [], launchAgents: [], btmItems: [], agentAccess: .capturedA, at: .dayOne)
    _ = try await store.writeFullSnapshot(grants: [], launchAgents: [], btmItems: [], agentAccess: nil, at: .dayTwo)
    let latest = try await store.latestAgentAccessSnapshotID(atOrBefore: .dayTwo)
    #expect(latest == SnapshotID(rawValue: 1))
}

@Test func matcherChangeIsRemovalPlusAddition() async throws {
    let diff = try await fixtureStore().diffAgentAccess(from: .beforeMatcher, to: .afterMatcher)
    #expect(diff.addedFacts.count == 1)
    #expect(diff.removedFacts.count == 1)
    #expect(diff.changedFacts.isEmpty)
}
```

- [ ] **Step 2: Verify red tests**

```bash
swift test --package-path Packages/PermissionsStore --filter AgentAccessDiffTests
```

- [ ] **Step 3: Implement deterministic diff structures**

```swift
public struct AgentAccessDiff: Sendable, Equatable {
    public let addedSurfaces: [AgentSurface]
    public let removedSurfaces: [AgentSurface]
    public let addedFacts: [AgentPermissionFact]
    public let removedFacts: [AgentPermissionFact]
    public let changedFacts: [DomainChange<AgentPermissionFact>]
    public let coverageChanges: [AgentCoverageChange]
    public var hasContent: Bool { !addedSurfaces.isEmpty || !removedSurfaces.isEmpty || !addedFacts.isEmpty || !removedFacts.isEmpty || !changedFacts.isEmpty || !coverageChanges.isEmpty }
}
```

Compare facts by `id`; decision or explanation changes produce `DomainChange`, while scope/matcher/source changes produce remove/add. Coverage changes never become permission grants. Reject `diffAgentAccess` when either marker is false with `StoreError.agentAccessNotCaptured(snapshotID:)`.

- [ ] **Step 4: Run store tests and commit**

```bash
swift test --package-path Packages/PermissionsStore
git add Packages/PermissionsStore/Sources/PermissionsStore/AgentAccessDiff.swift \
  Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift \
  Packages/PermissionsStore/Tests/PermissionsStoreTests/AgentAccessDiffTests.swift
git commit -m "feat: diff complete agent access captures"
```

### Task 9: Persist monitored roots and explicit host associations

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesStore.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesViewModel.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesWindowView.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/PreferencesStoreTests.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/PreferencesViewModelTests.swift`

**Interfaces:**
- Produces: `PreferencesStore.agentDeveloperRoots`, `PreferencesStore.agentHostAssociations`, standardized add/remove APIs, and the Agent Access preferences tab.
- Consumed by: Task 10.

- [ ] **Step 1: Write failing standardization, cap, and duplicate tests**

```swift
@Test func rootsStandardizeDeduplicateAndCapAtThirtyTwo() {
    let store = PreferencesStore(defaults: isolatedDefaults())
    #expect(store.addAgentDeveloperRoot(URL(fileURLWithPath: "/work/a/../repo")))
    #expect(!store.addAgentDeveloperRoot(URL(fileURLWithPath: "/work/repo")))
    for index in 1...31 { #expect(store.addAgentDeveloperRoot(URL(fileURLWithPath: "/work/r\(index)"))) }
    #expect(!store.addAgentDeveloperRoot(URL(fileURLWithPath: "/work/overflow")))
    #expect(store.agentDeveloperRoots.count == 32)
}
```

- [ ] **Step 2: Verify UI package tests fail**

```bash
swift test --package-path Packages/PermissionsUI --filter PreferencesStoreTests
```

- [ ] **Step 3: Add bundle-prefixed persistence and pure APIs**

Use keys:

```swift
public static let agentDeveloperRootsKey = "com.wallymagill.permissionpulse.agentDeveloperRoots"
public static let agentHostAssociationsKey = "com.wallymagill.permissionpulse.agentHostAssociations"
```

Persist standardized path strings and JSON-encoded `AgentHostAssociation` values. Reject non-file URLs, filesystem root `/`, the current user's home directory, `/System`, `/Library`, and paths that do not exist as directories. Removing a root updates preferences immediately; history remains untouched.

- [ ] **Step 4: Add a fifth Agent Access preferences tab**

Use `NSOpenPanel` through a small AppKit bridge because SwiftUI has no directory picker; include `// AppKit: directory selection for an explicitly monitored developer root`. Show roots with remove buttons, detected surfaces/support levels supplied by `AppViewModel`, association pickers for CLI surface plus installed host bundle, inspected/omitted category summaries, the configuration-file privacy exception, and runtime/cloud limitations. All actions are keyboard reachable and localized.

- [ ] **Step 5: Run UI tests and commit**

```bash
swift test --package-path Packages/PermissionsUI
git add Packages/PermissionsUI/Sources/PermissionsUI/PreferencesStore.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/PreferencesViewModel.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/PreferencesWindowView.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/PreferencesStoreTests.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/PreferencesViewModelTests.swift
git commit -m "feat: configure agent access discovery roots"
```

### Task 10: Coordinate live Agent Access scans and independent snapshots

**Files:**
- Create: `PermissionPulse/PermissionPulse/AgentAccessCoordinator.swift`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift`
- Modify: `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift`
- Modify: `PermissionPulse/PermissionPulse.xcodeproj/project.pbxproj`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/SnapshotDiffs.swift`
- Test: `PermissionPulse/PermissionPulseTests/AgentAccessCoordinatorTests.swift`
- Modify: `PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AgentAccessScanning`, `AgentHostCorrelating`, preferences, live TCC grants, schema v6, and Agent Access diff APIs.
- Produces: live/stale Agent Access view-model state and captured-only yesterday/week Agent Access diffs.

- [ ] **Step 1: Write failing coordinator isolation and same-day recovery tests**

```swift
@Test func failedAgentScanKeepsLastKnownFactsLabeledStale() async {
    let vm = AppViewModel(agentAccessScan: .completeFixture)
    let coordinator = AgentAccessCoordinator(viewModel: vm, scanner: FailingAgentScanner(), hostCorrelator: RecordingHostCorrelator())
    await coordinator.runScan(request: .test())
    #expect(vm.agentAccessScan?.facts == AgentAccessScan.completeFixture.facts)
    #expect(vm.agentAccessAvailability.isFailed)
}

@Test func sameDayRecoveryDoesNotRewriteUncapturedSnapshot() async throws {
    let harness = SnapshotHarness(firstAgentAvailability: .degraded)
    await harness.coordinator.onScanCompleted()
    harness.publishCompleteAgentScan()
    await harness.coordinator.onScanCompleted()
    #expect(try await harness.store.snapshotCount() == 1)
    #expect(try await harness.store.agentAccessCaptured(snapshotID: .first) == false)
}
```

- [ ] **Step 2: Verify app tests fail**

```bash
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/AgentAccessCoordinatorTests \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 3: Publish dedicated view-model state**

Add `agentAccessScan: AgentAccessScan?`, `agentAccessAvailability: AgentScanAvailability`, `agentAccessLastSuccessful: Date?`, `agentAccessIssues: [AgentCoverageIssue]`, `agentAccessDiffYesterday: AgentAccessDiff?`, and `agentAccessDiffWeek: AgentAccessDiff?`. On failure retain the previous scan, set failed/stale state, and show no facts when no success exists. Do not feed Agent Access failure into existing FDA/BTM attention precedence; Permission Debt and Agent Access coverage own their page/badge state.

- [ ] **Step 4: Run system and Agent Access scans concurrently**

`AppDelegate` creates `AgentAccessCoordinator(viewModel:scanner:hostCorrelator:)`. At initial scan and rescan, start `ScanCoordinator.runScan()` and Agent Access scanning with one `async let` boundary; the Agent Access request contains only the home directory and current standardized roots. After both tasks return, correlate the newly detected surfaces with the newly completed TCC grants and current associations, then publish one final `AgentAccessScan`. Set host coverage to `.complete` only when the TCC scan completed; otherwise attach no host evidence and `.unavailable`. Never rescan configuration files merely to add host context, and never correlate against stale grants.

- [ ] **Step 5: Preserve existing snapshots while gating only Agent Access rows**

Keep `scanFullySucceeded()` as the existing TCC/BTM/LaunchAgent gate. Pass `agentAccess: viewModel.agentAccessScan?.snapshot` only when `agentAccessAvailability == .complete` and `scan.isCompleteForHistory`; otherwise pass nil. Compute existing diffs from normal baselines and Agent Access diffs from `latestAgentAccessSnapshotID(atOrBefore:)`. Same-day guard remains before any write.

- [ ] **Step 6: Run app and package suites and commit**

```bash
swift test --package-path Packages/PermissionsUI
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
git add PermissionPulse/PermissionPulse/AgentAccessCoordinator.swift \
  PermissionPulse/PermissionPulse/PermissionPulseApp.swift \
  PermissionPulse/PermissionPulse/SnapshotCoordinator.swift \
  PermissionPulse/PermissionPulse.xcodeproj/project.pbxproj \
  PermissionPulse/PermissionPulseTests/AgentAccessCoordinatorTests.swift \
  PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/SnapshotDiffs.swift
git commit -m "feat: coordinate agent access history"
```

### Task 11: Derive deterministic, score-free Permission Debt

**Files:**
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/PermissionDebt.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/PermissionDebtTests.swift`

**Interfaces:**
- Produces: `PermissionDebtFinding`, `PermissionDebtReason`, and `PermissionDebt.derive(scan:fileExists:)`.
- Consumed by: the Agent Access page. Permission Debt remains a UI-derived current projection and does not cross into Core persistence, history, digest, or export APIs.

- [ ] **Step 1: Write failing reason-code and no-score tests**

```swift
@Test(arguments: [
    DebtCase(.bypassMode, .bypassOrNeverAsk),
    DebtCase(.homeWritableRoot, .broadWritableRoot),
    DebtCase(.broadShellRule, .broadShellApproval),
    DebtCase(.unrestrictedNetwork, .unrestrictedNetwork),
    DebtCase(.blanketMCP, .blanketMCPApproval),
    DebtCase(.commandHook, .commandRunningHook),
    DebtCase(.homeTrust, .broadTrustedDirectory),
    DebtCase(.missingTrustedPath, .missingTrustedPath),
]) func mapsEvidenceToOneFactualReason(_ testCase: DebtCase) {
    let findings = PermissionDebt.derive(scan: testCase.scan, fileExists: testCase.fileExists)
    #expect(findings.map(\.reason).contains(testCase.expected))
    #expect(findings.allSatisfy { !$0.explanation.localizedCaseInsensitiveContains("score") })
}
```

- [ ] **Step 2: Verify focused tests fail**

```bash
swift test --package-path Packages/PermissionsUI --filter PermissionDebtTests
```

- [ ] **Step 3: Implement pure, evidence-backed derivation**

```swift
public struct PermissionDebtFinding: Identifiable, Sendable, Equatable {
    public let reason: PermissionDebtReason
    public let factID: String
    public let surfaceID: AgentSurfaceID
    public let explanation: String
    public var id: String { "\(reason.rawValue)|\(factID)" }
}
```

Derive only the approved reason list. Broad-root rules must use standardized path components, not substring matching. A powerful desktop TCC finding requires `AgentHostEvidence`; a separate desktop surface holding TCC may be shown on its own without implying CLI use. Ambiguous security evidence produces `.manualReview`. Detected-only surfaces never create findings.

- [ ] **Step 4: Run UI tests and commit**

```bash
swift test --package-path Packages/PermissionsUI
git add Packages/PermissionsUI/Sources/PermissionsUI/PermissionDebt.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/PermissionDebtTests.swift
git commit -m "feat: derive agent permission debt findings"
```

### Task 12: Build Agent Access navigation, page, and inspector

**Files:**
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/AgentAccess/AgentAccessPresentation.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/AgentAccess/AgentAccessPage.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/AgentAccess/AgentAccessInspector.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/Navigation/AppRoute.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/Navigation/InspectorSelection.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/AgentAccessPresentationTests.swift`
- Modify: `Packages/PermissionsUI/Tests/PermissionsUITests/AppRouteTests.swift`
- Modify: `Packages/PermissionsUI/Tests/PermissionsUITests/InspectorContentResolverTests.swift`

**Interfaces:**
- Consumes: current scan, Permission Debt findings, host evidence, and coverage.
- Produces: conditional `.agentAccess` sidebar route, vendor-group view models, fact selection, and read-only inspector actions.

- [ ] **Step 1: Write failing grouping, search, navigation, and inspector tests**

```swift
@Test func groupsVendorFamilyButKeepsSurfacesSeparate() {
    let groups = AgentAccessPresentation.groups(scan: .openAIFixture, searchText: "")
    #expect(groups.first?.vendor == .openAI)
    #expect(groups.first?.surfaces.map(\.surface.productName) == ["ChatGPT", "Codex", "Codex"])
    #expect(Set(groups.first!.surfaces.map(\.surface.kind)) == [.cli, .desktopApp])
}

@Test func searchIncludesMatcherRepositoryAndSafeSourcePath() {
    #expect(AgentAccessPresentation.groups(scan: .fixture, searchText: "Bash(git *)").flatMap(\.surfaces).isEmpty == false)
    #expect(AgentAccessPresentation.groups(scan: .fixture, searchText: "/repo").flatMap(\.surfaces).isEmpty == false)
    #expect(AgentAccessPresentation.groups(scan: .fixture, searchText: ".claude/settings.json").flatMap(\.surfaces).isEmpty == false)
}
```

- [ ] **Step 2: Verify UI tests fail**

```bash
swift test --package-path Packages/PermissionsUI --filter AgentAccessPresentationTests
```

- [ ] **Step 3: Add conditional navigation and focused page composition**

Add `.agentAccess` to `SidebarItem` but build sidebar items dynamically: include it only when `viewModel.agentAccessScan?.surfaces.isEmpty == false`. Preferences remains available regardless. The page order is coverage summary, Needs Review, then vendor groups. Every surface shows support and availability separately. Detected-only rows say permission interpretation is not yet available and emit no findings.

Keep `AgentAccessPage.body` below 60 lines by extracting `AgentCoverageHeader`, `PermissionDebtSection`, `AgentVendorSection`, and `AgentSurfaceRow`.

- [ ] **Step 4: Add evidence-rich read-only inspector behavior**

Extend `InspectorSelection` with `.agentFact(String)` and resolve the stable fact ID from current scan. Inspector fields are surface, capability, decision, scope, matcher, source layer, safe path, coverage, uncertainty, relationship basis, and historical context. Actions are limited to `NSWorkspace.shared.activateFileViewerSelecting`, `SystemSettingsLink`, documented safe deep links opened through `NSWorkspace.open`, or localized manual instructions. No command execution and no CLI launch.

- [ ] **Step 5: Run UI tests and commit**

```bash
swift test --package-path Packages/PermissionsUI
git add Packages/PermissionsUI/Sources/PermissionsUI/AgentAccess \
  Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/Navigation/AppRoute.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/Navigation/InspectorSelection.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/AgentAccessPresentationTests.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/AppRouteTests.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/InspectorContentResolverTests.swift
git commit -m "feat: add agent access detail experience"
```

### Task 13: Integrate Agent Access into changes, dismissals, badges, and digest

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffEntryKey.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift`
- Modify: `PermissionPulse/PermissionPulse/WeeklyDigestCoordinator.swift`
- Modify: `Packages/PermissionsUI/Tests/PermissionsUITests/DiffEntryKeyTests.swift`
- Modify: `Packages/PermissionsUI/Tests/PermissionsUITests/WhatChangedViewModelTests.swift`
- Modify: `PermissionPulse/PermissionPulseTests/WeeklyDigestCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AgentAccessDiff` and existing dismissal store.
- Produces: stable Agent Access change rows, unified search/count/review behavior, and weekly totals.

- [ ] **Step 1: Write failing count, key, search, and digest tests**

```swift
@Test func agentFactChangeUsesStableSemanticDismissalKey() {
    let key = DiffEntryKey.key(for: .agentFactChanged(.fixture))
    #expect(key == "agent-changed|openai.codex.cli:user|approval-policy|global|on-request")
    #expect(!key.contains("snapshot"))
}

@Test func recentChangeCountIncludesAgentEvents() {
    let vm = AppViewModel(agentAccessDiffYesterday: .fixtureWithSixEvents)
    #expect(vm.recentChangeEventCount == 6)
}

@Test func digestIncludesAgentAddsRemovesAndChanges() {
    let body = coordinator().composeDigestBody(diff: .systemEmpty, agentDiff: .oneOfEach).body
    #expect(body.contains("1 added"))
    #expect(body.contains("1 removed"))
    #expect(body.contains("1 changed"))
}
```

- [ ] **Step 2: Verify focused tests fail**

```bash
swift test --package-path Packages/PermissionsUI --filter DiffEntryKeyTests
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/WeeklyDigestCoordinatorTests CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 3: Add every Agent Access event kind**

Add surface added/removed, fact added/removed/changed, and coverage-changed cases. Permission rows use plus/minus/change indicators; coverage rows use warning styling and never count as grants. Search uses the rendered summary plus vendor, product, capability, decision, matcher, scope, repository, and safe path. Dismissal keys use stable surface/fact identity and event kind, never explanation or snapshot ID.

- [ ] **Step 4: Keep review and digest counts semantically aligned**

`SnapshotDiffs` continues carrying system diffs; `AppViewModel.activeAgentDiff` chooses yesterday then week using the same fallback rule. `hasUnreviewedChanges`, menu badge, Recent Changes sections, and digest totals count the exact event categories rendered. Coverage events appear in Recent Changes but do not increment added/removed permission totals; include them as changed in the digest.

- [ ] **Step 5: Run UI and app tests and commit**

```bash
swift test --package-path Packages/PermissionsUI
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
git add Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/DiffEntryKey.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/DiffEntryKeyTests.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/WhatChangedViewModelTests.swift \
  PermissionPulse/PermissionPulse/WeeklyDigestCoordinator.swift \
  PermissionPulse/PermissionPulseTests/WeeklyDigestCoordinatorTests.swift
git commit -m "feat: surface agent access changes"
```

### Task 14: Export normalized Agent Access facts and coverage safely

**Files:**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/PermissionsExport.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/ExportToolbar.swift`
- Modify: `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionsExportTests.swift`

**Interfaces:**
- Produces: `ExportAgentSurface`, `ExportAgentFact`, `ExportAgentCoverage`, and Agent Access JSON/Markdown sections.

- [ ] **Step 1: Write failing normalized-export and secret-negative tests**

```swift
@Test func exportContainsNormalizedAgentEvidenceAndCoverage() throws {
    let report = PermissionsExport.report(grants: [], launchAgents: [], btmItems: [], staleApps: [], agentAccess: .fixture, generatedAt: .fixture)
    #expect(report.agentSurfaces.count == 2)
    #expect(report.agentFacts.first?.matcher == "Bash(git *)")
    #expect(report.agentCoverage.first?.availability == "complete")
}

@Test func exportNeverContainsFixtureSecrets() throws {
    let data = try PermissionsExport.makeJSON(report: .secretFixture)
    let text = String(decoding: data, as: UTF8.self)
    for secret in ["sk-fake", "Bearer fake", "PRIVATE_HEADER_VALUE", "hook command"] {
        #expect(!text.contains(secret))
    }
}
```

- [ ] **Step 2: Verify core export tests fail**

```bash
swift test --package-path Packages/PermissionsCore --filter PermissionsExportTests
```

- [ ] **Step 3: Add normalized DTOs and Markdown tables**

Export product/vendor/kind/support, capability/decision/scope/matcher/safe source/locator/explanation, and coverage categories/issues. Never export host relationships or TCC evidence, raw configuration, or UI-derived Permission Debt findings. Escape pipes/newlines through the existing `cell` helper. `ExportToolbar` passes only the snapshot-safe surfaces, facts, and coverage from the current Agent Access scan.

- [ ] **Step 4: Run core and UI suites and commit**

```bash
swift test --package-path Packages/PermissionsCore
swift test --package-path Packages/PermissionsUI
git add Packages/PermissionsCore/Sources/PermissionsCore/PermissionsExport.swift \
  Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionsExportTests.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/ExportToolbar.swift
git commit -m "feat: export normalized agent access evidence"
```

### Task 15: Complete reset, schema verification, public documentation, and release gates

**Files:**
- Modify: `PermissionPulse/PermissionPulse/ResetAllDataService.swift`
- Modify: `PermissionPulse/PermissionPulseTests/ResetAllDataServiceTests.swift`
- Modify: `scripts/verify-snapshot-schema.sh`
- Modify: `scripts/tests/snapshot-schema-verifier-test.sh`
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/00-vision.md`
- Modify: `docs/02-scope.md`
- Modify: `docs/03-architecture.md`
- Modify: `docs/04-data-sources.md`
- Modify: `docs/05-permissions.md`
- Modify: `docs/08-risks.md`
- Modify: `docs/09-roadmap.md`

**Interfaces:**
- Consumes: all completed feature contracts.
- Produces: reset-safe live state, v6 external verification, public trust documentation, and recorded manual-gate evidence.

- [ ] **Step 1: Write failing reset and v6 verifier tests**

```swift
@Test func resetClearsAgentHistoryPreferencesDismissalsAndLiveState() async {
    let harness = ResetHarness.withAgentAccessData()
    #expect(await harness.service.reset() == .completed(scanSucceeded: true))
    #expect(harness.viewModel.agentAccessScan == nil)
    #expect(harness.preferences.agentDeveloperRoots.isEmpty)
    #expect(harness.preferences.agentHostAssociations.isEmpty)
    #expect(harness.defaults.object(forKey: PreferencesStore.agentDeveloperRootsKey) == nil)
}
```

Extend the shell fixture to require migration ledger `v1,v2,v3,v4,v5,v6`, `agent_access_captured`, all three agent tables/columns, boolean capture markers, foreign keys, and read-only verification. Add corrupt fixtures for missing v6 ledger, partial table shape, invalid marker, and orphan agent rows.

- [ ] **Step 2: Verify reset and verifier tests fail**

```bash
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/ResetAllDataServiceTests CODE_SIGNING_ALLOWED=NO
bash scripts/tests/snapshot-schema-verifier-test.sh
```

- [ ] **Step 3: Clear all Agent Access state during reset**

Clear scan, availability, coverage issues, yesterday/week agent diffs, derived debt, roots, host associations, and Agent Access dismissal keys before rescanning. Existing prefix-based defaults clearing remains the final persistence guarantee.

- [ ] **Step 4: Update the public trust contract**

Document the narrow configuration-file exception verbatim: Permission Pulse reads only documented, allowlisted agent configuration/policy files to extract permission posture; never source, documents, prompts, transcripts, sessions, credentials, auth stores, arbitrary files, or raw secret values. Document all ten detected families, full Codex/Claude Code coverage, separate desktop TCC evidence, bounded roots, schema v6, degraded behavior, same-day history rule, and TOMLDecoder's MIT license/dependency boundary. Add an unversioned “Agent Access Foundation” roadmap entry; do not change the release number.

- [ ] **Step 5: Resolve Xcode dependencies and run every automated gate**

```bash
xcodebuild -resolvePackageDependencies \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse
swift test --package-path Packages/PermissionsCore
swift test --package-path Packages/PermissionsScanners
swift test --package-path Packages/PermissionsStore
swift test --package-path Packages/PermissionsUI
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
bash scripts/tests/snapshot-schema-verifier-test.sh
bash scripts/tests/smoke-test-safety-test.sh
bash scripts/tests/release-verifier-test.sh
git diff --check
```

Expected: all four SwiftPM suites, the app/unit/UI test invocation, all shell verifier suites, and whitespace validation pass. Confirm both `Packages/PermissionsScanners/Package.resolved` and `PermissionPulse/PermissionPulse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` pin TOMLDecoder 0.4.5.

- [ ] **Step 6: Run and record the real-Mac manual gates**

On a Mac with current Codex and Claude Code installations:

1. Compare detected sources and normalized facts with each product's own permission UI and current official documentation.
2. Change one persistent permission and verify it appears only in the next eligible complete daily diff.
3. Confirm Codex, ChatGPT, Claude, Terminal, and IDE TCC rows remain separately attributed.
4. Confirm every host relationship displays its evidence basis.
5. Inspect `snapshots.db`, Console logs, delivered notification content, dismissal defaults, and JSON/Markdown exports for the fake secret corpus.
6. Confirm no agent configuration timestamp/content changes and no agent process launches during scan.
7. Repeat with FDA granted and denied; host context may degrade while configuration evidence remains valid.
8. Record the date, macOS build, Codex version, Claude Code version, FDA state, and PASS/FAIL for each gate in the Agent Access roadmap entry.

- [ ] **Step 7: Commit the completion slice**

```bash
git add PermissionPulse/PermissionPulse/ResetAllDataService.swift \
  PermissionPulse/PermissionPulseTests/ResetAllDataServiceTests.swift \
  PermissionPulse/PermissionPulse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
  scripts/verify-snapshot-schema.sh scripts/tests/snapshot-schema-verifier-test.sh \
  README.md CLAUDE.md docs/00-vision.md docs/02-scope.md docs/03-architecture.md \
  docs/04-data-sources.md docs/05-permissions.md docs/08-risks.md docs/09-roadmap.md
git commit -m "docs: complete agent access foundation gates"
```

Do not claim release readiness when any real-Mac gate is unrecorded or failing.
