import SwiftUI
import PermissionsCore

struct PermissionsEmptyStateView: View {
    let error: ScannerError?

    var body: some View {
        switch error {
        case .permissionDenied:
            permissionDeniedView
        case .schemaMismatch, .unsupportedOnThisOS:
            schemaMismatchView
        case nil:
            emptyView
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(String(localized: "Full Disk Access required"))
                .font(.headline)
            Text(String(
                localized: "Permission Pulse reads the macOS TCC databases to list the permissions you've granted. Without Full Disk Access, those databases are unreadable."
            ))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SystemSettingsLink.openFullDiskAccess()
            } label: {
                Label(String(localized: "Grant Access in System Settings"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
            Text(String(localized: "You'll need to relaunch Permission Pulse after granting."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
            DisclosureGroup(String(localized: "Why does Permission Pulse need this?")) {
                Text(String(
                    localized: "Permission Pulse opens TCC.db in read-only mode and never modifies it. It does not send any data over the network. Source is open on GitHub."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .font(.footnote)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var schemaMismatchView: some View {
        VStack(spacing: 8) {
            Text(String(localized: "Permissions unavailable"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "See the banner above for details."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        Text(String(localized: "No permissions yet"))
            .foregroundStyle(.secondary)
    }
}
