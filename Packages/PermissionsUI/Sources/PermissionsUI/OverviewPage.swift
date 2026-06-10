import SwiftUI
import PermissionsCore

/// The window's landing page: answers "am I okay?" — every row deep-links.
struct OverviewPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var section: SidebarItem?

    var body: some View {
        Form {
            if hasAttentionContent {
                Section(String(localized: "Needs Attention")) {
                    attentionRows
                }
            }
            Section(String(localized: "At a Glance")) {
                countRow(
                    title: String(localized: "Permissions"),
                    systemImage: "lock.shield",
                    count: viewModel.grants.count,
                    target: .permissions
                )
                countRow(
                    title: String(localized: "Launch Agents"),
                    systemImage: "clock",
                    count: viewModel.launchAgents.count,
                    target: .launchAgents
                )
                countRow(
                    title: String(localized: "Background Items"),
                    systemImage: "square.stack.3d.up",
                    count: viewModel.btmItems.count,
                    target: .backgroundItems
                )
                if let risk = PermissionRiskSummary.line(for: viewModel.grants) {
                    Label(risk, systemImage: "exclamationmark.shield")
                        .foregroundStyle(.secondary)
                }
            }
            Section(String(localized: "Status")) {
                LabeledContent(String(localized: "Last Scan")) {
                    Text(lastScanText)
                }
                LabeledContent(String(localized: "Full Disk Access")) {
                    Text(fdaStatusText)
                        .foregroundStyle(fdaStatusColor)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Overview"))
    }

    private var hasAttentionContent: Bool {
        viewModel.attentionState != .clean || viewModel.hasUnreviewedChanges
    }

    @ViewBuilder
    private var attentionRows: some View {
        switch viewModel.attentionState {
        case .fdaDenied:
            attentionRow(
                String(localized: "Full Disk Access needed to scan permissions"),
                target: .permissions
            )
        case .btmOnlyFDADenied:
            attentionRow(
                String(localized: "Full Disk Access needed for background items"),
                target: .backgroundItems
            )
        case .schemaMismatch:
            attentionRow(
                String(localized: "A data source changed format — some items may be missing"),
                target: .permissions
            )
        case .launchAgentError:
            attentionRow(
                String(localized: "Launch Agents couldn't be read"),
                target: .launchAgents
            )
        case .clean:
            EmptyView()
        }
        if viewModel.hasUnreviewedChanges {
            attentionRow(
                String(localized: "\(viewModel.recentChangeEventCount) unreviewed changes"),
                target: .recentChanges
            )
        }
    }

    private func attentionRow(_ title: String, target: SidebarItem) -> some View {
        Button { section = target } label: {
            HStack {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .ppFont(.badge)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func countRow(title: String, systemImage: String, count: Int, target: SidebarItem) -> some View {
        Button { section = target } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .ppFont(.badge)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lastScanText: String {
        guard let date = viewModel.lastScanDate else {
            return viewModel.scanInProgress
                ? String(localized: "Scanning…")
                : String(localized: "Not yet scanned")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var fdaStatusText: String {
        switch viewModel.attentionState {
        case .fdaDenied, .btmOnlyFDADenied: String(localized: "Not granted")
        default: String(localized: "Granted")
        }
    }

    private var fdaStatusColor: Color {
        switch viewModel.attentionState {
        case .fdaDenied, .btmOnlyFDADenied: PPColor.warning
        default: .secondary
        }
    }
}
