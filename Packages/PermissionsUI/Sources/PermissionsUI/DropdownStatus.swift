import Foundation

/// One glanceable dropdown row: a semantic kind (the view maps it to copy
/// and an SF Symbol) plus the deep-link route a click follows.
public struct DropdownStatusRow: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case attention(AttentionState)
        case media(mic: Bool, camera: Bool)
        case changes(count: Int)
        case stale(count: Int)
        case allClear(appCount: Int)
    }

    public let kind: Kind
    public let route: AppRoute

    public var id: String {
        switch kind {
        case .attention: "attention"
        case .media: "media"
        case .changes: "changes"
        case .stale: "stale"
        case .allClear: "allClear"
        }
    }

    var title: String {
        switch kind {
        case .attention(.fdaDenied):
            String(localized: "Full Disk Access needed")
        case .attention(.btmOnlyFDADenied):
            String(localized: "FDA needed for background items")
        case .attention(.schemaMismatch):
            String(localized: "A data source changed format")
        case .attention(.launchAgentError):
            String(localized: "Launch Agents couldn't be read")
        case .attention(.scanFailed):
            String(localized: "Scan failed — no results available")
        case .attention(.degradedData):
            String(localized: "Scan data is degraded")
        case .attention(.staleData):
            String(localized: "Scan data is stale")
        case .attention(.clean):
            "" // builder never emits this
        case .media(true, true):
            String(localized: "Microphone and camera are in use")
        case .media(true, false):
            String(localized: "Microphone is in use")
        case .media(_, _):
            String(localized: "Camera is in use")
        case .changes(let n):
            String(localized: "\(n) changes since your last review")
        case .stale(let n):
            String(localized: "\(n) stale apps with old permissions")
        case .allClear(let n):
            String(localized: "\(n) apps with permissions")
        }
    }
}

/// Pure derivation of the dropdown's status rows. Order: attention first,
/// live media, unreviewed changes, stale apps, then the always-present
/// summary row (which doubles as the "all clear" line).
public enum DropdownStatusBuilder {
    public static func rows(
        attention: AttentionState,
        micInUse: Bool,
        cameraInUse: Bool,
        changeCount: Int,
        hasUnreviewedChanges: Bool,
        staleCount: Int,
        appCount: Int
    ) -> [DropdownStatusRow] {
        var result: [DropdownStatusRow] = []
        switch attention {
        case .clean:
            break
        case .fdaDenied, .schemaMismatch:
            result.append(.init(kind: .attention(attention), route: .permissions(selectAppKey: nil)))
        case .btmOnlyFDADenied:
            result.append(.init(kind: .attention(attention), route: .backgroundItems(selectID: nil)))
        case .launchAgentError:
            result.append(.init(kind: .attention(attention), route: .launchAgents(selectID: nil)))
        case .scanFailed, .degradedData, .staleData:
            result.append(.init(kind: .attention(attention), route: .overview))
        }
        if micInUse || cameraInUse {
            result.append(.init(
                kind: .media(mic: micInUse, camera: cameraInUse),
                route: .permissions(selectAppKey: nil)
            ))
        }
        if hasUnreviewedChanges && changeCount > 0 {
            result.append(.init(kind: .changes(count: changeCount), route: .recentChanges))
        }
        if staleCount > 0 {
            result.append(.init(kind: .stale(count: staleCount), route: .staleApps))
        }
        result.append(.init(kind: .allClear(appCount: appCount), route: .overview))
        return result
    }
}
