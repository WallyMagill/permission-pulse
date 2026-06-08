import Foundation
import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct LaunchAgentScannerFSTests {
    @Test func scanReadsThreeValidPlists() async throws {
        let dir = try TempDir()
        try dir.write(filename: "good1.plist", contents: PlistFixtures.runAtLoad(label: "com.test.one"))
        try dir.write(filename: "good2.plist", contents: PlistFixtures.runAtLoad(label: "com.test.two"))
        try dir.write(filename: "good3.plist", contents: PlistFixtures.runAtLoad(label: "com.test.three"))

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let items = try await scanner.scan()

        #expect(items.count == 3)
        let labels = Set(items.map(\.label))
        #expect(labels == ["com.test.one", "com.test.two", "com.test.three"])
    }

    @Test func scanSkipsMalformedPlist() async throws {
        let dir = try TempDir()
        try dir.write(filename: "good1.plist", contents: PlistFixtures.runAtLoad(label: "com.test.alpha"))
        try dir.write(filename: "good2.plist", contents: PlistFixtures.runAtLoad(label: "com.test.beta"))
        try dir.write(filename: "good3.plist", contents: PlistFixtures.runAtLoad(label: "com.test.gamma"))
        try dir.write(filename: "bad.plist", contents: Data("not a plist".utf8))

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let items = try await scanner.scan()

        #expect(items.count == 3)
        #expect(!items.contains { $0.label.contains("bad") })
    }

    @Test func scanDefaultsMissingKeys() async throws {
        let dir = try TempDir()
        try dir.write(filename: "minimal.plist", contents: PlistFixtures.minimal(label: "com.test.minimal"))

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let items = try await scanner.scan()

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.label == "com.test.minimal")
        #expect(item.runAtLoad == false)
        #expect(item.keepAlive == false)
        #expect(item.programArguments.isEmpty)
        #expect(item.programPath == "/usr/local/bin/foo")
    }

    @Test func scanHandlesDictKeepAlive() async throws {
        let dir = try TempDir()
        try dir.write(filename: "dict.plist", contents: PlistFixtures.dictKeepAlive(label: "com.test.dict"))

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let items = try await scanner.scan()

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.label == "com.test.dict")
        // A dict-valued KeepAlive (e.g. {NetworkState=true}) is an active
        // keep-alive policy — not false. This assertion was wrong before D4. (D4)
        #expect(item.keepAlive == true)
    }

    @Test func disabledKeyIsDecoded() async throws {
        let dir = try TempDir()
        try dir.write(
            filename: "disabled.plist",
            contents: PlistFixtures.disabled(label: "com.test.disabled")
        )

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let items = try await scanner.scan()

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.isDisabled == true)
    }

    @Test func scanReturnsEmptyForMissingDirectory() async throws {
        let dir = try TempDir()
        let nonexistent = dir.url.appendingPathComponent("does-not-exist", isDirectory: true)
        let source = LaunchAgentScannerFS.Source(
            url: nonexistent,
            category: .userLaunchAgents
        )

        let scanner = LaunchAgentScannerFS(sources: [source])
        let items = try await scanner.scan()

        #expect(items.isEmpty)
    }

    @Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil))
    func scanThrowsPermissionDeniedWhenDirectoryUnreadable() async throws {
        let dir = try TempDir()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: dir.url.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: dir.url.path
            )
        }

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        do {
            _ = try await scanner.scan()
            Issue.record("Expected scan to throw")
        } catch let error as ScannerError {
            guard case .permissionDenied = error else {
                Issue.record("Expected .permissionDenied, got \(error)")
                return
            }
        }
    }

    @Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil))
    func scanReturnsPartialResultsWhenOneSourceUnreadable() async throws {
        let readable = try TempDir()
        try readable.write(filename: "good.plist", contents: PlistFixtures.runAtLoad(label: "com.test.partial"))
        let unreadable = try TempDir()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: unreadable.url.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: unreadable.url.path
            )
        }

        let scanner = LaunchAgentScannerFS(sources: [
            readable.asSource(.userLaunchAgents),
            unreadable.asSource(.libraryLaunchAgents),
        ])
        let items = try await scanner.scan()

        #expect(items.count == 1)
        #expect(items.first?.label == "com.test.partial")
    }

    @Test func scanAssignsCorrectSourceDirectory() async throws {
        let userDir = try TempDir()
        let daemonDir = try TempDir()
        try userDir.write(filename: "u.plist", contents: PlistFixtures.runAtLoad(label: "com.test.user"))
        try daemonDir.write(filename: "d.plist", contents: PlistFixtures.runAtLoad(label: "com.test.daemon"))

        let scanner = LaunchAgentScannerFS(sources: [
            userDir.asSource(.userLaunchAgents),
            daemonDir.asSource(.libraryLaunchDaemons),
        ])
        let items = try await scanner.scan()

        #expect(items.count == 2)
        let userItem = try #require(items.first { $0.label == "com.test.user" })
        let daemonItem = try #require(items.first { $0.label == "com.test.daemon" })
        #expect(userItem.sourceDirectory == .userLaunchAgents)
        #expect(daemonItem.sourceDirectory == .libraryLaunchDaemons)
    }
}

private final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ppulse-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(filename: String, contents: Data) throws {
        try contents.write(to: url.appendingPathComponent(filename))
    }

    func asSource(_ category: LaunchAgentItem.SourceDirectory) -> LaunchAgentScannerFS.Source {
        LaunchAgentScannerFS.Source(url: url, category: category)
    }
}

private enum PlistFixtures {
    static func runAtLoad(label: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>Program</key><string>/usr/local/bin/foo</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/foo</string>
                <string>--flag</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><false/>
        </dict>
        </plist>
        """.utf8)
    }

    static func minimal(label: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>Program</key><string>/usr/local/bin/foo</string>
        </dict>
        </plist>
        """.utf8)
    }

    static func dictKeepAlive(label: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>Program</key><string>/usr/local/bin/foo</string>
            <key>KeepAlive</key>
            <dict>
                <key>NetworkState</key><true/>
            </dict>
        </dict>
        </plist>
        """.utf8)
    }

    // Disabled = true: launchd does not load this job (it stays registered
    // but unloaded). We surface it so a disabled agent isn't read as active.
    static func disabled(label: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>Program</key><string>/usr/local/bin/foo</string>
            <key>Disabled</key><true/>
        </dict>
        </plist>
        """.utf8)
    }
}
