import AppKit
import SwiftUI
import PermissionsCore

/// Inspector panel for a selected LaunchAgent / LaunchDaemon entry.
///
/// Ports the content of `LaunchAgentDetailSheet` into the non-modal trailing
/// inspector layout — header, properties card, source path card, and a
/// full-width "Reveal in Finder" action.
struct LaunchAgentInspector: View {
    let item: LaunchAgentItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                header
                propertiesSection
                sourceSection
                actionFooter
            }
            .padding(PPSpacing.lg)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            SheetGradientTile(symbol: "gearshape.fill", size: 40)
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(item.label)
                    .ppFont(.cardHeader)
                    .lineLimit(2)
                Text(scopeLabel)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Properties section

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            SheetSectionLabel(String(localized: "Properties"))
            SheetKVCard(rows: propertyRows)
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
            SheetKVRow(String(localized: "Run at load"), item.runAtLoad ? String(localized: "Yes") : String(localized: "No")),
            SheetKVRow(String(localized: "Keep alive"), item.keepAlive ? String(localized: "Yes") : String(localized: "No")),
            SheetKVRow(String(localized: "Disabled"), item.isDisabled ? String(localized: "Yes") : String(localized: "No")),
        ]
    }

    // MARK: - Source section

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            SheetSectionLabel(String(localized: "Source"))
            Text(item.sourceDirectory.path)
                .font(Font.system(.subheadline).monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .vibrancyCard()
        }
    }

    // MARK: - Action footer

    private var actionFooter: some View {
        Button {
            revealInFinder()
        } label: {
            Label(String(localized: "Reveal in Finder"), systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    // MARK: - Helpers

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
