import Foundation
import PermissionsCore

/// What the user has selected in a section list. Drives the trailing
/// inspector. Identifier-based so selection survives data refreshes.
public enum InspectorSelection: Hashable, Sendable {
    case app(appKey: String)            // PermissionGrant.appKey (grouped per app)
    case launchAgent(id: String)        // LaunchAgentItem.id
    case backgroundItem(id: String)     // BTMItem.id
}

/// Resolved inspector content — the data the panel renders.
public enum InspectorContent: Equatable, Sendable {
    case app(AppIdentity, grants: [PermissionGrant])
    case launchAgent(LaunchAgentItem)
    case backgroundItem(BTMItem)
}

/// Pure resolution from a selection to current scan data. Returns nil when
/// the selected item no longer exists (e.g. a change row for a removed app);
/// the panel shows a "no longer present" state for that.
public enum InspectorContentResolver {
    public static func resolve(
        _ selection: InspectorSelection?,
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem]
    ) -> InspectorContent? {
        guard let selection else { return nil }
        switch selection {
        case .app(let appKey):
            let matching = grants.filter { $0.appKey == appKey }
            // Representative identity comes from the most recently modified
            // grant — if sources ever disagree on display name, newest wins.
            // `grants` in the result is never empty by this guard.
            guard let freshest = matching.max(by: { $0.lastModified < $1.lastModified }) else { return nil }
            return .app(freshest.app, grants: matching)
        case .launchAgent(let id):
            guard let item = launchAgents.first(where: { $0.id == id }) else { return nil }
            return .launchAgent(item)
        case .backgroundItem(let id):
            guard let item = btmItems.first(where: { $0.id == id }) else { return nil }
            return .backgroundItem(item)
        }
    }
}
