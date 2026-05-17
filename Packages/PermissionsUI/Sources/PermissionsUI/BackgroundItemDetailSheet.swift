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
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 16)

            SheetSectionLabel(String(localized: "Properties"))
                .padding(.bottom, 6)
            SheetKVCard(rows: propertyRows)
                .padding(.bottom, 16)

            footer
        }
        .padding(22)
        .frame(width: 460)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 13) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
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
            SheetGradientTile(symbol: typeSymbolName)
        }
    }

    private var propertyRows: [SheetKVRow] {
        var rows: [SheetKVRow] = [
            SheetKVRow(String(localized: "Type"), typeLabel),
            SheetKVRow(String(localized: "Scope"), scopeLabel),
            SheetKVRow(String(localized: "Identifier"), item.identifier, mono: true),
        ]
        if let bid = item.bundleIdentifier, !bid.isEmpty {
            rows.append(SheetKVRow(String(localized: "Bundle ID"), bid, mono: true))
        }
        if let tid = item.teamIdentifier, !tid.isEmpty {
            rows.append(SheetKVRow(String(localized: "Team ID"), tid, mono: true))
        }
        rows.append(SheetKVRow(String(localized: "Modified"), sheetFormattedDate(item.modificationDate)))
        if let parent = item.parentIdentifier, !parent.isEmpty {
            rows.append(SheetKVRow(String(localized: "Parent"), parent, mono: true))
        }
        return rows
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
