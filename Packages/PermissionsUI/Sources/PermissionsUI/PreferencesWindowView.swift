import SwiftUI

// Preferences window — Tahoe Vibrant style.
//
// Two tabs, both built from the same primitives as the detail sheets
// (`vibrancyCard()`, `SheetSectionLabel`) so this window feels like part
// of the rest of the app, not a stock macOS preferences panel.
public struct PreferencesWindowView: View {
    @Environment(PreferencesViewModel.self) private var viewModel

    private let onResetAllData: (() -> Void)?
    private let scanInProgress: () -> Bool

    @State private var selectedTab: Tab = .snapshots

    enum Tab: Hashable {
        case snapshots
        case notifications
    }

    public init(
        onResetAllData: (() -> Void)? = nil,
        scanInProgress: @escaping () -> Bool = { false }
    ) {
        self.onResetAllData = onResetAllData
        self.scanInProgress = scanInProgress
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 14)

            ScrollView {
                Group {
                    switch selectedTab {
                    case .snapshots:
                        SnapshotsPreferencesTab(
                            onResetAllData: onResetAllData,
                            resetDisabled: scanInProgress()
                        )
                    case .notifications:
                        NotificationsPreferencesTab()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .frame(width: 560, height: 460)
        .background(WindowBackground())
        .navigationTitle(String(localized: "Preferences"))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.snapshots, title: String(localized: "Snapshots"), symbol: "clock.fill")
            tabButton(.notifications, title: String(localized: "Notifications"), symbol: "bell.fill")
            Spacer()
        }
    }

    private func tabButton(_ tab: Tab, title: String, symbol: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor.opacity(0.14)
                        : Color.clear
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window background (matches detail window canvas)

private struct WindowBackground: View {
    var body: some View {
        #if canImport(AppKit)
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
        #else
        Color.white.ignoresSafeArea()
        #endif
    }
}

// MARK: - Snapshots tab

private struct SnapshotsPreferencesTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel
    private let onResetAllData: (() -> Void)?
    private let resetDisabled: Bool

    init(onResetAllData: (() -> Void)? = nil, resetDisabled: Bool = false) {
        self.onResetAllData = onResetAllData
        self.resetDisabled = resetDisabled
    }

    var body: some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 22) {
            sliderSection(
                label: String(localized: "Snapshot Retention"),
                title: String(localized: "Keep snapshots for"),
                value: Binding(
                    get: { Double(vm.store.snapshotRetentionDays) },
                    set: { vm.store.snapshotRetentionDays = Int($0.rounded()) }
                ),
                range: Double(PreferencesStore.snapshotRetentionDaysRange.lowerBound)
                    ... Double(PreferencesStore.snapshotRetentionDaysRange.upperBound),
                currentDays: vm.store.snapshotRetentionDays,
                footnote: String(localized: "Older snapshots are pruned automatically on the next scan.")
            )

            sliderSection(
                label: String(localized: "Stale Apps"),
                title: String(localized: "Flag apps unused for"),
                value: Binding(
                    get: { Double(vm.store.staleThresholdDays) },
                    set: { vm.store.staleThresholdDays = Int($0.rounded()) }
                ),
                range: Double(PreferencesStore.staleThresholdDaysRange.lowerBound)
                    ... Double(PreferencesStore.staleThresholdDaysRange.upperBound),
                currentDays: vm.store.staleThresholdDays,
                footnote: String(localized: "Apps unused for this long appear in the Stale Apps tab.")
            )

            resetSection
        }
    }

    private func sliderSection(
        label: String,
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        currentDays: Int,
        footnote: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetSectionLabel(label)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 13))
                    Spacer()
                    Text(daysLabel(currentDays))
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
                Slider(value: value, in: range, step: 1)
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .vibrancyCard()
        }
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetSectionLabel(String(localized: "Reset"))

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Deletes all saved snapshots, dismissals, snoozes, and preferences. Permission Pulse will rescan immediately. This cannot be undone."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        onResetAllData?()
                    } label: {
                        Text(String(localized: "Reset All Data…"))
                    }
                    .disabled(onResetAllData == nil || resetDisabled)
                }

                if resetDisabled {
                    Text(String(localized: "Reset is disabled while a scan is in progress."))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(14)
            .vibrancyCard()
        }
    }

    private func daysLabel(_ days: Int) -> String {
        days == 1
            ? String(localized: "1 day")
            : String(localized: "\(days) days")
    }
}

// MARK: - Notifications tab

private struct NotificationsPreferencesTab: View {
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

        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                SheetSectionLabel(String(localized: "Weekly Digest"))

                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(
                        get: { vm.digestEnabled },
                        set: { newValue in
                            Task { await vm.handleDigestToggle(to: newValue) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Send weekly digest"))
                                .font(.system(size: 13))
                            Text(String(localized: "A local notification summarizing this week's changes. macOS will ask for permission the first time you turn this on."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(.accentColor)

                    Divider()

                    HStack(alignment: .firstTextBaseline) {
                        Text(String(localized: "Day"))
                            .font(.system(size: 13))
                            .frame(width: 90, alignment: .leading)
                        Picker("", selection: $vm.store.digestWeekday) {
                            ForEach(Self.weekdayLabels, id: \.value) { entry in
                                Text(entry.label).tag(entry.value)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(!vm.digestEnabled)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(String(localized: "Time"))
                            .font(.system(size: 13))
                            .frame(width: 90, alignment: .leading)
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { vm.store.digestTime() },
                                set: { vm.store.setDigestTime($0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .disabled(!vm.digestEnabled)
                    }
                }
                .padding(14)
                .vibrancyCard()

                hintCard

                if vm.digestEnabled {
                    diagnosticsCard(vm: vm)
                }
            }
        }
        .task {
            await vm.refreshAuthorizationHint()
        }
    }

    @ViewBuilder
    private var hintCard: some View {
        switch viewModel.authorizationHint {
        case .notYetRequested, .disabled:
            EmptyView()
        case .scheduled:
            statusRow(
                icon: "checkmark.circle.fill",
                tint: .green,
                primary: String(localized: "Weekly digest is on."),
                secondary: nextFireSecondary,
                action: nil
            )
        case .denied:
            statusRow(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                primary: String(localized: "Notifications are off in System Settings."),
                secondary: String(localized: "Re-enable them to receive the weekly digest."),
                action: (
                    title: String(localized: "Open Notifications…"),
                    perform: { SystemSettingsLink.openNotifications() }
                )
            )
        }
    }

    private var nextFireSecondary: String? {
        guard let date = viewModel.nextWeeklyFireDate else { return nil }
        let formatted = DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .short)
        return String(localized: "Next: \(formatted)")
    }

    @ViewBuilder
    private func diagnosticsCard(vm: PreferencesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Send test notification"))
                        .font(.system(size: 13, weight: .medium))
                    Text(String(localized: "Fires a one-off banner in 5 seconds. Useful for verifying delivery without waiting for the scheduled day."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    Task {
                        await vm.sendTestNotification()
                        // Clear the inline result after 8 seconds so the
                        // user can re-fire without state leftover.
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
                    .font(.system(size: 11.5))
                    .foregroundStyle(testResultColor(vm.testNotificationResult))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .vibrancyCard()
    }

    private func testResultText(_ result: PreferencesViewModel.TestNotificationResult) -> String? {
        switch result {
        case .idle:
            return nil
        case .scheduling:
            return String(localized: "Scheduling…")
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
        case .idle, .scheduling, .scheduled:
            return .secondary
        case .notAuthorized, .failed:
            return .orange
        }
    }

    private func statusRow(
        icon: String,
        tint: Color,
        primary: String,
        secondary: String?,
        action: (title: String, perform: () -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(primary)
                    .font(.system(size: 12.5, weight: .medium))
                if let secondary {
                    Text(secondary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let action {
                    Button(action: action.perform) {
                        Text(action.title)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.link)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .vibrancyCard()
    }
}
