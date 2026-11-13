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
        let items = try await scanner.scan().items

        #expect(items.count == 3)
        let labels = Set(items.map(\.label))
        #expect(labels == ["com.test.one", "com.test.two", "com.test.three"])
    }

    @Test func unparseablePlistIsListedWithoutDetails() async throws {
        let dir = try TempDir()
        try dir.write(filename: "good1.plist", contents: PlistFixtures.runAtLoad(label: "com.test.alpha"))
        try dir.write(filename: "com.test.bad.plist", contents: Data("not a plist".utf8))

        let scanner = scanner(dir, ageSeconds: LaunchAgentScannerFS.settlingInterval)
        let output = try await scanner.scan()

        #expect(output.warnings.isEmpty)
        let bad = try #require(output.items.first { $0.label == "com.test.bad" })
        #expect(bad.detailsReadable == false)
        #expect(bad.fileName == "com.test.bad.plist")
        #expect(bad.programPath == nil && bad.programArguments.isEmpty)
        #expect(bad.runAtLoad == false && bad.keepAlive == false)
        #expect(output.items.first { $0.label == "com.test.alpha" }?.detailsReadable == true)
    }

    // A root-only 0700 daemon plist (NordVPN's helper) must not degrade the
    // domain forever; it is listed by file name with details unknown.
    @Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil))
    func permissionDeniedPlistIsListedWithoutDetails() async throws {
        let dir = try TempDir()
        try dir.write(filename: "com.test.locked.plist", contents: PlistFixtures.runAtLoad(label: "com.test.inner"))
        let locked = dir.url.appendingPathComponent("com.test.locked.plist")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.libraryLaunchDaemons)])
        let output = try await scanner.scan()

        #expect(output.warnings.isEmpty)
        let item = try #require(output.items.first)
        #expect(output.items.count == 1)
        #expect(item.label == "com.test.locked")
        #expect(item.detailsReadable == false)
    }

    @Test func permissionDeniedClassificationFollowsUnderlyingPOSIXError() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileReadUnknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: posix]
        )
        #expect(LaunchAgentScannerFS.isPermissionDenied(CocoaError(.fileReadNoPermission)))
        #expect(LaunchAgentScannerFS.isPermissionDenied(wrapped))
        #expect(!LaunchAgentScannerFS.isPermissionDenied(CocoaError(.fileReadNoSuchFile)))
        #expect(!LaunchAgentScannerFS.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))))
    }

    @Test func danglingSymlinkIsInert() async throws {
        let dir = try TempDir()
        try dir.write(filename: "good.plist", contents: PlistFixtures.runAtLoad(label: "com.test.alpha"))
        try FileManager.default.createSymbolicLink(
            at: dir.url.appendingPathComponent("gone.plist"),
            withDestinationURL: dir.url.appendingPathComponent("missing-target.plist")
        )

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let output = try await scanner.scan()

        #expect(output.items.map(\.label) == ["com.test.alpha"])
        #expect(output.warnings.isEmpty)
    }

    @Test func otherReadErrorsStillOmitWithWarning() async throws {
        let dir = try TempDir()
        try FileManager.default.createDirectory(
            at: dir.url.appendingPathComponent("folder.plist"),
            withIntermediateDirectories: false
        )

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let output = try await scanner.scan()

        #expect(output.items.isEmpty)
        #expect(output.warnings == [ScannerWarning(source: .entries, omittedCount: 1, omittedNames: ["folder.plist"])])
    }

    @Test func wrongTypedOptionalKeyDoesNotDropTheJob() async throws {
        let dir = try TempDir()
        try dir.write(filename: "odd.plist", contents: PlistFixtures.integerProgram(label: "com.test.odd"))

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let output = try await scanner.scan()

        #expect(output.warnings.isEmpty)
        let item = try #require(output.items.first)
        #expect(item.label == "com.test.odd")
        #expect(item.detailsReadable)
        #expect(item.programPath == nil)
        #expect(item.programArguments == ["/usr/local/bin/odd", "--run"])
        #expect(item.runAtLoad == true)
    }

    @Test func fileNameIsTheNameOnDisk() async throws {
        let dir = try TempDir()
        try dir.write(filename: "Renamed Helper.plist", contents: PlistFixtures.runAtLoad(label: "com.test.helper"))

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let item = try #require(try await scanner.scan().items.first)

        #expect(item.label == "com.test.helper")
        #expect(item.fileName == "Renamed Helper.plist")
        #expect(item.id == "userLaunchAgents|com.test.helper")
    }

    // Verified on a real Mac: com.logitech.LogiRightSight.Agent has no
    // Disabled key but is `true` in disabled.501.plist.
    @Test func launchdOverrideDatabaseDecidesDisabledPerDomain() async throws {
        let agents = try TempDir()
        let daemons = try TempDir()
        let overrides = try TempDir()
        try agents.write(filename: "a.plist", contents: PlistFixtures.runAtLoad(label: "com.test.agent"))
        try agents.write(filename: "b.plist", contents: PlistFixtures.disabled(label: "com.test.reenabled"))
        try daemons.write(filename: "d.plist", contents: PlistFixtures.disabled(label: "com.test.daemon"))
        try overrides.write(filename: "disabled.501.plist", contents: PlistFixtures.overrides([
            "com.test.agent": true,
            "com.test.reenabled": false,
            "com.test.daemon": false,
        ]))

        let scanner = LaunchAgentScannerFS(
            sources: [agents.asSource(.userLaunchAgents), daemons.asSource(.libraryLaunchDaemons)],
            overrideDirectory: overrides.url,
            userID: 501
        )
        let items = try await scanner.scan().items
        let disabled = Dictionary(uniqueKeysWithValues: items.map { ($0.label, $0.isDisabled) })

        #expect(disabled["com.test.agent"] == true)
        #expect(disabled["com.test.reenabled"] == false)
        // No system-domain file exists, so the daemon falls back to its plist key.
        #expect(disabled["com.test.daemon"] == true)
    }

    @Test func systemOverrideAppliesToLaunchDaemons() async throws {
        let daemons = try TempDir()
        let overrides = try TempDir()
        try daemons.write(filename: "d.plist", contents: PlistFixtures.runAtLoad(label: "com.test.daemon"))
        try overrides.write(filename: "disabled.plist", contents: PlistFixtures.overrides(["com.test.daemon": true]))

        let scanner = LaunchAgentScannerFS(
            sources: [daemons.asSource(.libraryLaunchDaemons)],
            overrideDirectory: overrides.url,
            userID: 501
        )
        let item = try #require(try await scanner.scan().items.first)
        #expect(item.isDisabled == true)
    }

    // Google Keystone leaves empty `{}` plists behind; launchd won't load a
    // label-less file, so it is not an agent and must not degrade the scan.
    @Test func labelLessPlistIsInertNotOmitted() async throws {
        let dir = try TempDir()
        try dir.write(filename: "good.plist", contents: PlistFixtures.runAtLoad(label: "com.test.alpha"))
        try dir.write(filename: "empty.plist", contents: PlistFixtures.emptyDictionary)

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let output = try await scanner.scan()

        #expect(output.items.map(\.label) == ["com.test.alpha"])
        #expect(output.warnings.isEmpty)
    }

    // A plist caught mid-write by an installer must not appear as a phantom
    // item for one scan, nor degrade coverage: it is ignored until it settles.
    @Test func freshUnparseablePlistIsIgnoredForThisScan() async throws {
        let dir = try TempDir()
        try dir.write(filename: "good.plist", contents: PlistFixtures.runAtLoad(label: "com.test.alpha"))
        try dir.write(filename: "com.test.writing.plist", contents: Data("<?xml version=".utf8))

        let output = try await scanner(dir, ageSeconds: LaunchAgentScannerFS.settlingInterval - 1).scan()

        #expect(output.items.map(\.label) == ["com.test.alpha"])
        #expect(output.warnings.isEmpty)
    }

    @Test func nonStringLabelIsListedWithoutDetailsOnceSettled() async throws {
        let dir = try TempDir()
        try dir.write(filename: "bad-label.plist", contents: PlistFixtures.integerLabel)

        let young = try await scanner(dir, ageSeconds: 5).scan()
        let settled = try await scanner(dir, ageSeconds: LaunchAgentScannerFS.settlingInterval).scan()

        #expect(young.items.isEmpty)
        #expect(young.warnings.isEmpty)
        let item = try #require(settled.items.first)
        #expect(settled.warnings.isEmpty)
        #expect(item.label == "bad-label")
        #expect(item.detailsReadable == false)
    }

    @Test func settledNonDictionaryPlistIsListedWithoutDetails() async throws {
        let dir = try TempDir()
        let array = try PropertyListSerialization.data(fromPropertyList: ["a"], format: .xml, options: 0)
        try dir.write(filename: "com.test.array.plist", contents: array)

        let output = try await scanner(dir, ageSeconds: 3600).scan()

        #expect(output.items.map(\.label) == ["com.test.array"])
        #expect(output.items.first?.detailsReadable == false)
        #expect(output.warnings.isEmpty)
    }

    // A modification date that cannot be read can never settle, so it must
    // not keep the domain degraded forever.
    @Test func unknownModificationDateCountsAsSettled() async throws {
        let dir = try TempDir()
        try dir.write(filename: "com.test.bad.plist", contents: Data("not a plist".utf8))

        let scanner = LaunchAgentScannerFS(
            sources: [dir.asSource(.userLaunchAgents)],
            modificationDate: { _ in nil }
        )
        let output = try await scanner.scan()

        #expect(output.items.map(\.label) == ["com.test.bad"])
        #expect(output.warnings.isEmpty)
    }

    @Test func scanDefaultsMissingKeys() async throws {
        let dir = try TempDir()
        try dir.write(filename: "minimal.plist", contents: PlistFixtures.minimal(label: "com.test.minimal"))

        let scanner = LaunchAgentScannerFS(sources: [dir.asSource(.userLaunchAgents)])
        let items = try await scanner.scan().items

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
        let items = try await scanner.scan().items

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
        let items = try await scanner.scan().items

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
        let output = try await scanner.scan()

        #expect(output.items.isEmpty)
        #expect(output.warnings.isEmpty)
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

    @Test func scanRetainsItemsAndReportsWarningWhenOneExistingSourceFails() async throws {
        let readable = try TempDir()
        try readable.write(filename: "good.plist", contents: PlistFixtures.runAtLoad(label: "com.test.partial"))
        let invalidDirectory = try TempDir()
        let existingFile = invalidDirectory.url.appendingPathComponent("not-a-directory")
        try Data().write(to: existingFile)

        let scanner = LaunchAgentScannerFS(sources: [
            readable.asSource(.userLaunchAgents),
            LaunchAgentScannerFS.Source(
                url: existingFile,
                category: .libraryLaunchAgents
            ),
        ])
        let output = try await scanner.scan()

        #expect(output.items.count == 1)
        #expect(output.items.first?.label == "com.test.partial")
        #expect(output.warnings == [
            ScannerWarning(source: .libraryLaunchAgents, omittedCount: nil),
        ])
    }

    @Test func scanThrowsDeterministicErrorWhenAllExistingSourcesFail() async throws {
        let dir = try TempDir()
        let firstFile = dir.url.appendingPathComponent("first-not-a-directory")
        let secondFile = dir.url.appendingPathComponent("second-not-a-directory")
        try Data().write(to: firstFile)
        try Data().write(to: secondFile)
        let scanner = LaunchAgentScannerFS(sources: [
            LaunchAgentScannerFS.Source(
                url: firstFile,
                category: .userLaunchAgents
            ),
            LaunchAgentScannerFS.Source(
                url: secondFile,
                category: .libraryLaunchDaemons
            ),
        ])

        let firstError = await scannerError(from: scanner)
        let secondError = await scannerError(from: scanner)

        #expect(firstError == .permissionDenied(
            reason: "A LaunchAgents directory could not be read."
        ))
        #expect(secondError == firstError)
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
        let items = try await scanner.scan().items

        #expect(items.count == 2)
        let userItem = try #require(items.first { $0.label == "com.test.user" })
        let daemonItem = try #require(items.first { $0.label == "com.test.daemon" })
        #expect(userItem.sourceDirectory == .userLaunchAgents)
        #expect(daemonItem.sourceDirectory == .libraryLaunchDaemons)
    }
}

/// A scanner whose clock reads `ageSeconds` after every file's modification date.
private func scanner(_ dir: TempDir, ageSeconds: TimeInterval) -> LaunchAgentScannerFS {
    let modified = Date(timeIntervalSince1970: 1_700_000_000)
    return LaunchAgentScannerFS(
        sources: [dir.asSource(.userLaunchAgents)],
        now: { modified.addingTimeInterval(ageSeconds) },
        modificationDate: { _ in modified }
    )
}

private func scannerError(from scanner: LaunchAgentScannerFS) async -> ScannerError? {
    do {
        _ = try await scanner.scan()
        Issue.record("Expected scan to throw")
        return nil
    } catch let error as ScannerError {
        return error
    } catch {
        Issue.record("Expected ScannerError, got \(error)")
        return nil
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
    static let emptyDictionary = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict/>
        </plist>
        """.utf8)

    static let integerLabel = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><integer>7</integer>
        </dict>
        </plist>
        """.utf8)

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

    static func integerProgram(label: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>Program</key><integer>42</integer>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/odd</string>
                <string>--run</string>
            </array>
            <key>RunAtLoad</key><true/>
        </dict>
        </plist>
        """.utf8)
    }

    static func overrides(_ table: [String: Bool]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: table, format: .xml, options: 0)
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
