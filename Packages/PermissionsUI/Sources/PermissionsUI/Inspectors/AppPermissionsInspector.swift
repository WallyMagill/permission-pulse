// AppKit: NSWorkspace reveals a bundle in Finder (read-only) and
// NSPasteboard copies text the user pastes into Terminal themselves —
// Permission Pulse never executes the commands.
import AppKit
import SwiftUI
import PermissionsCore

/// Inspector panel for a selected app's TCC grants.
///
/// Ports the content of `AppPermissionsDetailSheet` into the non-modal
/// trailing inspector layout — same sections (risk, service pills,
/// automation card, action footer) rendered in a narrow scrollable column.
struct AppPermissionsInspector: View {
    let app: AppIdentity
    let grants: [PermissionGrant]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                header

                if let highest = highestRiskService {
                    riskSection(highest: highest)
                }

                servicePillsSection

                if !automationGrants.isEmpty {
                    automationSection
                }

                actionFooter
            }
            .padding(PPSpacing.lg)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            AppIconResolver.iconView(for: app, size: 40)
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(app.displayName)
                    .ppFont(.cardHeader)
                    .lineLimit(2)
                Text(app.bundleID)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Risk section

    private func riskSection(highest: PermissionService) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            SheetSectionLabel(String(localized: "Risk"))
            VStack(alignment: .leading, spacing: 6) {
                SheetRiskPanel(text: highest.riskDescription)
                if distinctServices.count > 1 {
                    Text(String(localized: "Highest-risk service shown."))
                        .ppFont(.metadata)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 2)
                }
            }
        }
    }

    // MARK: - Service pills section

    private var servicePillsSection: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            SheetSectionLabel(String(localized: "Granted Services"))
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
    }

    // MARK: - Automation section

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            SheetSectionLabel(String(localized: "Controls"))
            automationCard
        }
    }

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
                Text(grant.automationTarget ?? String(localized: "(unset)"))
                    .font(Font.system(.subheadline).monospaced())
                    .textSelection(.enabled)
                Text(String(localized: "Granted \(sheetFormattedDate(grant.lastModified))"))
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Action footer

    private var actionFooter: some View {
        VStack(spacing: PPSpacing.sm) {
            if !resetCommands.isEmpty {
                Text(String(localized: "Permission Pulse won't run these — paste them into Terminal yourself."))
                    .ppFont(.metadata)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let path = app.bundlePath {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([path])
                } label: {
                    Label(String(localized: "Reveal in Finder"), systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
            }
            if !resetCommands.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(resetCommands.joined(separator: "\n"), forType: .string)
                } label: {
                    Label(String(localized: "Copy Reset Commands"), systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .help(String(localized: "Copies tccutil reset commands to run yourself in Terminal."))
            }
        }
        .controlSize(.large)
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
}
