import Foundation
import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct LastUsedProbeTests {
    @Test func mockReturnsFixedDate() async {
        let path = URL(fileURLWithPath: "/Applications/Zoom.app")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let probe = MockLastUsedProbe(fixed: [path: (fixedDate, .spotlight)])
        let result = await probe.lastUsedDate(for: path)
        #expect(result?.date == fixedDate)
        #expect(result?.source == .spotlight)
    }

    @Test func mockReturnsNilForUnknownPath() async {
        let probe = MockLastUsedProbe(fixed: [:])
        let result = await probe.lastUsedDate(for: URL(fileURLWithPath: "/Applications/Unknown.app"))
        #expect(result == nil)
    }

    @Test func hybridProbeFallsBackToFileSystemWhenSpotlightMissing() async throws {
        // Create a real temp file with a known modification date. Spotlight will
        // almost certainly return (null) for /tmp paths, exercising the fallback.
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("permission-pulse-stale-probe-\(UUID().uuidString)")
        try Data().write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Set a fixed mtime in the past (90+ days).
        let pastDate = Date(timeIntervalSinceNow: -100 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: pastDate],
            ofItemAtPath: tempURL.path(percentEncoded: false)
        )

        let probe = LastUsedProbeHybrid()
        let result = await probe.lastUsedDate(for: tempURL)
        // Either Spotlight returned something (uncommon for /tmp), or the
        // file-system fallback kicked in. Both are acceptable; we just need a
        // non-nil result here on a real file we know exists.
        #expect(result != nil)
        if let result {
            // If we hit the file-system fallback, the date matches what we set
            // (within a 1-second tolerance for filesystem rounding).
            if result.source == .fileSystem {
                let delta = abs(result.date.timeIntervalSince(pastDate))
                #expect(delta < 1.0)
            }
        }
    }
}
