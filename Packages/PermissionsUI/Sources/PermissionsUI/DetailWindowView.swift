import SwiftUI
import PermissionsCore

public struct DetailWindowView: View {
    @Environment(AppViewModel.self) private var viewModel

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    if viewModel.grants.isEmpty {
                        Text("No permissions yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.grants, id: \.self) { grant in
                            GrantRow(grant: grant)
                        }
                    }
                } header: {
                    HStack {
                        Text("Permissions")
                        Spacer()
                        switch viewModel.tccDataSource {
                        case .mock: MockBadge()
                        case .live: LiveBadge()
                        }
                    }
                }

                LaunchAgentsSection(
                    items: viewModel.launchAgents,
                    dataSource: viewModel.launchAgentsDataSource
                )
            }
            .navigationTitle("Permission Pulse")
        }
        .frame(minWidth: 520, minHeight: 360)
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
