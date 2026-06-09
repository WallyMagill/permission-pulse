import AppKit
import SwiftUI
import PermissionsCore

// Per-app permissions detail sheet — Tahoe Vibrant style.
//
// One sheet per app, listing every service the app has been granted as a
// clickable pill (tap → open that service's pane in System Settings). The
// risk panel shows the highest-severity service's description so users see
// the most consequential capability first. Automation grants with targets
// expand into a Controls section below.
//
// Replaces the legacy per-grant PermissionDetailSheet and per-app
// AutomationDetailSheet.
public struct AppPermissionsDetailSheet: View {
    private let app: AppIdentity
    private let grants: [PermissionGrant]
    @Environment(\.dismiss) private var dismiss

    public init(app: AppIdentity, grants: [PermissionGrant]) {
        self.app = app
        self.grants = grants
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 16)

            if let highest = highestRiskService {
                SheetSectionLabel(String(localized: "Risk"))
                    .padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 6) {
                    SheetRiskPanel(text: highest.riskDescription)
                    if distinctServices.count > 1 {
                        Text(String(localized: "Highest-risk service shown."))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 2)
                    }
                }
                .padding(.bottom, 14)
            }

            SheetSectionLabel(String(localized: "Granted Services"))
                .padding(.bottom, 8)
            servicePills
                .padding(.bottom, automationGrants.isEmpty ? 16 : 14)

            if !automationGrants.isEmpty {
                SheetSectionLabel(String(localized: "Controls"))
                    .padding(.bottom, 6)
                automationCard
                    .padding(.bottom, 16)
            }

            actionFooter
        }
        .padding(22)
        .frame(width: 460)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 13) {
            AppIconResolver.iconView(for: app, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.system(size: 17, weight: .semibold))
                Text(app.bundleID)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Service pills

    private var servicePills: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(distinctServices, id: \.self) { service in
                ServicePillButton(
                    service: service,
                    date: mostRecentDate(for: service),
                    action: { SystemSettingsLink.open(for: service) }
                )
            }
        }
    }

    // MARK: - Automation card

    private var automationCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedAutomationGrants.enumerated()), id: \.offset) { index, grant in
                if index > 0 {
                    Divider().padding(.leading, 14)
                }
                automationRow(grant: grant)
            }
        }
        .vibrancyCard()
    }

    private func automationRow(grant: PermissionGrant) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grant.automationTarget ?? "(unset)")
                    .font(.system(size: 12.5).monospaced())
                    .textSelection(.enabled)
                Text(String(localized: "Granted \(sheetFormattedDate(grant.lastModified))"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Derived state

    private var distinctServices: [PermissionService] {
        var seen = Set<PermissionService>()
        var ordered: [PermissionService] = []
        for grant in grants where seen.insert(grant.service).inserted {
            ordered.append(grant.service)
        }
        return ordered.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var highestRiskService: PermissionService? {
        distinctServices.max { $0.riskSeverity < $1.riskSeverity }
    }

    private var automationGrants: [PermissionGrant] {
        grants.filter { $0.service == .automation }
    }

    private var sortedAutomationGrants: [PermissionGrant] {
        automationGrants.sorted { $0.lastModified > $1.lastModified }
    }

    private func mostRecentDate(for service: PermissionService) -> Date? {
        grants
            .filter { $0.service == service }
            .map(\.lastModified)
            .max()
    }

    private var resetCommands: [String] {
        PermissionService.tccutilResetCommands(bundleID: app.bundleID, services: distinctServices)
    }

    @ViewBuilder
    private var actionFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !resetCommands.isEmpty {
                Text(String(localized: "Permission Pulse won't run these — paste them into Terminal yourself."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                if app.bundlePath != nil {
                    Button(String(localized: "Reveal in Finder")) { revealInFinder() }
                }
                if !resetCommands.isEmpty {
                    Button(String(localized: "Copy Reset Commands")) { copyResetCommands() }
                }
                Button(String(localized: "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // AppKit: NSPasteboard is the system clipboard; we only copy text the user
    // pastes into Terminal themselves. Permission Pulse never executes it.
    private func copyResetCommands() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resetCommands.joined(separator: "\n"), forType: .string)
    }

    // AppKit: NSWorkspace reveals an existing bundle in Finder (read-only).
    private func revealInFinder() {
        guard let url = app.bundlePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
