import SwiftUI

/// Preferences → Notifications: change alerts, the weekly digest, a test
/// banner, and the shared "notifications are off" hint.
struct NotificationsSettingsTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var vm = viewModel

        Form {
            ChangeAlertsSection()
            DigestScheduleSection()
            if vm.anyNotificationEnabled {
                TestNotificationSection()
            }
            DigestStatusSection()
            if vm.notificationsDenied {
                NotificationsDeniedSection()
            }
        }
        .formStyle(.grouped)
        // Sections appear/disappear from several state sources (the toggles,
        // the async authorization hints, the timed test-result clear) — track
        // the reflow so rows don't pop and snap the form around.
        .animation(reduceMotion ? nil : .default, value: vm.digestEnabled)
        .animation(reduceMotion ? nil : .default, value: vm.changeAlertsEnabled)
        .animation(reduceMotion ? nil : .default, value: vm.authorizationHint)
        .animation(reduceMotion ? nil : .default, value: vm.changeAlertsHint)
        .animation(reduceMotion ? nil : .default, value: vm.testNotificationResult)
        .task {
            await vm.refreshAuthorizationHint()
        }
    }
}

// MARK: - Change alerts

private struct ChangeAlertsSection: View {
    @Environment(PreferencesViewModel.self) private var vm

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { vm.changeAlertsEnabled },
                set: { newValue in
                    vm.changeAlertsEnabled = newValue
                    Task { await vm.handleChangeAlertsToggle(to: newValue) }
                }
            )) {
                VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                    Text(String(localized: "Notify me when something changes"))
                        .ppFont(.body)
                    Text(String(localized: "Checks when your Mac wakes, at the start of each day, and when you open Permission Pulse. Nothing leaves your Mac."))
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(.accentColor)
            if case .failed(let message) = vm.changeAlertsHint {
                NotificationStatusRow(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    primary: String(localized: "Change alerts couldn't be turned on."),
                    secondary: message
                )
            }
        } header: {
            Text(String(localized: "Change Alerts"))
        }
    }
}

// MARK: - Weekly digest

private struct DigestScheduleSection: View {
    @Environment(PreferencesViewModel.self) private var vm

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
        Section {
            digestToggle
            Picker(
                String(localized: "Day"),
                selection: Binding(
                    get: { vm.store.digestWeekday },
                    set: { newValue in
                        vm.store.digestWeekday = newValue
                        vm.scheduleDidChange()
                    }
                )
            ) {
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
                    set: { newValue in
                        vm.store.setDigestTime(newValue)
                        vm.scheduleDidChange()
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .disabled(!vm.digestEnabled)
        } header: {
            Text(String(localized: "Weekly Digest"))
        }
    }

    private var digestToggle: some View {
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
    }
}

private struct DigestStatusSection: View {
    @Environment(PreferencesViewModel.self) private var vm

    var body: some View {
        switch vm.authorizationHint {
        case .notYetRequested, .disabled, .denied:
            EmptyView()
        case .scheduled:
            Section {
                NotificationStatusRow(
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    primary: String(localized: "Weekly digest is on."),
                    secondary: nextFireSecondary
                )
            }
        case .failed(let message):
            Section {
                NotificationStatusRow(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    primary: String(localized: "Weekly digest couldn't be scheduled."),
                    secondary: String(localized: "\(message) Your selected day and time were saved.")
                )
                Button(String(localized: "Retry")) {
                    vm.scheduleDidChange()
                }
            }
        }
    }

    private var nextFireSecondary: String? {
        guard let date = vm.nextWeeklyFireDate else { return nil }
        let formatted = DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .short)
        return String(localized: "Next: \(formatted)")
    }
}

private struct NotificationsDeniedSection: View {
    var body: some View {
        Section {
            NotificationStatusRow(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                primary: String(localized: "Notifications are off in System Settings."),
                secondary: String(localized: "Turn them on for Permission Pulse to receive change alerts and the weekly digest.")
            )
            Button(String(localized: "Open Notifications…")) {
                SystemSettingsLink.openNotifications()
            }
        }
    }
}

// MARK: - Test notification

private struct TestNotificationSection: View {
    @Environment(PreferencesViewModel.self) private var vm
    @State private var clearResultTask: Task<Void, Never>?

    private static let testResultDisplayDuration: Duration = .seconds(8)

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                    Text(String(localized: "Send test notification"))
                        .ppFont(.body)
                        .fontWeight(.medium)
                    Text(String(localized: "Fires a one-off banner in 5 seconds. Useful for checking that notifications reach you."))
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PPSpacing.md)
                sendButton
            }

            if let resultText = testResultText(vm.testNotificationResult) {
                Text(resultText)
                    .ppFont(.metadata)
                    .foregroundStyle(testResultColor(vm.testNotificationResult))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { clearResultTask?.cancel() }
    }

    private var sendButton: some View {
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

// MARK: - Shared row

struct NotificationStatusRow: View {
    let icon: String
    let tint: Color
    let primary: String
    let secondary: String?

    var body: some View {
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
}
