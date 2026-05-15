import AppKit
import SwiftUI
import PermissionsCore

// Per-row detail sheet for a single LaunchAgent / LaunchDaemon entry.
//
// Launch agents are not apps — they are property-list-defined background
// helpers. The sheet shows the launchd properties (program, args, load
// triggers) plus the file path so the user can inspect or remove the
// underlying .plist via Finder. There is no System Settings deep-link
// for launch agents.
public struct LaunchAgentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let item: LaunchAgentItem

    public init(item: LaunchAgentItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            propertiesBlock
            pathBlock
            footer
        }
        .padding(24)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(scopeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var propertiesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            propertyRow(label: String(localized: "Program"), value: item.programPath ?? String(localized: "(unset)"))
            propertyRow(
                label: String(localized: "Arguments"),
                value: item.programArguments.isEmpty
                    ? String(localized: "(none)")
                    : item.programArguments.joined(separator: " ")
            )
            propertyRow(label: String(localized: "Run at load"), value: item.runAtLoad ? "Yes" : "No")
            propertyRow(label: String(localized: "Keep alive"), value: item.keepAlive ? "Yes" : "No")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var pathBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Source directory"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.sourceDirectory.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(String(localized: "Close")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(String(localized: "Reveal in Finder")) {
                revealInFinder()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private func propertyRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var scopeLabel: String {
        switch item.sourceDirectory {
        case .userLaunchAgents:     String(localized: "User Launch Agent")
        case .libraryLaunchAgents:  String(localized: "System-wide Launch Agent")
        case .libraryLaunchDaemons: String(localized: "Launch Daemon")
        }
    }

    private func revealInFinder() {
        let expanded = (item.sourceDirectory.path as NSString).expandingTildeInPath
        let dir = URL(fileURLWithPath: expanded, isDirectory: true)
        let probable = dir.appendingPathComponent("\(item.label).plist")
        if FileManager.default.fileExists(atPath: probable.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([probable])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        }
    }
}
