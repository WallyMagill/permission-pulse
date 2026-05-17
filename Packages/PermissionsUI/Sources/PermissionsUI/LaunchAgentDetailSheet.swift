import AppKit
import SwiftUI
import PermissionsCore

// Per-row detail sheet for a single LaunchAgent / LaunchDaemon entry.
//
// Launch agents are not apps — they are property-list-defined background
// helpers. The sheet shows the launchd properties plus the file path so the
// user can inspect or remove the underlying .plist via Finder. No System
// Settings deep-link exists for launch agents.
public struct LaunchAgentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let item: LaunchAgentItem

    public init(item: LaunchAgentItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 16)

            SheetSectionLabel(String(localized: "Properties"))
                .padding(.bottom, 6)
            SheetKVCard(rows: propertyRows)
                .padding(.bottom, 14)

            SheetSectionLabel(String(localized: "Source"))
                .padding(.bottom, 6)
            sourcePathLine
                .padding(.bottom, 16)

            footer
        }
        .padding(22)
        .frame(width: 460)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 13) {
            SheetGradientTile(symbol: "gearshape.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                Text(scopeLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var propertyRows: [SheetKVRow] {
        [
            SheetKVRow(
                String(localized: "Program"),
                item.programPath ?? String(localized: "(unset)"),
                mono: true
            ),
            SheetKVRow(
                String(localized: "Arguments"),
                item.programArguments.isEmpty
                    ? String(localized: "(none)")
                    : item.programArguments.joined(separator: " "),
                mono: true
            ),
            SheetKVRow(String(localized: "Run at load"), item.runAtLoad ? "Yes" : "No"),
            SheetKVRow(String(localized: "Keep alive"), item.keepAlive ? "Yes" : "No"),
        ]
    }

    private var sourcePathLine: some View {
        Text(item.sourceDirectory.path)
            .font(.system(size: 12).monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .vibrancyCard()
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
