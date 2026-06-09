import SwiftUI
import PermissionsCore

public struct PermissionsSection: View {
    private let grants: [PermissionGrant]
    private let dataSource: AppViewModel.DataSource
    private let error: ScannerError?
    private let showsHeader: Bool

    @State private var selectedAppGroup: SelectedAppGroup?

    public init(
        grants: [PermissionGrant],
        dataSource: AppViewModel.DataSource,
        error: ScannerError? = nil,
        showsHeader: Bool = true
    ) {
        self.grants = grants
        self.dataSource = dataSource
        self.error = error
        self.showsHeader = showsHeader
    }

    public var body: some View {
        let displayItems = PermissionsDisplayItem.make(from: grants)

        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            if showsHeader {
                SectionHeader(
                    title: String(localized: "Permissions"),
                    showsBadge: error == nil,
                    dataSource: dataSource
                )
            }

            if grants.isEmpty {
                PermissionsEmptyStateView(error: error, domain: .tcc)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        rowView(for: item)
                        if index < displayItems.count - 1 {
                            Divider().padding(.leading, PPSpacing.md)
                        }
                    }
                }
                .vibrancyCard()
            }
        }
        .sheet(item: $selectedAppGroup) { selection in
            AppPermissionsDetailSheet(app: selection.app, grants: selection.grants)
        }
    }

    @ViewBuilder
    private func rowView(for item: PermissionsDisplayItem) -> some View {
        switch item {
        case .appGroup(let app, let grants):
            TappableRow(
                action: { selectedAppGroup = SelectedAppGroup(app: app, grants: grants) }
            ) {
                AppGroupRow(app: app, grants: grants)
            }
        }
    }
}

// Wrapper conforming to Identifiable so `sheet(item:)` can bind to it. The id
// is stable across data refreshes that preserve the app so an open sheet
// doesn't close on rescans.
private struct SelectedAppGroup: Identifiable {
    let app: AppIdentity
    let grants: [PermissionGrant]

    var id: String {
        if app.bundleID.isEmpty, let first = grants.first {
            return "grant|\(first.id)"
        }
        return "app|\(app.bundleID)"
    }
}

private struct AppGroupRow: View {
    let app: AppIdentity
    let grants: [PermissionGrant]

    var body: some View {
        HStack(spacing: PPSpacing.md) {
            AppIconResolver.iconView(for: app, size: 28)
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(app.displayName)
                    .ppFont(.body)
                    .fontWeight(.medium)
                Text(serviceLine)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: PPSpacing.sm)
            Text(serviceCountLabel)
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
                .padding(.horizontal, PPSpacing.sm)
                .padding(.vertical, PPSpacing.xxs)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private var distinctServices: [PermissionService] {
        var seen = Set<PermissionService>()
        var ordered: [PermissionService] = []
        for grant in grants where seen.insert(grant.service).inserted {
            ordered.append(grant.service)
        }
        return ordered.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var serviceLine: String {
        distinctServices.map(\.displayName).joined(separator: " · ")
    }

    private var serviceCountLabel: String {
        let n = distinctServices.count
        if n == 1 {
            return String(localized: "1 service")
        }
        return String(localized: "\(n) services")
    }
}
