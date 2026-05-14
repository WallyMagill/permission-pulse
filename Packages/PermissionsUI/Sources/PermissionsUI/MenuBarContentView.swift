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

            statusArea

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
    private var statusArea: some View {
        switch attentionState {
        case .fdaDenied:
            attentionButton(
                text: String(localized: "Full Disk Access needed"),
                action: { SystemSettingsLink.openFullDiskAccess() }
            )
        case .btmOnlyFDADenied:
            attentionButton(
                text: String(localized: "Full Disk Access needed for background items"),
                action: { SystemSettingsLink.openFullDiskAccess() }
            )
        case .schemaMismatch:
            attentionButton(
                text: String(localized: "Permission Pulse schema mismatch"),
                action: { openWindow(id: "detail") }
            )
        case .clean:
            Text(String(localized: "\(viewModel.grants.count) permissions tracked"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(String(localized: "\(viewModel.btmItems.count) background items"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func attentionButton(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(text)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private enum AttentionState {
        case fdaDenied
        case btmOnlyFDADenied
        case schemaMismatch
        case clean
    }

    private var attentionState: AttentionState {
        let tccDenied = isPermissionDenied(viewModel.tccScanError)
        let btmDenied = isPermissionDenied(viewModel.btmScanError)
        if tccDenied { return .fdaDenied }
        if btmDenied { return .btmOnlyFDADenied }
        if isSchemaIssue(viewModel.tccScanError) || isSchemaIssue(viewModel.btmScanError) {
            return .schemaMismatch
        }
        return .clean
    }

    private func isPermissionDenied(_ error: ScannerError?) -> Bool {
        switch error {
        case .permissionDenied: true
        default: false
        }
    }

    private func isSchemaIssue(_ error: ScannerError?) -> Bool {
        switch error {
        case .schemaMismatch, .unsupportedOnThisOS: true
        default: false
        }
    }
}
