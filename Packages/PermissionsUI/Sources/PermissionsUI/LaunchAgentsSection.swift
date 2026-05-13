import SwiftUI
import PermissionsCore

public struct LaunchAgentsSection: View {
    private let items: [LaunchAgentItem]
    private let dataSource: AppViewModel.DataSource

    public init(items: [LaunchAgentItem], dataSource: AppViewModel.DataSource) {
        self.items = items
        self.dataSource = dataSource
    }

    public var body: some View {
        Section {
            if items.isEmpty {
                Text("No launch agents")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    LaunchAgentRow(item: item)
                }
            }
        } header: {
            HStack {
                Text("Launch Agents")
                Spacer()
                switch dataSource {
                case .mock: MockBadge()
                case .live: LiveBadge()
                }
            }
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

#Preview("Empty — Live") {
    List {
        LaunchAgentsSection(items: [], dataSource: .live)
    }
    .frame(width: 480, height: 240)
}

#Preview("Populated — Live") {
    List {
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
    .frame(width: 480, height: 240)
}

#Preview("Populated — Mock") {
    List {
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
    .frame(width: 480, height: 240)
}
