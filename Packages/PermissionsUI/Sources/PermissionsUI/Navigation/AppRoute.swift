import Foundation

// TODO(Thread C T3): collapse DetailSidebarSelection into SidebarItem
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
public enum AppRoute: Hashable, Sendable {
    case overview
    case permissions(selectAppKey: String?)
    case launchAgents(selectID: String?)
    case backgroundItems(selectID: String?)
    case recentChanges
    case staleApps

    public var sidebarItem: SidebarItem {
        switch self {
        case .overview: .overview
        case .permissions: .permissions
        case .launchAgents: .launchAgents
        case .backgroundItems: .backgroundItems
        case .recentChanges: .recentChanges
        case .staleApps: .staleApps
        }
    }
}
