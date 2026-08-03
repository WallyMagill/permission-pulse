import SwiftUI
import PermissionsCore

/// Trailing inspector content host. Resolves the current selection against
/// live scan data and routes to the matching per-type inspector panel.
struct InspectorPanel: View {
    @Environment(AppViewModel.self) private var viewModel
    let selection: InspectorSelection?

    var body: some View {
        Group {
            switch resolvedContent {
            case .app(let app, let grants):
                AppPermissionsInspector(app: app, grants: grants)
            case .launchAgent(let item):
                LaunchAgentInspector(item: item)
            case .backgroundItem(let item):
                BackgroundItemInspector(item: item)
            case nil:
                if selection == nil {
                    ContentUnavailableView(
                        String(localized: "No Selection"),
                        systemImage: "sidebar.trailing",
                        description: Text(String(localized: "Select an item to see its details."))
                    )
                } else {
                    ContentUnavailableView(
                        String(localized: "No Longer Present"),
                        systemImage: "questionmark.app.dashed",
                        description: Text(String(localized: "This item isn't in the latest scan. It may have been removed."))
                    )
                }
            }
        }
    }

    private var resolvedContent: InspectorContent? {
        InspectorContentResolver.resolve(
            selection,
            grants: viewModel.grants,
            launchAgents: viewModel.launchAgents,
            btmItems: viewModel.btmItems
        )
    }
}
