import AppKit
import SwiftUI
import PermissionsCore

struct StaleAppsTabView: View {
    let staleApps: [StaleApp]

    var body: some View {
        if staleApps.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Apps with active grants you haven't used in 90+ days"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(staleApps.enumerated()), id: \.offset) { index, app in
                        StaleAppRow(app: app)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        if index < staleApps.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text(String(localized: "No stale apps")).font(.headline)
            Text(String(localized: "Every app with an active grant has been used recently."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}

private struct StaleAppRow: View {
    let app: StaleApp

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(app.app.displayName).font(.body.weight(.medium))
                Text(app.app.bundleID).font(.caption).foregroundStyle(.secondary)
                Text(servicesLine).font(.caption).foregroundStyle(.tertiary)
                Text(lastUsedLine).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var icon: some View {
        AppIconResolver.iconView(for: app.app, size: 36)
    }

    private var servicesLine: String {
        let names = app.grantedServices.map(\.displayName).sorted().joined(separator: ", ")
        return String(localized: "Granted: \(names)")
    }

    private var lastUsedLine: String {
        let dateString = DateFormatter.localizedString(
            from: app.lastUsedDate,
            dateStyle: .medium,
            timeStyle: .none
        )
        let source = app.dateSource == .spotlight
            ? String(localized: "via Spotlight")
            : String(localized: "via file modified")
        return String(localized: "Last used \(dateString) · \(source) · \(app.daysSinceUsed) days ago")
    }
}
