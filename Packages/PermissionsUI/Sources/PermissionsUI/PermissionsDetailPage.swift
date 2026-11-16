import SwiftUI
import PermissionsCore

struct PermissionsDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let searchText: String
    @Binding var selection: InspectorSelection?

    var body: some View {
        VStack(spacing: 0) {
            ScanAvailabilityBanner(
                availability: viewModel.tccAvailability,
                domainName: String(localized: "Permissions"),
                unavailableSources: viewModel.tccUnavailableSources
            )
            .padding([.horizontal, .top], PPSpacing.lg)
            .padding(.bottom, PPSpacing.sm)
            content
        }
        // A scan can land a schema error while the page is open; animate the
        // banner in instead of shoving the list down by a full banner height.
        .animation(reduceMotion ? nil : .default, value: viewModel.tccScanError == nil)
        .navigationTitle(String(localized: "Permissions"))
        .navigationSubtitle(subtitle)
    }

    @ViewBuilder
    private var content: some View {
        let groups = self.groups
        if let error = viewModel.tccScanError, isSchemaIssue(error) {
            VStack(spacing: 0) {
                SchemaMismatchBanner(error: error, domain: .tcc)
                    .padding(PPSpacing.lg)
                grantList(groups)
            }
        } else if ScanState.showsScanningPlaceholder(
            isScanning: viewModel.scanInProgress,
            isEmpty: viewModel.grants.isEmpty,
            hasError: viewModel.tccScanError != nil,
            isSearching: !searchText.isEmpty
        ) {
            ScanningStateView()
        } else if viewModel.grants.isEmpty, viewModel.tccScanError != nil {
            PermissionsEmptyStateView(error: viewModel.tccScanError, domain: .tcc)
        } else if groups.isEmpty, let hidden = viewModel.permissionScope.hiddenService(matching: searchText) {
            HiddenServiceSearchView(service: hidden)
        } else if viewModel.grants.isEmpty {
            PermissionsEmptyStateView(error: nil, domain: .tcc, scope: viewModel.permissionScope)
        } else if groups.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            grantList(groups)
        }
    }

    private func grantList(_ groups: [AppGrantGroup]) -> some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                AppGrantRow(group: group)
                    .tag(InspectorSelection.app(appKey: group.appKey))
            }
        }
        .listStyle(.inset)
    }

    private struct AppGrantGroup: Identifiable {
        let appKey: String
        let app: AppIdentity
        let grants: [PermissionGrant]
        let appMissing: Bool
        var id: String { appKey }
    }

    private var groups: [AppGrantGroup] {
        let filtered: [PermissionGrant]
        if searchText.isEmpty {
            filtered = viewModel.grants
        } else {
            let q = searchText.lowercased()
            filtered = viewModel.grants.filter { grant in
                grant.app.displayName.lowercased().contains(q)
                    || grant.app.bundleID.lowercased().contains(q)
                    || grant.service.displayName.lowercased().contains(q)
            }
        }
        let missing = viewModel.missingAppKeys
        return Dictionary(grouping: filtered, by: \.appKey)
            .map { key, grants in
                AppGrantGroup(
                    appKey: key,
                    app: grants[0].app,
                    grants: grants,
                    appMissing: missing.contains(key)
                )
            }
            .sorted { $0.app.displayName.localizedCaseInsensitiveCompare($1.app.displayName) == .orderedAscending }
    }

    private var subtitle: String {
        guard !viewModel.grants.isEmpty else { return "" }
        let appCount = Set(viewModel.grants.map(\.appKey)).count
        let serviceCount = Set(viewModel.grants.map(\.service)).count
        let apps = appCount == 1
            ? String(localized: "1 app")
            : String(localized: "\(appCount) apps")
        let services = serviceCount == 1
            ? String(localized: "1 service")
            : String(localized: "\(serviceCount) services")
        return String(localized: "\(apps) · \(services)")
    }

    private struct AppGrantRow: View {
        let group: AppGrantGroup

        var body: some View {
            HStack(spacing: PPSpacing.md) {
                AppIconResolver.iconView(for: group.app, size: 28)
                VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                    Text(group.app.displayName).ppFont(.body)
                    Text(serviceLine)
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: PPSpacing.sm)
                if group.appMissing {
                    AppNotFoundBadge()
                }
                Text("\(distinctServices.count)")
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, PPSpacing.xxs)
            .accessibilityElement(children: .combine)
        }

        private var distinctServices: [String] {
            Set(group.grants.map(\.service))
                .map(\.displayName)
                .sorted()
        }

        private var serviceLine: String {
            distinctServices.joined(separator: " · ")
        }
    }
}
