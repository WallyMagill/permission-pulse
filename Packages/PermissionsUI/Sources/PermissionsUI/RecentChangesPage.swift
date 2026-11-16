import SwiftUI

struct RecentChangesDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    let searchText: String
    var onMarkAllReviewed: (() -> Void)?

    var body: some View {
        // The diff content (a List or ContentUnavailableView) is the detail-pane
        // root, matching every other section. A bare VStack root here let the
        // pane size to its content instead of filling, which made
        // NavigationSplitView mis-lay-out its sidebar column. The window picker
        // rides in a top safe-area inset — pinned without distorting the pane,
        // and it also keeps the picker steady across populated/empty windows.
        DiffTabView(
            diff: diff,
            window: viewModel.recentChangesWindow,
            searchText: searchText,
            storeProblem: viewModel.snapshotStoreProblem,
            diffUnavailable: viewModel.diffUnavailable,
            permissionScope: viewModel.permissionScope,
            onMarkAllReviewed: onMarkAllReviewed
        )
        .id(viewModel.recentChangesWindow)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationTitle(String(localized: "Recent Changes"))
    }

    private var header: some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: PPSpacing.sm) {
            Picker("", selection: $viewModel.recentChangesWindow) {
                Text(String(localized: "Since Last Review")).tag(RecentChangesWindow.sinceLastReview)
                Text(String(localized: "Last 7 days")).tag(RecentChangesWindow.lastSevenDays)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(String(localized: "Change window"))
            if viewModel.snapshotWriteFailed {
                Label(
                    RecentChangesStatus.writeFailedLine(latestSnapshotDate: viewModel.latestSnapshotDate),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .ppFont(.metadata)
                .foregroundStyle(PPColor.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(statusLines, id: \.self) { line in
                Text(line)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(PPSpacing.lg)
        .background(.windowBackground)
    }

    private var diff: SnapshotDiffs? {
        switch viewModel.recentChangesWindow {
        case .sinceLastReview: viewModel.latestDiffSinceReview
        case .lastSevenDays: viewModel.latestDiffWeek
        }
    }

    private var statusLines: [String] {
        RecentChangesStatus.lines(diff: diff, latestSnapshotDate: viewModel.latestSnapshotDate)
    }
}
