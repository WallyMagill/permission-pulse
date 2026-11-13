import SwiftUI
import PermissionsCore

struct StaleAppsDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    let searchText: String

    var body: some View {
        VStack(spacing: 0) {
            ScanAvailabilityBanner(
                availability: viewModel.tccAvailability,
                domainName: String(localized: "Permissions"),
                unavailableSources: viewModel.tccUnavailableSources
            )
            .padding([.horizontal, .top], PPSpacing.lg)
            .padding(.bottom, PPSpacing.sm)
            if filteredApps.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                StaleAppsTabView(
                    staleApps: filteredApps,
                    staleThresholdDays: viewModel.staleThresholdDays,
                    emptyState: emptyState
                )
            }
        }
        .navigationTitle(String(localized: "Stale Apps"))
        .navigationSubtitle(subtitle)
    }

    private var emptyState: StaleAppsEmptyState {
        StaleAppsEmptyState.resolve(
            hasPermissionData: viewModel.hasPermissionData,
            historyAvailable: !viewModel.snapshotStoreUnavailable && viewModel.latestSnapshotID != nil,
            systemLevelOnly: viewModel.permissionScope.isReduced
        )
    }

    private var filteredApps: [StaleApp] {
        if searchText.isEmpty { return viewModel.staleApps }
        let q = searchText.lowercased()
        return viewModel.staleApps.filter { app in
            app.app.displayName.lowercased().contains(q)
                || app.app.bundleID.lowercased().contains(q)
        }
    }

    private var subtitle: String {
        if viewModel.permissionScope.isReduced {
            return String(localized: "Checks apps with system-level permissions only.")
        }
        if viewModel.staleApps.isEmpty { return "" }
        return String(localized: "Apps with active grants you haven't used in \(viewModel.staleThresholdDays)+ days")
    }
}

/// Why Stale Apps has nothing to list. "Every app has been used recently"
/// is true only when there were permissions to check and history to check
/// them with.
enum StaleAppsEmptyState: Equatable {
    case noPermissionData
    case historyUnavailable
    case noneStale(systemLevelOnly: Bool)

    /// Stale apps are computed after a snapshot is stored, so without one
    /// (or without an open history database) nothing was checked.
    static func resolve(hasPermissionData: Bool, historyAvailable: Bool, systemLevelOnly: Bool) -> Self {
        if !hasPermissionData { return .noPermissionData }
        if !historyAvailable { return .historyUnavailable }
        return .noneStale(systemLevelOnly: systemLevelOnly)
    }

    var title: String {
        switch self {
        case .noPermissionData: String(localized: "No Permission Data")
        case .historyUnavailable: String(localized: "History Unavailable")
        case .noneStale: String(localized: "No Stale Apps")
        }
    }

    var description: String {
        switch self {
        case .noPermissionData:
            String(localized: "Stale Apps checks the apps that hold permissions. No permissions scan has succeeded, so there is nothing to check yet.")
        case .historyUnavailable:
            String(localized: "Stale Apps needs Permission Pulse's local history, which isn't available. Recent Changes says why.")
        case .noneStale(systemLevelOnly: false):
            String(localized: "Every app with an active grant has been used recently.")
        case .noneStale(systemLevelOnly: true):
            String(localized: "Every app with a system-level permission has been used recently.")
        }
    }

    var systemImage: String {
        switch self {
        case .noPermissionData: "lock.shield"
        case .historyUnavailable: "externaldrive.badge.exclamationmark"
        case .noneStale: "checkmark.circle"
        }
    }
}
