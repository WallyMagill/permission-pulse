import AppKit // AppKit: NSPasteboard for Copy Diagnostics; SwiftUI has no clipboard writer.
import SwiftUI

/// Preferences window — native macOS TabView with four tabs:
/// General / Scanning / Notifications / Data.
public struct PreferencesWindowView: View {
    @Environment(PreferencesViewModel.self) private var viewModel
    private let onResetAllData: (() -> Void)?
    private let scanInProgress: () -> Bool
    private let makeDiagnostics: (() async -> String)?
    private let onRestoreSkippedStaleApps: (() -> Void)?

    public init(
        onResetAllData: (() -> Void)? = nil,
        scanInProgress: @escaping () -> Bool = { false },
        makeDiagnostics: (() async -> String)? = nil,
        onRestoreSkippedStaleApps: (() -> Void)? = nil
    ) {
        self.onResetAllData = onResetAllData
        self.scanInProgress = scanInProgress
        self.makeDiagnostics = makeDiagnostics
        self.onRestoreSkippedStaleApps = onRestoreSkippedStaleApps
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            ScanningSettingsTab()
                .tabItem { Label(String(localized: "Scanning"), systemImage: "clock.arrow.circlepath") }
            NotificationsSettingsTab()
                .tabItem { Label(String(localized: "Notifications"), systemImage: "bell.badge") }
            DataSettingsTab(
                onResetAllData: onResetAllData,
                scanInProgress: scanInProgress,
                makeDiagnostics: makeDiagnostics,
                onRestoreSkippedStaleApps: onRestoreSkippedStaleApps
            )
                .tabItem { Label(String(localized: "Data"), systemImage: "externaldrive") }
        }
        .frame(width: 560, height: 440)
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
    let makeDiagnostics: (() async -> String)?
    let onRestoreSkippedStaleApps: (() -> Void)?
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Export current state")) {
                    ExportToolbarMenu()
                }
            }
            HiddenItemsSection(onRestoreSkippedStaleApps: onRestoreSkippedStaleApps)
            if let makeDiagnostics {
                CopyDiagnosticsSection(makeDiagnostics: makeDiagnostics)
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

/// Brings back Recent Changes rows the user dismissed or snoozed and apps
/// they skipped in Stale Apps, without resetting everything else.
private struct HiddenItemsSection: View {
    let onRestoreSkippedStaleApps: (() -> Void)?
    @Environment(DismissedDiffEntryStore.self) private var dismissedChanges
    @Environment(DismissedStaleAppStore.self) private var skippedApps

    var body: some View {
        let changeCount = dismissedChanges.activeCount(asOf: Date())
        let skippedCount = skippedApps.allStableKeys().count
        Section {
            LabeledContent(String(localized: "Dismissed changes (\(changeCount))")) {
                Button(String(localized: "Restore All")) { dismissedChanges.removeAll() }
                    .disabled(changeCount == 0)
            }
            LabeledContent(String(localized: "Skipped stale apps (\(skippedCount))")) {
                Button(String(localized: "Restore All")) {
                    if let onRestoreSkippedStaleApps {
                        onRestoreSkippedStaleApps()
                    } else {
                        skippedApps.removeAll()
                    }
                }
                .disabled(skippedCount == 0)
            }
            Text(String(localized: "Dismissed and snoozed changes return to Recent Changes; skipped apps return to Stale Apps if they are still unused."))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CopyDiagnosticsSection: View {
    let makeDiagnostics: () async -> String
    @State private var copied = false

    var body: some View {
        Section {
            HStack {
                Button(String(localized: "Copy Diagnostics")) {
                    Task {
                        let text = await makeDiagnostics()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                    }
                }
                if copied {
                    Text(String(localized: "Copied to the clipboard."))
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            Text(String(localized: "Copies the app's version, scan status and settings as plain text for a bug report. It includes no app names, identifiers or file paths other than Permission Pulse's own."))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
