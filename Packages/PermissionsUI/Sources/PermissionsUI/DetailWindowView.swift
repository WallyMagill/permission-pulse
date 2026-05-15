import SwiftUI
import PermissionsCore

public struct DetailWindowView: View {
    @Environment(AppViewModel.self) private var viewModel
    private let onRefresh: (() async -> Void)?
    private let onWhatChangedSelected: (() -> Void)?

    @State private var mode: AppViewModel.DetailMode = .current

    public init(
        onRefresh: (() async -> Void)? = nil,
        onWhatChangedSelected: (() -> Void)? = nil
    ) {
        self.onRefresh = onRefresh
        self.onWhatChangedSelected = onWhatChangedSelected
    }

    public var body: some View {
        @Bindable var bindableViewModel = viewModel

        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch mode {
                        case .current:
                            currentContent
                        case .whatChanged:
                            WhatChangedSection()
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { applyPendingModeIfAny() }
        .onChange(of: viewModel.pendingDetailMode) { _, _ in applyPendingModeIfAny() }
        .onChange(of: mode) { _, newMode in
            if newMode == .whatChanged {
                onWhatChangedSelected?()
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text(String(localized: "Current")).tag(AppViewModel.DetailMode.current)
            Text(String(localized: "What Changed")).tag(AppViewModel.DetailMode.whatChanged)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var currentContent: some View {
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

    // Handles both first-open (onAppear) and re-open while the window is
    // still alive (onChange of pendingDetailMode). The menu-bar buttons set
    // the pending mode and then call openWindow.
    private func applyPendingModeIfAny() {
        guard let pending = viewModel.pendingDetailMode else { return }
        mode = pending
        viewModel.pendingDetailMode = nil
        if pending == .whatChanged {
            onWhatChangedSelected?()
        }
    }

    private func isSchemaIssue(_ error: ScannerError) -> Bool {
        switch error {
        case .schemaMismatch, .unsupportedOnThisOS: true
        default: false
        }
    }
}
