import SwiftUI

/// Preferences window — native macOS TabView with four tabs:
/// General / Scanning / Notifications / Data.
public struct PreferencesWindowView: View {
    @Environment(PreferencesViewModel.self) private var viewModel
    private let onResetAllData: (() -> Void)?
    private let scanInProgress: () -> Bool

    public init(
        onResetAllData: (() -> Void)? = nil,
        scanInProgress: @escaping () -> Bool = { false }
    ) {
        self.onResetAllData = onResetAllData
        self.scanInProgress = scanInProgress
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            ScanningSettingsTab()
                .tabItem { Label(String(localized: "Scanning"), systemImage: "clock.arrow.circlepath") }
            NotificationsSettingsTab()
                .tabItem { Label(String(localized: "Notifications"), systemImage: "bell.badge") }
            DataSettingsTab(onResetAllData: onResetAllData, scanInProgress: scanInProgress)
                .tabItem { Label(String(localized: "Data"), systemImage: "externaldrive") }
        }
        .frame(width: 560, height: 440)
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel

    var body: some View {
        Form {
            Toggle(
                String(localized: "Launch at login"),
                isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { newValue in Task { await viewModel.setLaunchAtLogin(newValue) } }
                )
            )
            Text(String(localized: "Permission Pulse starts in the menu bar when you log in."))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scanning tab

private struct ScanningSettingsTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        Form {
            Section {
                DaysSliderRow(
                    label: String(localized: "Keep snapshots for"),
                    value: Binding(
                        get: { vm.store.snapshotRetentionDays },
                        set: { vm.store.snapshotRetentionDays = $0 }
                    ),
                    range: PreferencesStore.snapshotRetentionDaysRange
                )
                Text(String(localized: "Older snapshots are pruned automatically on the next scan."))
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Snapshot Retention"))
            }

            Section {
                DaysSliderRow(
                    label: String(localized: "Flag apps unused for"),
                    value: Binding(
                        get: { vm.store.staleThresholdDays },
                        set: { vm.store.staleThresholdDays = $0 }
                    ),
                    range: PreferencesStore.staleThresholdDaysRange
                )
                Text(String(localized: "Apps unused for this long appear under Stale Apps in the sidebar."))
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Stale Apps"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct DaysSliderRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = Int($0.rounded()) }
                    ),
                    in: Double(range.lowerBound) ... Double(range.upperBound),
                    step: 1
                )
                Text(daysLabel(value))
                    .ppFont(.metadata)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 60, alignment: .trailing)
            }
        }
    }

    private func daysLabel(_ days: Int) -> String {
        days == 1
            ? String(localized: "1 day")
            : String(localized: "\(days) days")
    }
}

// MARK: - Data tab

private struct DataSettingsTab: View {
    let onResetAllData: (() -> Void)?
    let scanInProgress: () -> Bool
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Export current state")) {
                    ExportToolbarMenu()
                }
            }
            Section {
                Button(String(localized: "Reset All Data…"), role: .destructive) {
                    isConfirmingReset = true
                }
                .disabled(scanInProgress() || onResetAllData == nil)
                Text(String(localized: "Deletes all snapshots, dismissed items, snoozes, and settings. This cannot be undone."))
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                if scanInProgress() {
                    Text(String(localized: "Reset is disabled while a scan is in progress."))
                        .ppFont(.metadata)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .alert(String(localized: "Reset Permission Pulse?"), isPresented: $isConfirmingReset) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Reset"), role: .destructive) { onResetAllData?() }
        } message: {
            Text(String(localized: "All snapshots, dismissed items, snoozes, and settings will be deleted. Permission Pulse will rescan immediately. This cannot be undone."))
        }
    }
}
