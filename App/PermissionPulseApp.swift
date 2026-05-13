import SwiftUI
import PermissionsUI

@main
struct PermissionPulseApp: App {
    @State private var viewModel = AppViewModel()
    @State private var coordinator: ScanCoordinator?

    var body: some Scene {
        // Settings trampoline: works around the Tahoe MenuBarExtra/openSettings
        // regression by routing through a regular window. Must be declared
        // before any Settings scene. See docs/03-architecture.md.
        WindowGroup(id: "settings-trampoline") {
            EmptyView().frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)

        MenuBarExtra("Permission Pulse", systemImage: "shield.lefthalf.filled") {
            MenuBarContentView()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Permission Pulse", id: "detail") {
            DetailWindowView()
                .environment(viewModel)
                .task {
                    if coordinator == nil {
                        coordinator = ScanCoordinator(viewModel: viewModel)
                    }
                    await coordinator?.runMockScan()
                }
        }
        .windowResizability(.contentSize)
    }
}
