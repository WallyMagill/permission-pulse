import SwiftUI
import PermissionsCore
import PermissionsStore

// The What Changed surface that lives inside the unified detail window when
// `mode == .whatChanged`. Owns the Yesterday / Last week / Stale apps
// sub-picker and renders the appropriate tab. The styling mirrors the
// .regularMaterial card pattern used by the Current-mode sections so both
// modes feel like one window.
struct WhatChangedSection: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var selectedTab: WhatChangedTab = .yesterday

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $selectedTab) {
                Text(String(localized: "Yesterday")).tag(WhatChangedTab.yesterday)
                Text(String(localized: "Last week")).tag(WhatChangedTab.lastWeek)
                Text(String(localized: "Stale apps")).tag(WhatChangedTab.staleApps)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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
}

private enum WhatChangedTab: Hashable {
    case yesterday
    case lastWeek
    case staleApps
}
