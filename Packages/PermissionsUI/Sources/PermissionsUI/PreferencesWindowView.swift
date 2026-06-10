import SwiftUI

/// Preferences window — native macOS TabView with four tabs:
/// General / Scanning / Digest / Data.
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
            DigestSettingsTab()
                .tabItem { Label(String(localized: "Digest"), systemImage: "bell.badge") }
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
                LabeledContent(String(localized: "Keep snapshots for")) {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(vm.store.snapshotRetentionDays) },
                                set: { vm.store.snapshotRetentionDays = Int($0.rounded()) }
                            ),
                            in: Double(PreferencesStore.snapshotRetentionDaysRange.lowerBound)
                                ... Double(PreferencesStore.snapshotRetentionDaysRange.upperBound),
                            step: 1
                        )
                        Text(daysLabel(vm.store.snapshotRetentionDays))
                            .ppFont(.metadata)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                }
                Text(String(localized: "Older snapshots are pruned automatically on the next scan."))
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Snapshot Retention"))
            }

            Section {
                LabeledContent(String(localized: "Flag apps unused for")) {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(vm.store.staleThresholdDays) },
                                set: { vm.store.staleThresholdDays = Int($0.rounded()) }
                            ),
                            in: Double(PreferencesStore.staleThresholdDaysRange.lowerBound)
                                ... Double(PreferencesStore.staleThresholdDaysRange.upperBound),
                            step: 1
                        )
                        Text(daysLabel(vm.store.staleThresholdDays))
                            .ppFont(.metadata)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                }
                Text(String(localized: "Apps unused for this long appear in the Stale Apps tab."))
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Stale Apps"))
            }
        }
        .formStyle(.grouped)
    }

    private func daysLabel(_ days: Int) -> String {
        days == 1
            ? String(localized: "1 day")
            : String(localized: "\(days) days")
    }
}

// MARK: - Digest tab

private struct DigestSettingsTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel

    private static let weekdayLabels: [(value: Int, label: String)] = [
        (1, String(localized: "Sunday")),
        (2, String(localized: "Monday")),
        (3, String(localized: "Tuesday")),
        (4, String(localized: "Wednesday")),
        (5, String(localized: "Thursday")),
        (6, String(localized: "Friday")),
        (7, String(localized: "Saturday")),
    ]

    var body: some View {
        @Bindable var vm = viewModel

        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { vm.digestEnabled },
                    set: { newValue in Task { await vm.handleDigestToggle(to: newValue) } }
                )) {
                    VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                        Text(String(localized: "Send weekly digest"))
                            .ppFont(.body)
                        Text(String(localized: "A local notification summarizing this week's changes. macOS will ask for permission the first time you turn this on."))
                            .ppFont(.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(.accentColor)

                Picker(String(localized: "Day"), selection: $vm.store.digestWeekday) {
                    ForEach(Self.weekdayLabels, id: \.value) { entry in
                        Text(entry.label).tag(entry.value)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!vm.digestEnabled)

                DatePicker(
                    String(localized: "Time"),
                    selection: Binding(
                        get: { vm.store.digestTime() },
                        set: { vm.store.setDigestTime($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .disabled(!vm.digestEnabled)
            } header: {
                Text(String(localized: "Weekly Digest"))
            }

            if vm.digestEnabled {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                            Text(String(localized: "Send test notification"))
                                .ppFont(.body)
                                .fontWeight(.medium)
                            Text(String(localized: "Fires a one-off banner in 5 seconds. Useful for verifying delivery without waiting for the scheduled day."))
                                .ppFont(.metadata)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: PPSpacing.md)
                        Button {
                            Task {
                                await vm.sendTestNotification()
                                try? await Task.sleep(nanoseconds: 8_000_000_000)
                                vm.clearTestNotificationResult()
                            }
                        } label: {
                            Text(String(localized: "Send"))
                                .frame(minWidth: 60)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(vm.testNotificationResult == .scheduling)
                    }

                    if let resultText = testResultText(vm.testNotificationResult) {
                        Text(resultText)
                            .ppFont(.metadata)
                            .foregroundStyle(testResultColor(vm.testNotificationResult))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            hintSection(vm: viewModel)
        }
        .formStyle(.grouped)
        .task {
            await vm.refreshAuthorizationHint()
        }
    }

    @ViewBuilder
    private func hintSection(vm: PreferencesViewModel) -> some View {
        switch vm.authorizationHint {
        case .notYetRequested, .disabled:
            EmptyView()
        case .scheduled:
            Section {
                statusRow(
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    primary: String(localized: "Weekly digest is on."),
                    secondary: nextFireSecondary(vm: vm)
                )
            }
        case .denied:
            Section {
                statusRow(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    primary: String(localized: "Notifications are off in System Settings."),
                    secondary: String(localized: "Re-enable them to receive the weekly digest.")
                )
                Button(String(localized: "Open Notifications…")) {
                    SystemSettingsLink.openNotifications()
                }
            }
        }
    }

    private func nextFireSecondary(vm: PreferencesViewModel) -> String? {
        guard let date = vm.nextWeeklyFireDate else { return nil }
        let formatted = DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .short)
        return String(localized: "Next: \(formatted)")
    }

    private func statusRow(icon: String, tint: Color, primary: String, secondary: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .ppFont(.secondary)
                .foregroundStyle(tint)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                Text(primary)
                    .ppFont(.metadata)
                    .fontWeight(.medium)
                if let secondary {
                    Text(secondary)
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func testResultText(_ result: PreferencesViewModel.TestNotificationResult) -> String? {
        switch result {
        case .idle: return nil
        case .scheduling: return String(localized: "Scheduling…")
        case .scheduled(let seconds):
            return String(localized: "Test notification scheduled. Switch away from Permission Pulse to see the banner in \(Int(seconds)) seconds.")
        case .notAuthorized:
            return String(localized: "Notifications are not authorized. Open Notifications in System Settings to re-enable.")
        case .failed(let message):
            return String(localized: "Test send failed: \(message)")
        }
    }

    private func testResultColor(_ result: PreferencesViewModel.TestNotificationResult) -> Color {
        switch result {
        case .idle, .scheduling, .scheduled: return .secondary
        case .notAuthorized, .failed: return .orange
        }
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
                Text(String(localized: "Deletes all snapshots, dismissed items, snoozes, and preferences. This cannot be undone."))
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(String(localized: "Reset Permission Pulse?"), isPresented: $isConfirmingReset) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Reset"), role: .destructive) { onResetAllData?() }
        } message: {
            Text(String(localized: "All snapshots, dismissed items, snoozes, and preferences will be deleted. This cannot be undone."))
        }
    }
}
