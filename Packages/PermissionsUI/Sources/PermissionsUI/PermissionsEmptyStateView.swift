import SwiftUI
import PermissionsCore

struct PermissionsEmptyStateView: View {
    @Environment(AppViewModel.self) private var viewModel

    let error: ScannerError?
    let domain: ScannerDomain

    init(error: ScannerError?, domain: ScannerDomain = .tcc) {
        self.error = error
        self.domain = domain
    }

    var body: some View {
        switch error {
        case .permissionDenied:
            permissionDeniedView
        case .schemaMismatch, .unsupportedOnThisOS:
            schemaMismatchView
        case .temporarilyUnavailable:
            temporarilyUnavailableView
        case nil:
            emptyView
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "Full Disk Access required"))
                .font(.headline)
            Text(permissionDeniedBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.showFDASheetOnDetail = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .accessibilityHidden(true)
                    Text(String(localized: "Grant Access in System Settings"))
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.blue)
            .padding(.vertical, 4)
            VStack(spacing: 6) {
                Text(String(localized: "You'll need to relaunch Permission Pulse after granting."))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Button {
                    AppRelauncher.relaunch()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                        Text(String(localized: "Quit & Reopen"))
                    }
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.link)
                .accessibilityHint(String(localized: "Restarts Permission Pulse so a newly granted permission takes effect"))
            }
            DisclosureGroup(String(localized: "Why does Permission Pulse need this?")) {
                Text(disclosureBody)
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
            Text(unavailableHeadline)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "See the banner above for details."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var temporarilyUnavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "Temporarily unavailable"))
                .font(.headline)
            Text(String(localized: "The database is busy right now. Use Refresh to try again."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        Text(emptyHeadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionDeniedBody: String {
        switch domain {
        case .tcc:
            String(
                localized: "Permission Pulse reads the macOS TCC databases to list the permissions you've granted. Without Full Disk Access, those databases are unreadable."
            )
        case .btm:
            String(
                localized: "Permission Pulse reads the Background Task Management database to list the login items and background helpers registered with macOS. Without Full Disk Access, that database is unreadable."
            )
        }
    }

    private var disclosureBody: String {
        switch domain {
        case .tcc:
            String(
                localized: "Permission Pulse opens TCC.db in read-only mode and never modifies it. It does not send any data over the network. Source is open on GitHub."
            )
        case .btm:
            String(
                localized: "Permission Pulse opens the BTM database in read-only mode and never modifies it. It does not send any data over the network. Source is open on GitHub."
            )
        }
    }

    private var unavailableHeadline: String {
        switch domain {
        case .tcc: String(localized: "Permissions unavailable")
        case .btm: String(localized: "Background items unavailable")
        }
    }

    private var emptyHeadline: String {
        switch domain {
        case .tcc: String(localized: "No permissions yet")
        case .btm: String(localized: "No background items yet")
        }
    }
}
