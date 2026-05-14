import AppKit
import SwiftUI

public struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppViewModel.self) private var viewModel

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permission Pulse")
                .font(.headline)

            Divider()

            Text("\(viewModel.grants.count) permissions tracked")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(viewModel.launchAgents.count) launch agents")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                openWindow(id: "detail")
            } label: {
                Label("Open Permission Pulse", systemImage: "shield.lefthalf.filled")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(12)
        .frame(width: 280)
    }
}
