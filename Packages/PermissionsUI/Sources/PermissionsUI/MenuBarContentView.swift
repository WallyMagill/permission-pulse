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
        .frame(width: 300)
    }

    @ViewBuilder
    private var statusArea: some View {
        switch attentionState {
        case .fdaDenied:
            AttentionRow(
                text: String(localized: "Full Disk Access needed"),
                systemImage: "exclamationmark.triangle.fill",
                trailingSymbol: "arrow.up.right.square",
                action: { SystemSettingsLink.openFullDiskAccess() }
            )
        case .btmOnlyFDADenied:
            AttentionRow(
                text: String(localized: "FDA needed for background items"),
                systemImage: "exclamationmark.triangle.fill",
                trailingSymbol: "arrow.up.right.square",
                action: { SystemSettingsLink.openFullDiskAccess() }
            )
        case .schemaMismatch:
            AttentionRow(
                text: String(localized: "Schema mismatch — open for details"),
                systemImage: "exclamationmark.triangle.fill",
                trailingSymbol: "chevron.right",
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

private struct AttentionRow: View {
    let text: String
    let systemImage: String
    let trailingSymbol: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
                Text(text)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: trailingSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.orange.opacity(0.15) : Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
