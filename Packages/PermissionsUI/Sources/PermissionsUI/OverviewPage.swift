import SwiftUI
import PermissionsCore

/// The window's landing page: answers "am I okay?" — every row deep-links.
struct OverviewPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var section: SidebarItem?
    @State private var isShowingCoverageInfo = false

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
                    count: Self.countDisplay(viewModel.grants.count, availability: viewModel.tccAvailability),
                    target: .permissions
                )
                countRow(
                    title: String(localized: "Launch Agents"),
                    systemImage: "clock",
                    count: Self.countDisplay(
                        viewModel.launchAgents.count,
                        availability: viewModel.launchAgentAvailability
                    ),
                    target: .launchAgents
                )
                countRow(
                    title: String(localized: "Background Items"),
                    systemImage: "square.stack.3d.up",
                    count: Self.countDisplay(viewModel.btmItems.count, availability: viewModel.btmAvailability),
                    target: .backgroundItems
                )
                if let risk = PermissionRiskSummary.line(for: viewModel.grants) {
                    Label(risk, systemImage: "exclamationmark.shield")
                        .foregroundStyle(.secondary)
                }
            }
            statusSection
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Overview"))
    }

    private var statusSection: some View {
        Section(String(localized: "Status")) {
            LabeledContent(String(localized: "Last Scan")) {
                Text(lastScanText)
            }
            LabeledContent(String(localized: "Full Disk Access")) {
                Text(fdaStatusText)
                    .foregroundStyle(fdaStatusColor)
            }
            LabeledContent(String(localized: "Permission coverage")) {
                coverageValue
            }
        }
    }

    private var coverageValue: some View {
        let scope = viewModel.permissionScope
        return HStack(spacing: PPSpacing.xs) {
            Text(scope.coverageText(hasData: viewModel.hasPermissionData))
            if scope.isReduced {
                Button {
                    isShowingCoverageInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "About permission coverage"))
                .popover(isPresented: $isShowingCoverageInfo, arrowEdge: .bottom) {
                    Text(ScanAvailabilityBanner.reducedScopeExplanation)
                        .ppFont(.metadata)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 280)
                        .padding(PPSpacing.md)
                }
            }
        }
    }

    /// A domain not scanned yet, or whose scan failed before it ever
    /// succeeded, has no count to show; "0" would claim the scan found nothing.
    static func countDisplay(_ count: Int, availability: ScanAvailability) -> (value: String, note: String?) {
        switch availability {
        case .never: ("—", String(localized: "Not scanned yet"))
        case .failed(nil, _): ("—", String(localized: "Not readable"))
        default: ("\(count)", nil)
        }
    }

    private var hasAttentionContent: Bool {
        !viewModel.attentionItems.isEmpty || viewModel.hasUnreviewedChanges
            || viewModel.isTranslocated
    }

    @ViewBuilder
    private var attentionRows: some View {
        if viewModel.isTranslocated {
            Label(
                String(localized: "Move Permission Pulse to your Applications folder, then open it from there."),
                systemImage: "folder.badge.questionmark"
            )
        }
        ForEach(viewModel.attentionItems, id: \.domain) { item in
            attentionRow(
                Self.attentionTitle(item.state, domain: item.domain),
                target: item.domain.route.sidebarItem
            )
        }
        if viewModel.hasUnreviewedChanges {
            attentionRow(
                viewModel.unreviewedChangeCount == 1
                    ? String(localized: "1 unreviewed change")
                    : String(localized: "\(viewModel.unreviewedChangeCount) unreviewed changes"),
                target: .recentChanges
            )
        }
    }

    static func attentionTitle(_ state: AttentionState, domain: AttentionDomain) -> String {
        let name = domain.displayName
        return switch state {
        case .fdaDenied: String(localized: "Full Disk Access needed to scan permissions")
        case .btmOnlyFDADenied: String(localized: "Full Disk Access needed for background items")
        case .launchAgentError: String(localized: "Launch Agents couldn't be read")
        case .schemaMismatch: String(localized: "\(name) changed format — some items may be missing")
        case .degradedData: String(localized: "\(name) scan is degraded — some sources are missing")
        case .staleData: String(localized: "\(name) scan is stale — showing last-known results")
        case .scanFailed: String(localized: "\(name) scan failed — no results are available")
        case .historyNotRecorded: String(localized: "History isn't being recorded")
        case .clean: ""
        }
    }

    private func attentionRow(_ title: String, target: SidebarItem) -> some View {
        Button {
            if target == .recentChanges { viewModel.recentChangesWindow = .sinceLastReview }
            section = target
        } label: {
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

    private func countRow(
        title: String,
        systemImage: String,
        count: (value: String, note: String?),
        target: SidebarItem
    ) -> some View {
        Button { section = target } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                if let note = count.note {
                    Text(note)
                        .ppFont(.metadata)
                        .foregroundStyle(PPColor.warning)
                }
                Text(count.value)
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
        // Before the first completed scan (fresh launch, or right after Reset
        // All Data) attention is .clean by default, which would read as a
        // false "Granted"; say so instead of asserting a status we don't have.
        guard viewModel.lastScanDate != nil else {
            return viewModel.scanInProgress
                ? String(localized: "Checking…")
                : String(localized: "Unknown")
        }
        switch viewModel.attentionState {
        case .fdaDenied, .btmOnlyFDADenied: return String(localized: "Not granted")
        default: return String(localized: "Granted")
        }
    }

    private var fdaStatusColor: Color {
        switch viewModel.attentionState {
        case .fdaDenied, .btmOnlyFDADenied: PPColor.warning
        default: .secondary
        }
    }
}
