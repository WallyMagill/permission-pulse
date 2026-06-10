import SwiftUI
import PermissionsCore
import PermissionsStore

// One row in a diff sub-section. The kind enum tells the row what to render
// (indicator color + description string); the actual layout is uniform.
struct ChangeRow: View {
    enum Kind {
        case granted(PermissionGrant)
        case revoked(PermissionGrant)
        case btmAdded(BTMItem)
        case btmRemoved(BTMItem)
        case btmDispositionFlipped(DomainChange<BTMItem>)
        case launchAgentAdded(LaunchAgentItem)
        case launchAgentRemoved(LaunchAgentItem)
        case launchAgentFlipped(DomainChange<LaunchAgentItem>)
    }

    let kind: Kind
    var onDismissForever: (() -> Void)? = nil
    var onSnooze: (() -> Void)? = nil

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
        .help(String(localized: "Right-click for dismiss options"))
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
        case .btmDispositionFlipped, .launchAgentFlipped:
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
