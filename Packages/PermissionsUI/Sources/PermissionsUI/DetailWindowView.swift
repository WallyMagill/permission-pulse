import SwiftUI
import PermissionsCore

public struct DetailWindowView: View {
    @Environment(AppViewModel.self) private var viewModel
    private let onRefresh: (() async -> Void)?

    public init(onRefresh: (() async -> Void)? = nil) {
        self.onRefresh = onRefresh
    }

    public var body: some View {
        NavigationStack {
            List {
                if shouldShowSchemaBanner, let error = viewModel.tccScanError {
                    Section {
                        SchemaMismatchBanner(error: error)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    if viewModel.grants.isEmpty {
                        PermissionsEmptyStateView(error: viewModel.tccScanError)
                    } else {
                        ForEach(viewModel.grants, id: \.self) { grant in
                            GrantRow(grant: grant)
                        }
                    }
                } header: {
                    HStack {
                        Text(String(localized: "Permissions"))
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
            .navigationTitle(String(localized: "Permission Pulse"))
            .toolbar {
                if let onRefresh {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await onRefresh() }
                        } label: {
                            Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private var shouldShowSchemaBanner: Bool {
        switch viewModel.tccScanError {
        case .schemaMismatch, .unsupportedOnThisOS: true
        default: false
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
