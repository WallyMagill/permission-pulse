import SwiftUI
import PermissionsCore

public struct DetailWindowView: View {
    @Environment(AppViewModel.self) private var viewModel
    private let onRefresh: (() async -> Void)?

    public init(onRefresh: (() async -> Void)? = nil) {
        self.onRefresh = onRefresh
    }

    public var body: some View {
        @Bindable var bindableViewModel = viewModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let tccError = viewModel.tccScanError, isSchemaIssue(tccError) {
                        SchemaMismatchBanner(error: tccError, domain: .tcc)
                    }
                    if let btmError = viewModel.btmScanError, isSchemaIssue(btmError) {
                        SchemaMismatchBanner(error: btmError, domain: .btm)
                    }

                    PermissionsSection(
                        grants: viewModel.grants,
                        dataSource: viewModel.tccDataSource,
                        error: viewModel.tccScanError
                    )

                    LaunchAgentsSection(
                        items: viewModel.launchAgents,
                        dataSource: viewModel.launchAgentsDataSource
                    )

                    BackgroundItemsSection(
                        items: viewModel.btmItems,
                        dataSource: viewModel.btmDataSource,
                        error: viewModel.btmScanError
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(String(localized: "Permission Pulse"))
            .toolbar {
                if let onRefresh {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await onRefresh() }
                        } label: {
                            Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $bindableViewModel.showFDASheetOnDetail) {
            FDAGrantSheet()
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private func isSchemaIssue(_ error: ScannerError) -> Bool {
        switch error {
        case .schemaMismatch, .unsupportedOnThisOS: true
        default: false
        }
    }
}
