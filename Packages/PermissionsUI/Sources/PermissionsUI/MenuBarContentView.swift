import AppKit
import SwiftUI
import PermissionsCore

public struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppViewModel.self) private var viewModel

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Permission Pulse"))
                .font(.headline)

            Divider()

            permissionsLine

            Text(String(localized: "\(viewModel.launchAgents.count) launch agents"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                openWindow(id: "detail")
            } label: {
                Label(String(localized: "Open Permission Pulse"), systemImage: "shield.lefthalf.filled")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button(String(localized: "Quit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(12)
        .frame(width: 280)
    }

    @ViewBuilder
    private var permissionsLine: some View {
        switch viewModel.tccScanError {
        case .permissionDenied:
            Button {
                SystemSettingsLink.openFullDiskAccess()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(String(localized: "Full Disk Access needed"))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        case .schemaMismatch, .unsupportedOnThisOS:
            Button {
                openWindow(id: "detail")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(String(localized: "TCC schema not recognized"))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        case nil:
            Text(String(localized: "\(viewModel.grants.count) permissions tracked"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
