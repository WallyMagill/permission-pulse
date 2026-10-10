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

    private let sources: [Source]

    public init() {
        self.sources = Self.defaultSources()
    }

    init(sources: [Source]) {
        self.sources = sources
    }

    public func scan() async throws -> ScannerOutput<LaunchAgentItem> {
        var items: [LaunchAgentItem] = []
        var firstFailure: (any Error)?
        var warnings: [ScannerWarning] = []
        var omittedEntryCount = 0
        var anyExistingSourceSucceeded = false
        for source in sources {
            do {
                switch try scanDirectory(source) {
                case .absent:
                    break
                case .scanned(let sourceItems, let sourceOmittedEntryCount):
                    items.append(contentsOf: sourceItems)
                    omittedEntryCount += sourceOmittedEntryCount
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
        if omittedEntryCount > 0 {
            warnings.append(ScannerWarning(source: .entries, omittedCount: omittedEntryCount))
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

    private func scanDirectory(_ source: Source) throws -> DirectoryScan {
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
        var omittedEntryCount = 0
        for fileURL in contents where fileURL.pathExtension.lowercased() == "plist" {
            switch decodePlist(at: fileURL, category: source.category) {
            case .item(let item): items.append(item)
            case .inert: break
            case .omitted: omittedEntryCount += 1
            }
        }
        return .scanned(items: items, omittedEntryCount: omittedEntryCount)
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
        category: LaunchAgentItem.SourceDirectory
    ) -> PlistDecodeResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Self.logger.debug("Skip unreadable plist \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .omitted
        }

        // launchd refuses a job without a Label, so a well-formed label-less
        // dictionary (e.g. Google Keystone's empty leftovers) is not an agent.
        if let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           dict["Label"] == nil {
            Self.logger.debug("Skip label-less plist \(url.lastPathComponent, privacy: .public)")
            return .inert
        }

        do {
            let decoded = try PropertyListDecoder().decode(DecodedPlist.self, from: data)
            return .item(LaunchAgentItem(
                label: decoded.label,
                sourceDirectory: category,
                programPath: decoded.program,
                programArguments: decoded.programArguments,
                runAtLoad: decoded.runAtLoad,
                keepAlive: decoded.keepAlive,
                isDisabled: decoded.isDisabled
            ))
        } catch {
            Self.logger.debug("Skip malformed plist \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .omitted
        }
    }
}

private enum PlistDecodeResult {
    case item(LaunchAgentItem)
    case inert
    case omitted
}

private enum DirectoryScan {
    case absent
    case scanned(items: [LaunchAgentItem], omittedEntryCount: Int)
}

private struct DecodedPlist: Decodable {
    let label: String
    let program: String?
    let programArguments: [String]
    let runAtLoad: Bool
    let keepAlive: Bool
    let isDisabled: Bool

    enum CodingKeys: String, CodingKey {
        case label = "Label"
        case program = "Program"
        case programArguments = "ProgramArguments"
        case runAtLoad = "RunAtLoad"
        case keepAlive = "KeepAlive"
        case disabled = "Disabled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decode(String.self, forKey: .label)
        self.program = try container.decodeIfPresent(String.self, forKey: .program)
        self.programArguments = (try? container.decode([String].self, forKey: .programArguments)) ?? []
        self.runAtLoad = (try? container.decode(Bool.self, forKey: .runAtLoad)) ?? false
        // KeepAlive is often a dictionary ({SuccessfulExit=false}, {Crashed=true}).
        // A Bool decode fails on a dict; treat any present non-bool form as an
        // active keep-alive policy rather than silently false. (D4)
        if let b = try? container.decode(Bool.self, forKey: .keepAlive) {
            self.keepAlive = b
        } else {
            self.keepAlive = container.contains(.keepAlive)
        }
        self.isDisabled = (try? container.decode(Bool.self, forKey: .disabled)) ?? false
    }
}
