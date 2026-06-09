import SwiftUI
import PermissionsCore

public struct BackgroundItemsSection: View {
    private let items: [BTMItem]
    private let dataSource: AppViewModel.DataSource
    private let error: ScannerError?
    private let showsHeader: Bool

    @State private var selectedItem: BTMItem?

    public init(
        items: [BTMItem],
        dataSource: AppViewModel.DataSource,
        error: ScannerError? = nil,
        showsHeader: Bool = true
    ) {
        self.items = items
        self.dataSource = dataSource
        self.error = error
        self.showsHeader = showsHeader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            if showsHeader {
                SectionHeader(
                    title: String(localized: "Background Items"),
                    showsBadge: error == nil,
                    dataSource: dataSource
                )
            }

            if items.isEmpty {
                PermissionsEmptyStateView(error: error, domain: .btm)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        TappableRow(action: { selectedItem = item }) {
                            BTMItemRow(item: item)
                        } trailing: {
                            DispositionBadge(disposition: item.disposition)
                        }
                        if index < items.count - 1 {
                            Divider().padding(.leading, PPSpacing.md)
                        }
                    }
                }
                .vibrancyCard()
            }
        }
        .sheet(item: $selectedItem) { item in
            BackgroundItemDetailSheet(item: item)
        }
    }
}

private struct BTMItemRow: View {
    let item: BTMItem

    var body: some View {
        HStack(spacing: PPSpacing.md) {
            iconView
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(item.name)
                Text(secondaryLine)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                if let parent = item.parentIdentifier, !parent.isEmpty {
                    Text(String(localized: "under \(parent)"))
                        .ppFont(.tertiary)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let bid = item.bundleIdentifier, !bid.isEmpty {
            // Synthesize an AppIdentity from the BTM bundleID so the shared
            // resolver does the LaunchServices lookup. Daemons rarely have
            // an installed bundle — the resolver falls back to a dashed
            // placeholder gracefully.
            AppIconResolver.iconView(
                for: AppIdentity(bundleID: bid, displayName: item.name, bundlePath: nil),
                size: 28
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: typeSymbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var typeSymbolName: String {
        switch item.type {
        case .app:            "app.fill"
        case .legacyDaemon:   "gearshape.2.fill"
        case .developerGroup: "folder.fill"
        case .unknown:        "questionmark.circle.fill"
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
            .ppFont(.badge)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, PPSpacing.xxs)
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
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            BackgroundItemsSection(items: [], dataSource: .live)
        }
        .padding(16)
    }
    .frame(width: 520, height: 240)
    .environment(AppViewModel())
}

#Preview("Empty — FDA denied") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            BackgroundItemsSection(
                items: [],
                dataSource: .live,
                error: .permissionDenied(reason: "FDA needed")
            )
        }
        .padding(16)
    }
    .frame(width: 520, height: 480)
    .environment(AppViewModel())
}

#Preview("Populated — Mock") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(16)
    }
    .frame(width: 520, height: 240)
    .environment(AppViewModel())
}
