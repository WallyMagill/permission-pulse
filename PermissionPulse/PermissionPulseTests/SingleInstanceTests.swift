import Foundation
import Testing
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct SingleInstanceTests {
    private let appURL = URL(fileURLWithPath: "/Applications/Permission Pulse.app")
    private let otherURL = URL(fileURLWithPath: "/Users/me/Downloads/Permission Pulse.app")
    private let built = Date(timeIntervalSince1970: 1_000)

    private func instance(_ pid: pid_t, at url: URL? = nil, launched seconds: TimeInterval?) -> RunningInstance {
        RunningInstance(pid: pid, bundleURL: url ?? appURL, launchDate: seconds.map { Date(timeIntervalSince1970: $0) })
    }

    private func decide(
        current: RunningInstance,
        others: [RunningInstance],
        relaunchedFrom: pid_t? = nil
    ) -> SingleInstanceDecision {
        SingleInstanceDecision.decide(
            current: current,
            executableModified: built,
            others: others,
            relaunchedFrom: relaunchedFrom,
            now: Date(timeIntervalSince1970: 3_000)
        )
    }

    @Test func aloneProceeds() {
        #expect(decide(current: instance(500, launched: 3_000), others: []) == .proceed)
    }

    @Test func aRunningCopyOfThisCodeIsHandedOffTo() {
        let running = instance(412, launched: 2_000)
        #expect(decide(current: instance(500, launched: 3_000), others: [running]) == .handOff(to: 412))
    }

    @Test func aCopyFromAnotherPathIsReplaced() {
        let running = instance(412, at: otherURL, launched: 2_000)
        #expect(decide(current: instance(500, launched: 3_000), others: [running]) == .replace(waitFor: nil, terminate: [412]))
    }

    @Test func aCopyLaunchedBeforeTheAppWasReplacedOnDiskIsReplaced() {
        let running = instance(412, launched: 500)
        #expect(decide(current: instance(500, launched: 3_000), others: [running]) == .replace(waitFor: nil, terminate: [412]))
    }

    @Test func aCopyWithUnknownLaunchDateIsReplacedRatherThanTrusted() {
        let running = instance(412, launched: nil)
        #expect(decide(current: instance(500, launched: 3_000), others: [running]) == .replace(waitFor: nil, terminate: [412]))
    }

    // A copy run directly from its executable has no Launch Services launch
    // date; it must not sort ahead of a copy already running.
    @Test func thisCopyWithNoLaunchDateStillHandsOffToAnEarlierCopy() {
        let running = instance(412, launched: 2_000)
        #expect(decide(current: instance(500, launched: nil), others: [running]) == .handOff(to: 412))
    }

    @Test func anotherCopyWithNoStartTimeIsReplacedNotLeftRunning() {
        let running = instance(600, launched: nil)
        #expect(decide(current: instance(500, launched: nil), others: [running]) == .replace(waitFor: nil, terminate: [600]))
    }

    @Test func processStartTimeIsReadForAProcessLaunchServicesDidNotStart() throws {
        let start = try #require(SingleInstanceGuard.processStartTime(ProcessInfo.processInfo.processIdentifier))
        #expect(start <= Date())
        #expect(start > Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime - 60))
        #expect(SingleInstanceGuard.processStartTime(-1) == nil)
    }

    // A rename keeps the executable's dates; the bundle directory's change
    // date must still mark the code as newer than a copy launched earlier.
    @Test func renamingTheAppIntoPlaceCountsAsANewBuild() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = root.appendingPathComponent("Staged.app")
        let macOS = staged.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: macOS.appendingPathComponent("PermissionPulse"))
        let executableDates = try #require(SingleInstanceGuard.codeModificationDate(
            bundleURL: URL(fileURLWithPath: "/nonexistent"),
            executableURL: macOS.appendingPathComponent("PermissionPulse")
        ))
        try await Task.sleep(for: .milliseconds(50))
        let installed = root.appendingPathComponent("Permission Pulse.app")
        try FileManager.default.moveItem(at: staged, to: installed)

        let modified = try #require(SingleInstanceGuard.codeModificationDate(
            bundleURL: URL(fileURLWithPath: installed.path),
            executableURL: URL(fileURLWithPath: installed.path + "/Contents/MacOS/PermissionPulse")
        ))
        #expect(modified > executableDates)
    }

    @Test func twoCopiesLaunchedTogetherAgreeTheEarlierContinues() {
        let first = instance(600, launched: 3_000)
        let second = instance(500, launched: 3_001)
        #expect(decide(current: first, others: [second]) == .proceed)
        #expect(decide(current: second, others: [first]) == .handOff(to: 600))
    }

    @Test func equalLaunchDatesFallBackToTheLowerProcessID() {
        let low = instance(500, launched: 3_000)
        let high = instance(600, launched: 3_000)
        #expect(decide(current: low, others: [high]) == .proceed)
        #expect(decide(current: high, others: [low]) == .handOff(to: 500))
    }

    @Test func aDifferentCopyLaunchedLaterIsLeftToReplaceThisOne() {
        let later = instance(600, at: otherURL, launched: 3_001)
        #expect(decide(current: instance(500, launched: 3_000), others: [later]) == .proceed)
        #expect(decide(current: later, others: [instance(500, launched: 3_000)]) == .replace(waitFor: nil, terminate: [500]))
    }

    @Test func relaunchWaitsForTheProcessItReplaces() {
        let current = instance(500, launched: 3_000)
        #expect(decide(current: current, others: [instance(412, launched: 2_000)], relaunchedFrom: 412)
            == .replace(waitFor: 412, terminate: []))
        #expect(decide(current: current, others: [], relaunchedFrom: 412) == .proceed)
    }

    @Test func relaunchStillHandsOffToAThirdCopyOfThisCode() {
        let others = [instance(412, launched: 2_000), instance(977, launched: 2_500)]
        #expect(decide(current: instance(500, launched: 3_000), others: others, relaunchedFrom: 412) == .handOff(to: 977))
    }

    @Test func aReusedProcessIDCountsAsExited() {
        let ours = "com.wallymagill.permissionpulse"
        #expect(SingleInstanceDecision.hasExited(isTerminated: false, bundleIdentifier: "com.example.other", expected: ours))
        #expect(SingleInstanceDecision.hasExited(isTerminated: nil, bundleIdentifier: nil, expected: ours))
        #expect(SingleInstanceDecision.hasExited(isTerminated: true, bundleIdentifier: ours, expected: ours))
        #expect(!SingleInstanceDecision.hasExited(isTerminated: false, bundleIdentifier: ours, expected: ours))
    }

    @Test func relaunchArgumentRoundTrips() {
        let arguments = ["/Applications/Permission Pulse.app/Contents/MacOS/PermissionPulse", AppRelauncher.relaunchedFromArgument, "412"]
        #expect(AppRelauncher.relaunchedFromPID(in: arguments) == 412)
        #expect(AppRelauncher.relaunchedFromPID(in: [AppRelauncher.relaunchedFromArgument]) == nil)
        #expect(AppRelauncher.relaunchedFromPID(in: ["-NSDocumentRevisionsDebugMode", "YES"]) == nil)
    }
}
