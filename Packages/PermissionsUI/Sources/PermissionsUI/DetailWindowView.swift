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
                        if viewModel.dataSource == .mock { MockBadge() }
                    }
                }

                Section {
                    if viewModel.launchAgents.isEmpty {
                        Text("No launch agents")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.launchAgents, id: \.self) { item in
                            LaunchAgentRow(item: item)
                        }
                    }
                } header: {
                    HStack {
                        Text("Launch Agents")
                        Spacer()
                        if viewModel.dataSource == .mock { MockBadge() }
                    }
                }
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
        }
    }
}

private struct LaunchAgentRow: View {
    let item: LaunchAgentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.label)
            Text(item.sourceDirectory.path)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
