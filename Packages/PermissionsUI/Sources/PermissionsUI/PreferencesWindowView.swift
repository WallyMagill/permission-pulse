import SwiftUI

public struct PreferencesWindowView: View {
    @Environment(PreferencesViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    private let onResetAllData: (() -> Void)?

    public init(onResetAllData: (() -> Void)? = nil) {
        self.onResetAllData = onResetAllData
    }

    public var body: some View {
        TabView {
            SnapshotsPreferencesTab(onResetAllData: onResetAllData)
                .tabItem {
                    Label(String(localized: "Snapshots"), systemImage: "clock")
                }

            NotificationsPreferencesTab()
                .tabItem {
                    Label(String(localized: "Notifications"), systemImage: "bell")
                }
        }
        .frame(width: 520, height: 360)
        .navigationTitle(String(localized: "Preferences"))
    }
}

// MARK: - Snapshots tab

private struct SnapshotsPreferencesTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel
    private let onResetAllData: (() -> Void)?

    init(onResetAllData: (() -> Void)? = nil) {
        self.onResetAllData = onResetAllData
    }

    var body: some View {
        @Bindable var vm = viewModel

        Form {
            Section {
                LabeledContent {
                    Text(daysLabel(viewModel.store.snapshotRetentionDays))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Text(String(localized: "Keep snapshots for"))
                }
                Slider(
                    value: $vm.snapshotRetentionDaysDouble,
                    in: Double(PreferencesStore.snapshotRetentionDaysRange.lowerBound)
                        ... Double(PreferencesStore.snapshotRetentionDaysRange.upperBound),
                    step: 1
                )
                Text(String(localized: "Older snapshots are pruned automatically on the next scan after a change."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Snapshot Retention"))
            }

            Section {
                LabeledContent {
                    Text(daysLabel(viewModel.store.staleThresholdDays))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Text(String(localized: "Flag apps unused for"))
                }
                Slider(
                    value: $vm.staleThresholdDaysDouble,
                    in: Double(PreferencesStore.staleThresholdDaysRange.lowerBound)
                        ... Double(PreferencesStore.staleThresholdDaysRange.upperBound),
                    step: 1
                )
                Text(String(localized: "Apps that haven't launched in this many days appear in the Stale Apps tab."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Stale Apps"))
            }

            Section {
                Button(role: .destructive) {
                    onResetAllData?()
                } label: {
                    Text(String(localized: "Reset All Data…"))
                }
                .disabled(onResetAllData == nil)
                Text(String(localized: "Deletes all saved snapshots, dismissed items, and preferences. Permission Pulse will rescan immediately."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Reset"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func daysLabel(_ days: Int) -> String {
        String(localized: "\(days) days")
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

        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { vm.digestEnabled },
                    set: { newValue in
                        Task { await vm.handleDigestToggle(to: newValue) }
                    }
                )) {
                    Text(String(localized: "Send weekly digest"))
                }

                Picker(selection: Binding(
                    get: { vm.store.digestWeekday },
                    set: { vm.store.digestWeekday = $0 }
                )) {
                    ForEach(Self.weekdayLabels, id: \.value) { entry in
                        Text(entry.label).tag(entry.value)
                    }
                } label: {
                    Text(String(localized: "Day"))
                }
                .disabled(!vm.digestEnabled)

                DatePicker(
                    String(localized: "Time"),
                    selection: Binding(
                        get: { vm.store.digestTime() },
                        set: { vm.store.setDigestTime($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!vm.digestEnabled)

                hintLabel
            } header: {
                Text(String(localized: "Weekly Digest"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await vm.refreshAuthorizationHint()
        }
    }

    @ViewBuilder
    private var hintLabel: some View {
        switch viewModel.authorizationHint {
        case .notYetRequested:
            Text(String(localized: "Flip the toggle on to enable notifications. macOS will ask for permission."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .scheduled:
            Text(String(localized: "Weekly digest is on."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .denied:
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Notifications are off in System Settings."))
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button {
                    SystemSettingsLink.openNotifications()
                } label: {
                    Text(String(localized: "Open Notifications…"))
                }
                .buttonStyle(.link)
            }
        case .disabled:
            EmptyView()
        }
    }
}
