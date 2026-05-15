import AppKit
import SwiftUI
import PermissionsCore

// Per-app detail sheet for an AutomationGroup — one app with multiple
// Apple Events targets (e.g. Raycast → System Events / Messages /
// Shortcuts Events). Mirrors PermissionDetailSheet's structure but
// surfaces each target with its own last-modified row.
public struct AutomationDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let group: AutomationGroup

    init(group: AutomationGroup) {
        self.group = group
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            riskBlock
            targetsBlock
            metaBlock
            footer
        }
        .padding(24)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconResolver.iconView(for: group.app, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.app.displayName)
                    .font(.title2.weight(.semibold))
                Text(String(localized: "Automation · \(group.targets.count) targets"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var riskBlock: some View {
        Text(PermissionService.automation.riskDescription)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var targetsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Controls"))
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(group.targets.enumerated()), id: \.offset) { index, grant in
                    targetRow(grant: grant)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                    if index < group.targets.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func targetRow(grant: PermissionGrant) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grant.automationTarget ?? "(unset)")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Text(String(localized: "Granted \(formattedDate(grant.lastModified))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var metaBlock: some View {
        Text(String(localized: "Bundle ID: \(group.app.bundleID)"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(String(localized: "Close")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(String(localized: "Open in Settings")) {
                SystemSettingsLink.open(for: .automation)
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
