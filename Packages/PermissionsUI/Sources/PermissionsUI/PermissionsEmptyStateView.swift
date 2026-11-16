import SwiftUI
import PermissionsCore

struct PermissionsEmptyStateView: View {
    let error: ScannerError?
    let domain: ScannerDomain
    let scope: PermissionScope

    // Explicit binding so the disclosure survives parent recomposition.
    @State private var isDisclosureExpanded = false

    init(error: ScannerError?, domain: ScannerDomain = .tcc, scope: PermissionScope = .full) {
        self.error = error
        self.domain = domain
        self.scope = scope
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
                Text(String(localized: "Just updated? macOS turns Full Disk Access off for each new version. If Permission Pulse already looks enabled, switch it off and on again, then quit and reopen."))
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
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
        .padding(.top, PPSpacing.xxl)
        .padding(.bottom, PPSpacing.xl)
        // Top-anchored, not centered: expanding the disclosure grows the stack
        // downward only. Centering would shift everything (including the
        // disclosure label just clicked) up by half the expansion height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Text(String(localized: "The database is busy right now. Use Rescan to try again."))
        }
    }

    private var emptyView: some View {
        let copy = Self.emptyCopy(domain: domain, scope: scope)
        return ContentUnavailableView {
            Label(copy.headline, systemImage: "tray")
        } description: {
            Text(copy.description)
        }
    }

    /// With a reduced scope an empty list says nothing about Camera or the
    /// other hidden services, so the copy names what was actually checked.
    static func emptyCopy(domain: ScannerDomain, scope: PermissionScope) -> (headline: String, description: String) {
        switch domain {
        case .tcc where scope.isReduced:
            (
                String(localized: "No apps hold system-level permissions"),
                String(localized: "No app holds \(PermissionScope.systemLevelServiceList). macOS 27 hides every other permission from apps.")
            )
        case .tcc:
            (
                String(localized: "No permissions yet"),
                String(localized: "No app permissions have been recorded on this Mac.")
            )
        case .btm:
            (
                String(localized: "No background items yet"),
                String(localized: "No background items have been recorded on this Mac.")
            )
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
}

/// "No results" for a search that names a service macOS hides from apps.
struct HiddenServiceSearchView: View {
    let service: PermissionService

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "Hidden by macOS"), systemImage: "eye.slash")
        } description: {
            Text(PermissionScope.hiddenServiceMessage(service))
        } actions: {
            Button(PermissionScope.openServiceSettingsTitle(service)) {
                SystemSettingsLink.open(for: service)
            }
        }
    }
}
