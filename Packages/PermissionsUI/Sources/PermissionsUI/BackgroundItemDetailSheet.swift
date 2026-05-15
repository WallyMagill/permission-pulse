import AppKit
import SwiftUI
import PermissionsCore

// Per-row detail sheet for a single BTM (Background Task Management) entry.
//
// macOS exposes login items in System Settings → General → Login Items, but
// the per-item revocation flow is UI-driven there (toggle off, confirm).
// We deep-link to that pane and surface the BTM properties for inspection.
public struct BackgroundItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let item: BTMItem

    public init(item: BTMItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            propertiesBlock
            footer
        }
        .padding(24)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            iconView
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            DispositionBadge(disposition: item.disposition)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let bid = item.bundleIdentifier,
           !bid.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: typeSymbolName)
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
        }
    }

    private var propertiesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            propertyRow(label: String(localized: "Type"), value: typeLabel)
            propertyRow(label: String(localized: "Scope"), value: scopeLabel)
            propertyRow(label: String(localized: "Identifier"), value: item.identifier, monospaced: true)
            if let bid = item.bundleIdentifier, !bid.isEmpty {
                propertyRow(label: String(localized: "Bundle ID"), value: bid, monospaced: true)
            }
            if let tid = item.teamIdentifier, !tid.isEmpty {
                propertyRow(label: String(localized: "Team ID"), value: tid, monospaced: true)
            }
            propertyRow(label: String(localized: "Modified"), value: formattedDate(item.modificationDate))
            if let parent = item.parentIdentifier, !parent.isEmpty {
                propertyRow(label: String(localized: "Parent"), value: parent, monospaced: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(String(localized: "Close")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(String(localized: "Open Login Items")) {
                SystemSettingsLink.openLoginItems()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private func propertyRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(monospaced ? .body.monospaced() : .body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var subtitle: String? {
        if let dev = item.developerName, !dev.isEmpty { return dev }
        if let bid = item.bundleIdentifier, !bid.isEmpty { return bid }
        return nil
    }

    private var typeSymbolName: String {
        switch item.type {
        case .app:            "app.fill"
        case .legacyDaemon:   "gearshape.2.fill"
        case .developerGroup: "folder.fill"
        case .unknown:        "questionmark.circle.fill"
        }
    }

    private var typeLabel: String {
        switch item.type {
        case .app:                  String(localized: "App")
        case .legacyDaemon:         String(localized: "Legacy daemon")
        case .developerGroup:       String(localized: "Developer group")
        case .unknown(let rawValue): String(localized: "Unknown (0x\(String(rawValue, radix: 16)))")
        }
    }

    private var scopeLabel: String {
        switch item.scope {
        case .system:                String(localized: "System-wide")
        case .user:                  String(localized: "Root user")
        case .perUser(let uuid):     String(localized: "Current user (\(uuid))")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}

// Re-declared here because the version in BackgroundItemsSection is private.
// Kept identical so visual treatment matches the row badge.
private struct DispositionBadge: View {
    let disposition: BTMItem.Disposition

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: .capsule)
    }

    private var label: String {
        switch disposition {
        case .enabled:  String(localized: "Enabled")
        case .disabled: String(localized: "Disabled")
        case .unknown:  String(localized: "Unknown")
        }
    }

    private var color: Color {
        switch disposition {
        case .enabled:  .green
        case .disabled: .gray
        case .unknown:  .orange
        }
    }
}
