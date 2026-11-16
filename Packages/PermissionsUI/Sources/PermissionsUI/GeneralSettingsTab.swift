import ServiceManagement
import SwiftUI

/// Preferences → General: launch at login and About.
struct GeneralSettingsTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel

    var body: some View {
        Form {
            LaunchAtLoginSection()
            AboutSection()
        }
        .formStyle(.grouped)
        .onAppear { viewModel.refreshLaunchAtLoginStatus() }
    }
}

private struct LaunchAtLoginSection: View {
    @Environment(PreferencesViewModel.self) private var viewModel

    var body: some View {
        Section {
            Toggle(
                String(localized: "Launch at login"),
                isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin($0) }
                )
            )
            Text(String(localized: "Permission Pulse starts in the menu bar when you log in."))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
            if viewModel.launchAtLoginStatus == .requiresApproval {
                approvalRow
            }
            if let error = viewModel.launchAtLoginError {
                Text(error)
                    .ppFont(.metadata)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var approvalRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "Approve Permission Pulse in System Settings → Login Items"))
                .ppFont(.metadata)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: PPSpacing.sm)
            Button(String(localized: "Open Login Items…")) {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}

private struct AboutSection: View {
    @Environment(\.openURL) private var openURL
    private let version = AppVersion.running

    var body: some View {
        Section {
            LabeledContent(String(localized: "Permission Pulse")) {
                Text(version.displayText)
                    .textSelection(.enabled)
            }
            HStack {
                Button(String(localized: "Check for Updates…")) {
                    openURL(ProjectLinks.releases)
                }
                Spacer()
                Link(String(localized: "Source on GitHub"), destination: ProjectLinks.repository)
            }
            Text(String(localized: "MIT License"))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "About"))
        }
    }
}
