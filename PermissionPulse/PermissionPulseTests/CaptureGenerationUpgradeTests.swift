import Foundation
import GRDB
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

/// The first scan after upgrading compares a snapshot written by the old
/// capture rules with one written by the new rules. Recent Changes, the
/// badge and change alerts must not report what only the new rules capture.
@Suite @MainActor struct CaptureGenerationUpgradeTests {
    @Test func upgradeScanShowsNoChangesAndPostsNoAlert() async throws {
        let env = try await UpgradeEnvironment(baselineGeneration: 1)
        defer { env.cleanUp() }

        let (written, alert) = try await env.scanWithNewRules()

        #expect(written != nil, "The first scan after upgrading writes a current-generation baseline")
        #expect(env.viewModel.latestDiffSinceReview?.entries.isEmpty == true)
        #expect(env.viewModel.latestDiffWeek?.entries.isEmpty == true)
        #expect(!env.viewModel.hasUnreviewedChanges)
        #expect(alert == nil)
    }

    @Test func theSameDifferencesBetweenCurrentSnapshotsAreChanges() async throws {
        let env = try await UpgradeEnvironment(baselineGeneration: CaptureGeneration.current)
        defer { env.cleanUp() }

        let (_, alert) = try await env.scanWithNewRules()

        let entries = try #require(env.viewModel.latestDiffSinceReview?.entries)
        #expect(entries.map(\.domain) == [.tcc, .launchAgents])
        guard case .launchAgentFlipped(let change)? = entries.last else {
            Issue.record("Expected a launch agent change, got \(entries)")
            return
        }
        #expect(change.before.isDisabled == false && change.after.isDisabled == true)
        #expect(change.before.programArguments.isEmpty && !change.after.programArguments.isEmpty)
        #expect(alert?.body.hasPrefix("2 changes:") == true)
    }
}

@MainActor
private final class UpgradeEnvironment {
    nonisolated private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let agentLabel = "com.logitech.LogiRightSight.Agent"

    let directory: URL
    let store: SnapshotStore
    let viewModel: AppViewModel
    let coordinator: SnapshotCoordinator
    private let baseline: SnapshotID

    init(baselineGeneration: Int) async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-generation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("snapshots.db").path(percentEncoded: false)
        store = try SnapshotStore(path: path)
        viewModel = AppViewModel(
            tccAvailability: .complete(lastUpdated: Self.now),
            btmAvailability: .complete(lastUpdated: Self.now),
            launchAgentAvailability: .complete(lastUpdated: Self.now)
        )
        coordinator = SnapshotCoordinator(
            viewModel: viewModel,
            store: store,
            lastUsedProbe: MockLastUsedProbe(),
            defaults: UserDefaults(suiteName: "capture-generation-\(UUID().uuidString)")!,
            now: { Self.now }
        )
        baseline = try await store.writeFullSnapshot(
            grants: [Self.grant("com.example.app", .accessibility)],
            launchAgents: [Self.agent(arguments: [], disabled: false)],
            btmItems: [],
            at: Self.now.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        // Rows migrated from v6 carry generation 1; simulate one.
        let queue = try DatabaseQueue(path: path)
        try await queue.write { [baseline] db in
            try db.execute(
                sql: "UPDATE snapshots SET capture_generation = ? WHERE id = ?",
                arguments: [baselineGeneration, baseline.rawValue]
            )
        }
    }

    /// A scan with a Remote Desktop grant, an agent disabled only in
    /// launchd's override database, and repaired program arguments.
    func scanWithNewRules() async throws -> (SnapshotID?, ChangeAlert?) {
        viewModel.grants = [
            Self.grant("com.example.app", .accessibility),
            Self.grant("com.p5sys.jump.connect", .remoteDesktop),
        ]
        viewModel.launchAgents = [Self.agent(arguments: ["/bin/agent", "--quiet"], disabled: true)]
        await coordinator.onScanCompleted()
        let latest = try await store.latestSnapshotID()
        let written = latest == baseline ? nil : latest
        guard let written else { return (nil, nil) }
        let changes = await coordinator.changes(from: baseline, to: written)
        return (written, ChangeAlert.make(for: changes, dismissals: nil, asOf: Self.now))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func grant(_ bundleID: String, _ service: PermissionService) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID),
            lastModified: now
        )
    }

    private static func agent(arguments: [String], disabled: Bool) -> LaunchAgentItem {
        LaunchAgentItem(
            label: agentLabel,
            sourceDirectory: .userLaunchAgents,
            programPath: "/Applications/Logi.app/agent",
            programArguments: arguments,
            runAtLoad: true,
            keepAlive: false,
            isDisabled: disabled
        )
    }
}
