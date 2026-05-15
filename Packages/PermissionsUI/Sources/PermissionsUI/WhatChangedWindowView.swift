import SwiftUI
import PermissionsCore
import PermissionsStore

public struct WhatChangedWindowView: View {
    @Environment(AppViewModel.self) private var viewModel
    private let onAppeared: (() -> Void)?

    public init(onAppeared: (() -> Void)? = nil) {
        self.onAppeared = onAppeared
    }

    @State private var selectedTab: WhatChangedTab = .yesterday

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                Divider()
                ScrollView {
                    selectedTabContent
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle(String(localized: "What Changed"))
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { onAppeared?() }
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text(String(localized: "Yesterday")).tag(WhatChangedTab.yesterday)
            Text(String(localized: "Last week")).tag(WhatChangedTab.lastWeek)
            Text(String(localized: "Stale apps")).tag(WhatChangedTab.staleApps)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(12)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .yesterday:
            DiffTabView(diff: viewModel.latestDiffYesterday, windowLabel: .yesterday)
        case .lastWeek:
            DiffTabView(diff: viewModel.latestDiffWeek, windowLabel: .lastWeek)
        case .staleApps:
            StaleAppsTabView(staleApps: viewModel.staleApps)
        }
    }
}

private enum WhatChangedTab: Hashable {
    case yesterday
    case lastWeek
    case staleApps
}
