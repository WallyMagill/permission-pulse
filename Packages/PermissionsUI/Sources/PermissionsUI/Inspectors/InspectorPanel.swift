import SwiftUI
import PermissionsCore

/// Trailing inspector content host. Resolves the current selection against
/// live scan data; Tasks 4–5 swap the per-type placeholder for real panels.
struct InspectorPanel: View {
    @Environment(AppViewModel.self) private var viewModel
    let selection: InspectorSelection?

    var body: some View {
        Group {
            switch resolvedContent {
            case .app(let app, _):
                placeholder(title: app.displayName) // Task 4: AppPermissionsInspector
            case .launchAgent(let item):
                placeholder(title: item.label)      // Task 5: LaunchAgentInspector
            case .backgroundItem(let item):
                placeholder(title: item.name)       // Task 5: BackgroundItemInspector
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

    private func placeholder(title: String) -> some View {
        ContentUnavailableView(title, systemImage: "info.circle")
    }
}
