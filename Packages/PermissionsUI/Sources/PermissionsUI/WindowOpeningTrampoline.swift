import SwiftUI

/// Content of the hidden settings-trampoline window. Code without SwiftUI's
/// `openWindow` (the app delegate) sets `AppViewModel.windowToOpen`; this
/// view opens that scene and clears the request.
public struct WindowOpeningTrampoline: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        EmptyView()
            .frame(width: 0, height: 0)
            .onAppear { openRequestedWindow() }
            .onChange(of: viewModel.windowToOpen) { _, _ in openRequestedWindow() }
    }

    private func openRequestedWindow() {
        guard let id = viewModel.windowToOpen else { return }
        viewModel.windowToOpen = nil
        openWindow(id: id)
        // The scene's window exists once this update finishes.
        Task { @MainActor in WindowActivation.bringToFront(sceneID: id) }
    }
}
