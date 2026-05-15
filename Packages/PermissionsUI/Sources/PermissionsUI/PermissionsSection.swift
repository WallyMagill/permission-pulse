import SwiftUI
import PermissionsCore

public struct PermissionsSection: View {
    private let grants: [PermissionGrant]
    private let dataSource: AppViewModel.DataSource
    private let error: ScannerError?

    @State private var selectedGrant: PermissionGrant?

    public init(
        grants: [PermissionGrant],
        dataSource: AppViewModel.DataSource,
        error: ScannerError? = nil
    ) {
        self.grants = grants
        self.dataSource = dataSource
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(localized: "Permissions"),
                showsBadge: error == nil,
                dataSource: dataSource
            )

            if grants.isEmpty {
                PermissionsEmptyStateView(error: error, domain: .tcc)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(grants.enumerated()), id: \.element) { index, grant in
                        TappableRow(action: { selectedGrant = grant }) {
                            GrantRow(grant: grant)
                        }
                        if index < grants.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(item: $selectedGrant) { grant in
            PermissionDetailSheet(grant: grant)
        }
    }
}

private struct GrantRow: View {
    let grant: PermissionGrant

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(grant.app.displayName)
            Text("\(grant.service.displayName) · \(grant.app.bundleID)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if grant.service == .automation, let target = grant.automationTarget {
                Text("Controls → \(target)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
