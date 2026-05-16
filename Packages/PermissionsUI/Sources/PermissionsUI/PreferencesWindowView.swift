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

// MARK: - Notifications tab (placeholder — fleshed out in a later commit)

private struct NotificationsPreferencesTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        Form {
            Section {
                Toggle(isOn: $vm.digestEnabled) {
                    Text(String(localized: "Send weekly digest"))
                }
                Text(String(localized: "Weekly notifications are wired in a later commit."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Weekly Digest"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
