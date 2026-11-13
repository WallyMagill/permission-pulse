import Foundation

/// One glanceable dropdown row: a semantic kind (the view maps it to copy
/// and an SF Symbol) plus the deep-link route a click follows.
public struct DropdownStatusRow: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// One row per domain the attention state names.
        case attention(AttentionState, AttentionDomain)
        /// Running from a temporary App Translocation copy.
        case moveToApplications
        case media(mic: Bool, camera: Bool)
        case changes(count: Int)
        case stale(count: Int)
        /// How many apps hold a permission the scan can see. `allClear` is
        /// true only when it is the sole row: nothing else needs attention.
        case summary(appCount: Int, systemLevelOnly: Bool, allClear: Bool)
    }

    public let kind: Kind
    public let route: AppRoute

    public var id: String {
        switch kind {
        case .attention(_, let domain): "attention-\(domain)"
        case .moveToApplications: "moveToApplications"
        case .media: "media"
        case .changes: "changes"
        case .stale: "stale"
        case .summary: "summary"
        }
    }

    var title: String {
        switch kind {
        case .attention(let state, let domain):
            Self.attentionTitle(state, domain: domain)
        case .moveToApplications:
            String(localized: "Move Permission Pulse to your Applications folder, then open it from there.")
        case .media(true, true):
            String(localized: "Microphone and camera are in use")
        case .media(true, false):
            String(localized: "Microphone is in use")
        case .media(_, _):
            String(localized: "Camera is in use")
        case .changes(let n):
            n == 1
                ? String(localized: "1 change since your last review")
                : String(localized: "\(n) changes since your last review")
        case .stale(let n):
            n == 1
                ? String(localized: "1 stale app with old permissions")
                : String(localized: "\(n) stale apps with old permissions")
        case .summary(let n, false, _):
            n == 1
                ? String(localized: "1 app with permissions")
                : String(localized: "\(n) apps with permissions")
        case .summary(let n, true, _):
            n == 1
                ? String(localized: "1 app with system-level permissions")
                : String(localized: "\(n) apps with system-level permissions")
        }
    }

    private static func attentionTitle(_ state: AttentionState, domain: AttentionDomain) -> String {
        let name = domain.displayName
        return switch state {
        case .fdaDenied: String(localized: "Full Disk Access is off")
        case .btmOnlyFDADenied: String(localized: "FDA needed for background items")
        case .launchAgentError: String(localized: "Launch Agents couldn't be read")
        case .schemaMismatch: String(localized: "\(name): data format changed")
        case .scanFailed: String(localized: "\(name): scan failed — no results")
        case .degradedData: String(localized: "\(name): some sources couldn't be read")
        case .staleData: String(localized: "\(name): showing last-known data")
        case .clean: "" // builder never emits this
        }
    }
}

/// Pure derivation of the dropdown's status rows. Order: attention first,
/// then the move-to-Applications instruction, live media, unreviewed
/// changes, stale apps, then the summary row. The summary is left out while
/// the permissions scan has no data (`appCount == nil`), so a failed scan
/// never reads as "0 apps with permissions".
public enum DropdownStatusBuilder {
    public static func rows(
        attention: AttentionState,
        micInUse: Bool,
        cameraInUse: Bool,
        changeCount: Int,
        hasUnreviewedChanges: Bool,
        staleCount: Int,
        appCount: Int?,
        systemLevelOnly: Bool = false,
        isTranslocated: Bool = false
    ) -> [DropdownStatusRow] {
        var result = attention.domains.map { domain in
            DropdownStatusRow(kind: .attention(attention, domain), route: domain.route)
        }
        if isTranslocated {
            result.append(.init(kind: .moveToApplications, route: .overview))
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
        if let appCount {
            let summary = DropdownStatusRow.Kind.summary(
                appCount: appCount,
                systemLevelOnly: systemLevelOnly,
                allClear: result.isEmpty
            )
            result.append(.init(kind: summary, route: .overview))
        }
        return result
    }
}

/// The dropdown header's "Updated …" line.
public enum ScanTimestamp {
    /// Time of day for a scan today, date and time otherwise; nil before
    /// the first scan.
    public static func updatedText(
        lastScan: Date?,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard let lastScan else { return nil }
        let formatted = calendar.isDate(lastScan, inSameDayAs: now)
            ? lastScan.formatted(date: .omitted, time: .shortened)
            : lastScan.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Updated \(formatted)")
    }
}
