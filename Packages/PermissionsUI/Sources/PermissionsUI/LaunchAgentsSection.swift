import SwiftUI
import PermissionsCore

public struct LaunchAgentsSection: View {
    private let items: [LaunchAgentItem]
    private let dataSource: AppViewModel.DataSource

    @State private var selectedItem: LaunchAgentItem?

    public init(items: [LaunchAgentItem], dataSource: AppViewModel.DataSource) {
        self.items = items
        self.dataSource = dataSource
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(localized: "Launch Agents"),
                showsBadge: true,
                dataSource: dataSource
            )

            if items.isEmpty {
                Text(String(localized: "No launch agents"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        TappableRow(action: { selectedItem = item }) {
                            LaunchAgentRow(item: item)
                        }
                        if index < items.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(item: $selectedItem) { item in
            LaunchAgentDetailSheet(item: item)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Empty — Live") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            LaunchAgentsSection(items: [], dataSource: .live)
        }
        .padding(16)
    }
    .frame(width: 480, height: 240)
}

#Preview("Populated — Live") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            LaunchAgentsSection(
                items: [
                    LaunchAgentItem(
                        label: "com.example.helper",
                        sourceDirectory: .userLaunchAgents,
                        programPath: "/usr/local/bin/helper",
                        programArguments: [],
                        runAtLoad: true,
                        keepAlive: false
                    ),
                    LaunchAgentItem(
                        label: "com.example.daemon",
                        sourceDirectory: .libraryLaunchDaemons,
                        programPath: "/usr/local/sbin/daemon",
                        programArguments: ["--background"],
                        runAtLoad: true,
                        keepAlive: true
                    ),
                ],
                dataSource: .live
            )
        }
        .padding(16)
    }
    .frame(width: 480, height: 240)
}

#Preview("Populated — Mock") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            LaunchAgentsSection(
                items: [
                    LaunchAgentItem(
                        label: "com.example.mock",
                        sourceDirectory: .userLaunchAgents,
                        programPath: "/tmp/mock",
                        programArguments: [],
                        runAtLoad: false,
                        keepAlive: false
                    ),
                ],
                dataSource: .mock
            )
        }
        .padding(16)
    }
    .frame(width: 480, height: 240)
}
