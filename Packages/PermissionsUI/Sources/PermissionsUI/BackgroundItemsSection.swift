import SwiftUI
import PermissionsCore

public struct BackgroundItemsSection: View {
    private let items: [BTMItem]
    private let dataSource: AppViewModel.DataSource
    private let error: ScannerError?

    public init(
        items: [BTMItem],
        dataSource: AppViewModel.DataSource,
        error: ScannerError? = nil
    ) {
        self.items = items
        self.dataSource = dataSource
        self.error = error
    }

    public var body: some View {
        Section {
            if items.isEmpty {
                PermissionsEmptyStateView(error: error, domain: .btm)
            } else {
                ForEach(items, id: \.self) { item in
                    BTMItemRow(item: item)
                }
            }
        } header: {
            HStack {
                Text(String(localized: "Background Items"))
                Spacer()
                switch dataSource {
                case .mock: MockBadge()
                case .live: LiveBadge()
                }
            }
        }
    }
}

private struct BTMItemRow: View {
    let item: BTMItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let parent = item.parentIdentifier, !parent.isEmpty {
                    Text(String(localized: "under \(parent)"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            DispositionBadge(disposition: item.disposition)
        }
    }

    private var secondaryLine: String {
        let parts: [String] = [
            item.developerName ?? item.bundleIdentifier ?? item.identifier,
            scopeLabel,
            typeLabel,
        ]
        return parts.joined(separator: " · ")
    }

    private var scopeLabel: String {
        switch item.scope {
        case .system: String(localized: "system")
        case .user: String(localized: "user")
        case .perUser: String(localized: "current user")
        }
    }

    private var typeLabel: String {
        switch item.type {
        case .app: String(localized: "App")
        case .legacyDaemon: String(localized: "Daemon")
        case .developerGroup: String(localized: "Group")
        case .unknown(let rawValue): String(localized: "Unknown item type · 0x\(String(rawValue, radix: 16))")
        }
    }
}

private struct DispositionBadge: View {
    let disposition: BTMItem.Disposition

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: .capsule)
    }

    private var label: String {
        switch disposition {
        case .enabled: String(localized: "Enabled")
        case .disabled: String(localized: "Disabled")
        case .unknown: String(localized: "Unknown")
        }
    }

    private var color: Color {
        switch disposition {
        case .enabled: .green
        case .disabled: .gray
        case .unknown: .orange
        }
    }
}

#Preview("Empty — Live") {
    List {
        BackgroundItemsSection(items: [], dataSource: .live)
    }
    .frame(width: 520, height: 240)
}

#Preview("Empty — FDA denied") {
    List {
        BackgroundItemsSection(
            items: [],
            dataSource: .live,
            error: .permissionDenied(reason: "FDA needed")
        )
    }
    .frame(width: 520, height: 420)
}

#Preview("Populated — Mock") {
    List {
        BackgroundItemsSection(
            items: [
                BTMItem(
                    identifier: "2.us.zoom.xos",
                    name: "zoom.us",
                    bundleIdentifier: "us.zoom.xos",
                    teamIdentifier: "BJ4HAAB9B3",
                    type: .app,
                    disposition: .enabled,
                    scope: .user,
                    modificationDate: Date()
                ),
                BTMItem(
                    identifier: "16.com.docker.vmnetd",
                    name: "com.docker.vmnetd",
                    developerName: "Docker",
                    teamIdentifier: "9BNSXJN65R",
                    type: .legacyDaemon,
                    disposition: .enabled,
                    scope: .system,
                    modificationDate: Date(),
                    parentIdentifier: "Docker"
                ),
            ],
            dataSource: .mock
        )
    }
    .frame(width: 520, height: 240)
}
