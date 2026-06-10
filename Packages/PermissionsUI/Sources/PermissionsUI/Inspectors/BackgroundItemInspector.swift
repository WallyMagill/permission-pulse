import AppKit
import SwiftUI
import PermissionsCore

/// Inspector panel for a selected BTM (Background Task Management) entry.
///
/// Ports the content of `BackgroundItemDetailSheet` into the non-modal trailing
/// inspector layout — header with icon or gradient tile, properties card, and
/// a full-width "Open Login Items" action.
struct BackgroundItemInspector: View {
    let item: BTMItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                header
                propertiesSection
                actionFooter
            }
            .padding(PPSpacing.lg)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            iconView
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(item.name)
                    .ppFont(.cardHeader)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .ppFont(.metadata)
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
                .frame(width: 40, height: 40)
        } else {
            SheetGradientTile(symbol: item.type.symbolName, size: 40)
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
        var rows: [SheetKVRow] = [
            SheetKVRow(String(localized: "Type"), item.type.displayName),
            SheetKVRow(String(localized: "Scope"), item.scope.detailedDisplayName),
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

    // MARK: - Action footer

    private var actionFooter: some View {
        Button {
            SystemSettingsLink.openLoginItems()
        } label: {
            Label(String(localized: "Open Login Items"), systemImage: "gear")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    // MARK: - Derived properties

    private var subtitle: String? {
        if let dev = item.developerName, !dev.isEmpty { return dev }
        if let bid = item.bundleIdentifier, !bid.isEmpty { return bid }
        return nil
    }

}
