import SwiftUI
import PermissionsCore
import PermissionsStore

// One row in a diff sub-section. The kind enum tells the row what to render
// (indicator color + description string); the actual layout is uniform.
struct ChangeRow: View {
    enum Kind: Identifiable {
        case granted(PermissionGrant)
        case revoked(PermissionGrant)
        case permissionChanged(DomainChange<PermissionGrant>)
        case btmAdded(BTMItem)
        case btmRemoved(BTMItem)
        case btmDispositionFlipped(DomainChange<BTMItem>)
        case launchAgentAdded(LaunchAgentItem)
        case launchAgentRemoved(LaunchAgentItem)
        case launchAgentFlipped(DomainChange<LaunchAgentItem>)

        var id: String { DiffEntryKey.key(for: self) }
    }

    let kind: Kind
    var onDismissForever: (() -> Void)? = nil
    var onSnooze: (() -> Void)? = nil

    private var hasMenuActions: Bool { onSnooze != nil || onDismissForever != nil }

    var body: some View {
        HStack(spacing: 10) {
            indicator
            Text(description)
                .ppFont(.body)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            if let onSnooze {
                Button(String(localized: "Snooze 7 days")) { onSnooze() }
            }
            if let onDismissForever {
                Button(String(localized: "Dismiss forever"), role: .destructive) { onDismissForever() }
            }
        }
        .help(hasMenuActions ? String(localized: "Right-click for dismiss options") : "")
        // VoiceOver can't discover a context menu on its own; mirror its actions.
        .accessibilityActions {
            if let onSnooze {
                Button(String(localized: "Snooze 7 days")) { onSnooze() }
            }
            if let onDismissForever {
                Button(String(localized: "Dismiss forever")) { onDismissForever() }
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch kind {
        case .granted, .btmAdded, .launchAgentAdded:
            Image(systemName: "plus.circle.fill")
                .ppFont(.body)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        case .revoked, .btmRemoved, .launchAgentRemoved:
            Image(systemName: "minus.circle.fill")
                .ppFont(.body)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        case .permissionChanged, .btmDispositionFlipped, .launchAgentFlipped:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .ppFont(.body)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
    }

    private var description: String {
        Self.summary(for: kind)
    }

    static func summary(for kind: Kind) -> String {
        switch kind {
        case .granted(let g):
            return String(localized: "Granted \(g.service.displayName) to \(g.app.displayName)")
        case .revoked(let g):
            return String(localized: "Revoked \(g.service.displayName) from \(g.app.displayName)")
        case .permissionChanged(let change):
            let from = authorizationLabel(change.before.authValue)
            let to = authorizationLabel(change.after.authValue)
            return String(localized: "Permission changed: \(change.after.service.displayName) for \(change.after.app.displayName) (\(from) → \(to))")
        case .btmAdded(let i):
            return String(localized: "New background item: \(i.name)")
        case .btmRemoved(let i):
            return String(localized: "Removed background item: \(i.name)")
        case .btmDispositionFlipped(let change):
            let from = dispositionLabel(change.before.disposition)
            let to = dispositionLabel(change.after.disposition)
            return String(localized: "Disposition changed: \(change.after.name) (\(from) → \(to))")
        case .launchAgentAdded(let i):
            return String(localized: "New launch agent: \(i.label)")
        case .launchAgentRemoved(let i):
            return String(localized: "Removed launch agent: \(i.label)")
        case .launchAgentFlipped(let change):
            return launchAgentFlipDescription(change)
        }
    }

    static func searchText(for kind: Kind) -> String {
        let details: [String]
        switch kind {
        case .granted(let grant), .revoked(let grant):
            details = permissionSearchFields(grant)
        case .permissionChanged(let change):
            details = permissionSearchFields(change.before) + permissionSearchFields(change.after)
        case .btmAdded(let item), .btmRemoved(let item):
            details = btmSearchFields(item)
        case .btmDispositionFlipped(let change):
            details = btmSearchFields(change.before) + btmSearchFields(change.after)
        case .launchAgentAdded(let item), .launchAgentRemoved(let item):
            details = launchAgentSearchFields(item)
        case .launchAgentFlipped(let change):
            details = launchAgentSearchFields(change.before) + launchAgentSearchFields(change.after)
        }
        return ([summary(for: kind)] + details).joined(separator: " ")
    }

    static func filtered(_ rows: [Kind], searchText queryText: String) -> [Kind] {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { searchText(for: $0).localizedCaseInsensitiveContains(query) }
    }

    private static func permissionSearchFields(_ grant: PermissionGrant) -> [String] {
        [
            grant.app.displayName,
            grant.app.bundleID,
            grant.app.bundlePath?.path(percentEncoded: false),
            grant.service.displayName,
            grant.service.rawValue,
            grant.automationTarget,
        ].compactMap { $0 }
    }

    private static func btmSearchFields(_ item: BTMItem) -> [String] {
        [
            item.name,
            item.developerName,
            item.identifier,
            item.bundleIdentifier,
            item.teamIdentifier,
            item.parentIdentifier,
        ].compactMap { $0 }
    }

    private static func launchAgentSearchFields(_ item: LaunchAgentItem) -> [String] {
        [
            item.label,
            item.sourceDirectory.rawValue,
            item.sourceDirectory.path,
            item.programPath,
        ].compactMap { $0 } + item.programArguments
    }

    private static func authorizationLabel(_ value: Int) -> String {
        switch value {
        case 2: String(localized: "Allowed")
        case 3: String(localized: "Limited")
        default: String(localized: "Value \(value)")
        }
    }

    private static func launchAgentFlipDescription(_ change: DomainChange<LaunchAgentItem>) -> String {
        if change.before.runAtLoad != change.after.runAtLoad {
            let from = change.before.runAtLoad ? String(localized: "on") : String(localized: "off")
            let to = change.after.runAtLoad ? String(localized: "on") : String(localized: "off")
            return String(localized: "runAtLoad flipped: \(change.after.label) (\(from) → \(to))")
        }
        if change.before.keepAlive != change.after.keepAlive {
            let from = change.before.keepAlive ? String(localized: "on") : String(localized: "off")
            let to = change.after.keepAlive ? String(localized: "on") : String(localized: "off")
            return String(localized: "keepAlive flipped: \(change.after.label) (\(from) → \(to))")
        }
        return String(localized: "Modified: \(change.after.label)")
    }

    private static func dispositionLabel(_ d: BTMItem.Disposition) -> String {
        switch d {
        case .enabled:  return String(localized: "enabled")
        case .disabled: return String(localized: "disabled")
        case .unknown:  return String(localized: "unknown")
        }
    }
}
