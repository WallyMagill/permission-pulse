import Foundation

/// Sidebar destinations in the detail window, in display order.
public enum SidebarItem: Hashable, Sendable, CaseIterable {
    case overview
    case permissions
    case launchAgents
    case backgroundItems
    case recentChanges
    case staleApps
}

/// A deep-link destination. Glance surfaces (the dropdown) emit routes; the
/// detail window consumes them: select the sidebar section and, when a route
/// carries an item identifier, pre-select that item so the inspector opens.
/// A Permissions route can also pre-fill the page's search field.
public enum AppRoute: Hashable, Sendable {
    case overview
    case permissions(selectAppKey: String?, searchText: String? = nil)
    case launchAgents(selectID: String?)
    case backgroundItems(selectID: String?)
    /// Recent Changes on its since-last-review window.
    case recentChanges
    /// Recent Changes on its last-7-days window (the weekly digest's view).
    case recentChangesLastSevenDays
    case staleApps

    public var sidebarItem: SidebarItem {
        switch self {
        case .overview: .overview
        case .permissions: .permissions
        case .launchAgents: .launchAgents
        case .backgroundItems: .backgroundItems
        case .recentChanges, .recentChangesLastSevenDays: .recentChanges
        case .staleApps: .staleApps
        }
    }

    /// The Recent Changes window this route selects, if it goes there.
    public var recentChangesWindow: RecentChangesWindow? {
        switch self {
        case .recentChanges: .sinceLastReview
        case .recentChangesLastSevenDays: .lastSevenDays
        default: nil
        }
    }

    /// The pre-selection carried by this route, if any.
    public var inspectorSelection: InspectorSelection? {
        switch self {
        case .permissions(let key?, _): .app(appKey: key)
        case .launchAgents(let id?): .launchAgent(id: id)
        case .backgroundItems(let id?): .backgroundItem(id: id)
        default: nil
        }
    }

    /// Text to put in the destination page's search field, if any.
    public var searchText: String? {
        if case .permissions(_, let text) = self { return text }
        return nil
    }
}
