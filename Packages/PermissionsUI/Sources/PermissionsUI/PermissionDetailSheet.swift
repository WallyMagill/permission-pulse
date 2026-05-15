import AppKit
import SwiftUI
import PermissionsCore

// Per-row detail sheet for a single TCC grant. Shows:
//  • app name + bundle ID
//  • service name + automation target (when applicable)
//  • the service's plain-English risk description
//  • a button that deep-links into the matching Settings pane
//
// Triggered by tapping a row in PermissionsSection. Matches the
// FDAGrantSheet visual language (header icon + title, body copy, action
// row).
public struct PermissionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let grant: PermissionGrant

    public init(grant: PermissionGrant) {
        self.grant = grant
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            riskBlock
            metaBlock
            footer
        }
        .padding(24)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            appIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(grant.app.displayName)
                    .font(.title2.weight(.semibold))
                Text(grant.service.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let path = grant.app.bundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path.path(percentEncoded: false)))
                .resizable()
                .frame(width: 40, height: 40)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
        }
    }

    private var riskBlock: some View {
        Text(grant.service.riskDescription)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Bundle ID: \(grant.app.bundleID)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if grant.service == .automation, let target = grant.automationTarget {
                Text(String(localized: "Controls: \(target)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(String(localized: "Last modified: \(formattedDate(grant.lastModified))"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(String(localized: "Close")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(String(localized: "Open in Settings")) {
                SystemSettingsLink.open(for: grant.service)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}
