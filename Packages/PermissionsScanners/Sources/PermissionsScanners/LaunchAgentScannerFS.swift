import Foundation
import OSLog
import PermissionsCore

public struct LaunchAgentScannerFS: LaunchAgentScanner, Sendable {
    struct Source: Sendable {
        let url: URL
        let category: LaunchAgentItem.SourceDirectory
    }

    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "scanners.launchagent"
    )

    /// A guess, sized well above the moment an installer takes to write a
    /// plist: a malformed file younger than this may still be mid-write.
    static let settlingInterval: TimeInterval = 60

    private let sources: [Source]
    private let overrideDirectory: URL?
    private let userID: uid_t
    private let now: @Sendable () -> Date
    private let modificationDate: @Sendable (URL) -> Date?

    public init() {
        self.init(sources: Self.defaultSources(), overrideDirectory: LaunchdDisabledOverrides.defaultDirectory)
    }

    /// `overrideDirectory: nil` ignores launchd's disabled-override database.
    init(
        sources: [Source],
        overrideDirectory: URL? = nil,
        userID: uid_t = getuid(),
        now: @escaping @Sendable () -> Date = Date.init,
        modificationDate: @escaping @Sendable (URL) -> Date? = Self.fileModificationDate
    ) {
        self.sources = sources
        self.overrideDirectory = overrideDirectory
        self.userID = userID
        self.now = now
        self.modificationDate = modificationDate
    }

    public func scan() async throws -> ScannerOutput<LaunchAgentItem> {
        var items: [LaunchAgentItem] = []
        var firstFailure: (any Error)?
        var warnings: [ScannerWarning] = []
        var omittedFileNames: [String] = []
        var anyExistingSourceSucceeded = false
        let overrides = LaunchdDisabledOverrides.load(from: overrideDirectory, userID: userID)
        for source in sources {
            do {
                switch try scanDirectory(source, overrides: overrides) {
                case .absent:
                    break
                case .scanned(let sourceItems, let sourceOmittedFileNames):
                    items.append(contentsOf: sourceItems)
                    omittedFileNames += sourceOmittedFileNames
                    anyExistingSourceSucceeded = true
                }
            } catch {
                if firstFailure == nil { firstFailure = error }
                warnings.append(ScannerWarning(source: Self.scannerSource(for: source.category)))
            }
        }
        if !anyExistingSourceSucceeded, let firstFailure {
            throw firstFailure
        }
        if !omittedFileNames.isEmpty {
            warnings.append(ScannerWarning(
                source: .entries,
                omittedCount: omittedFileNames.count,
                omittedNames: omittedFileNames.sorted()
            ))
        }
        let sortedItems = items.sorted {
            if $0.sourceDirectory.rawValue == $1.sourceDirectory.rawValue {
                return $0.label < $1.label
            }
            return $0.sourceDirectory.rawValue < $1.sourceDirectory.rawValue
        }
        return ScannerOutput(items: sortedItems, warnings: warnings)
    }

    private static func defaultSources() -> [Source] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            Source(
                url: home.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
                category: .userLaunchAgents
            ),
            Source(
                url: URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
                category: .libraryLaunchAgents
            ),
            Source(
                url: URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true),
                category: .libraryLaunchDaemons
            ),
        ]
    }

    private func scanDirectory(
        _ source: Source,
        overrides: LaunchdDisabledOverrides
    ) throws -> DirectoryScan {
        let fm = FileManager.default
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: source.url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // A directory that doesn't exist is normal (not every Mac has all
            // three). A directory that exists but can't be enumerated is a real
            // failure worth surfacing. (C3)
            if fm.fileExists(atPath: source.url.path(percentEncoded: false)) {
                Self.logger.error("LaunchAgent directory unreadable \(source.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw ScannerError.permissionDenied(
                    reason: String(localized: "A LaunchAgents directory could not be read.")
                )
            }
            Self.logger.debug("LaunchAgent directory absent \(source.url.path, privacy: .public)")
            return .absent
        }

        var items: [LaunchAgentItem] = []
        var omittedFileNames: [String] = []
        for fileURL in contents where fileURL.pathExtension.lowercased() == "plist" {
            switch decodePlist(at: fileURL, category: source.category, overrides: overrides) {
            case .item(let item): items.append(item)
            case .inert: break
            case .omitted: omittedFileNames.append(fileURL.lastPathComponent)
            }
        }
        return .scanned(items: items, omittedFileNames: omittedFileNames)
    }

    private static func scannerSource(
        for category: LaunchAgentItem.SourceDirectory
    ) -> ScannerSource {
        switch category {
        case .userLaunchAgents: .userLaunchAgents
        case .libraryLaunchAgents: .libraryLaunchAgents
        case .libraryLaunchDaemons: .libraryLaunchDaemons
        }
    }

    private func decodePlist(
        at url: URL,
        category: LaunchAgentItem.SourceDirectory,
        overrides: LaunchdDisabledOverrides
    ) -> PlistDecodeResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if Self.isPermissionDenied(error) {
                Self.logger.debug("Plist not readable \(url.lastPathComponent, privacy: .public); listing without details")
                return .item(unreadableItem(at: url, category: category, overrides: overrides))
            }
            if Self.isDanglingSymlink(url) {
                Self.logger.debug("Skip dangling symlink \(url.lastPathComponent, privacy: .public)")
                return .inert
            }
            Self.logger.debug("Skip unreadable plist \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .omitted
        }

        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = plist as? [String: Any] else {
            return malformed(at: url, category: category, overrides: overrides)
        }
        // launchd refuses a job without a Label, so a well-formed label-less
        // dictionary (e.g. Google Keystone's empty leftovers) is not an agent.
        guard let rawLabel = dict["Label"] else {
            Self.logger.debug("Skip label-less plist \(url.lastPathComponent, privacy: .public)")
            return .inert
        }
        guard let label = rawLabel as? String else {
            return malformed(at: url, category: category, overrides: overrides)
        }
        let job = LaunchJobFields(dict)
        return .item(LaunchAgentItem(
            label: label,
            sourceDirectory: category,
            programPath: job.program,
            programArguments: job.programArguments,
            runAtLoad: job.runAtLoad,
            keepAlive: job.keepAlive,
            isDisabled: overrides.isDisabled(label: label, category: category, plistDisabled: job.disabled),
            fileName: url.lastPathComponent
        ))
    }

    /// Not a launchd job: unparseable, not a dictionary, or a non-string
    /// `Label`. A file caught mid-write by an installer looks the same, so it
    /// is listed as unreadable only once settled and omitted until then.
    private func malformed(
        at url: URL,
        category: LaunchAgentItem.SourceDirectory,
        overrides: LaunchdDisabledOverrides
    ) -> PlistDecodeResult {
        guard isSettled(url) else {
            Self.logger.debug("Skip malformed plist still settling \(url.lastPathComponent, privacy: .public)")
            return .omitted
        }
        Self.logger.debug("Plist malformed \(url.lastPathComponent, privacy: .public); listing without details")
        return .item(unreadableItem(at: url, category: category, overrides: overrides))
    }

    /// An unknown date cannot be waited out, and a date far in the future is
    /// a clock change rather than a write in progress; both count as settled.
    private func isSettled(_ url: URL) -> Bool {
        guard let modified = modificationDate(url) else { return true }
        return abs(now().timeIntervalSince(modified)) >= Self.settlingInterval
    }

    static func fileModificationDate(_ url: URL) -> Date? {
        let resolved = url.resolvingSymlinksInPath()
        return try? resolved.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func unreadableItem(
        at url: URL,
        category: LaunchAgentItem.SourceDirectory,
        overrides: LaunchdDisabledOverrides
    ) -> LaunchAgentItem {
        let label = url.deletingPathExtension().lastPathComponent
        return LaunchAgentItem(
            label: label,
            sourceDirectory: category,
            programPath: nil,
            programArguments: [],
            runAtLoad: false,
            keepAlive: false,
            isDisabled: overrides.isDisabled(label: label, category: category, plistDisabled: false),
            detailsReadable: false,
            fileName: url.lastPathComponent
        )
    }

    static func isPermissionDenied(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileReadNoPermission.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionDenied(underlying)
        }
        return false
    }

    private static func isDanglingSymlink(_ url: URL) -> Bool {
        let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        return isLink && !FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

private enum PlistDecodeResult {
    case item(LaunchAgentItem)
    case inert
    case omitted
}

private enum DirectoryScan {
    case absent
    case scanned(items: [LaunchAgentItem], omittedFileNames: [String])
}

/// Lenient read of the job keys we report. A key of the wrong type reads as
/// absent instead of discarding the whole job.
private struct LaunchJobFields {
    let program: String?
    let programArguments: [String]
    let runAtLoad: Bool
    let keepAlive: Bool
    let disabled: Bool

    init(_ dict: [String: Any]) {
        program = dict["Program"] as? String
        programArguments = (dict["ProgramArguments"] as? [Any])?.compactMap { $0 as? String } ?? []
        runAtLoad = dict["RunAtLoad"] as? Bool ?? false
        // KeepAlive is often a dictionary ({SuccessfulExit=false}, {Crashed=true}).
        // Treat any present non-bool form as an active keep-alive policy rather
        // than silently false. (D4)
        if let flag = dict["KeepAlive"] as? Bool {
            keepAlive = flag
        } else {
            keepAlive = dict["KeepAlive"] != nil
        }
        disabled = dict["Disabled"] as? Bool ?? false
    }
}
