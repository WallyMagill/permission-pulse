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
                Text(String(localized: "Apps unused for this long appear in the Stale Apps tab."))
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

// MARK: - Digest tab

private struct DigestSettingsTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clearResultTask: Task<Void, Never>?

    private static let testResultDisplayDuration: Duration = .seconds(8)

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
                    set: { newValue in
                        // Write the store before the async hop so the switch
                        // flips on this frame instead of snapping back first.
                        vm.digestEnabled = newValue
                        Task { await vm.handleDigestToggle(to: newValue) }
                    }
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
                            // Cancel any in-flight auto-clear so a re-tap's
                            // result isn't wiped early by the previous timer.
                            clearResultTask?.cancel()
                            clearResultTask = Task {
                                await vm.sendTestNotification()
                                try? await Task.sleep(for: Self.testResultDisplayDuration)
                                guard !Task.isCancelled else { return }
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
        // Sections appear/disappear from three state sources (the toggle, the
        // async authorization hint, the timed test-result clear) — track the
        // reflow so rows don't pop and snap the form around.
        .animation(reduceMotion ? nil : .default, value: vm.digestEnabled)
        .animation(reduceMotion ? nil : .default, value: vm.authorizationHint)
        .animation(reduceMotion ? nil : .default, value: vm.testNotificationResult)
        .task {
            await vm.refreshAuthorizationHint()
        }
        .onDisappear { clearResultTask?.cancel() }
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
            return String(localized: "Test notification scheduled. The banner will appear in \(Int(seconds)) seconds.")
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
            Text(String(localized: "All snapshots, dismissed items, snoozes, and preferences will be deleted. Permission Pulse will rescan immediately. This cannot be undone."))
        }
    }
}
