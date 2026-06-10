import SwiftUI
import PermissionsCore

struct PermissionsEmptyStateView: View {
    let error: ScannerError?
    let domain: ScannerDomain

    // Explicit binding so the disclosure survives parent recomposition.
    @State private var isDisclosureExpanded = false

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
        VStack(spacing: PPSpacing.md) {
            ContentUnavailableView {
                Label(String(localized: "Full Disk Access Required"), systemImage: "lock.shield")
            } description: {
                Text(permissionDeniedBody)
            } actions: {
                Button(String(localized: "Grant Access in System Settings…")) {
                    SystemSettingsLink.openFullDiskAccess()
                }
                .buttonStyle(.borderedProminent)
            }
            VStack(spacing: PPSpacing.sm) {
                Text(String(localized: "You'll need to relaunch Permission Pulse after granting."))
                    .ppFont(.metadata)
                    .foregroundStyle(.tertiary)
                Button {
                    AppRelauncher.relaunch()
                } label: {
                    HStack(spacing: PPSpacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                        Text(String(localized: "Quit & Reopen"))
                    }
                    .ppFont(.metadata)
                    .fontWeight(.medium)
                }
                .buttonStyle(.link)
                .accessibilityHint(String(localized: "Restarts Permission Pulse so a newly granted permission takes effect"))
            }
            DisclosureGroup(
                String(localized: "Why does Permission Pulse need this?"),
                isExpanded: $isDisclosureExpanded
            ) {
                Text(disclosureBody)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .padding(.top, PPSpacing.xs)
            }
            .ppFont(.metadata)
        }
        .padding(.vertical, PPSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    private var schemaMismatchView: some View {
        ContentUnavailableView {
            Label(unavailableHeadline, systemImage: "exclamationmark.triangle")
        } description: {
            Text(String(localized: "See the banner above for details."))
        }
    }

    private var temporarilyUnavailableView: some View {
        ContentUnavailableView {
            Label(String(localized: "Temporarily Unavailable"), systemImage: "clock.badge.exclamationmark")
        } description: {
            Text(String(localized: "The database is busy right now. Use Refresh to try again."))
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(emptyHeadline, systemImage: "tray")
        } description: {
            Text(emptyDescription)
        }
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

    private var emptyDescription: String {
        switch domain {
        case .tcc: String(localized: "No app permissions have been recorded on this Mac.")
        case .btm: String(localized: "No background items have been recorded on this Mac.")
        }
    }
}
