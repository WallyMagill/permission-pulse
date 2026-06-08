import SwiftUI

public struct WelcomeWindowView: View {
    private let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(String(localized: "Welcome to Permission Pulse"))
                .font(.title2.bold())

            Text(String(
                localized: "Permission Pulse helps you audit which apps have access to TCC permissions like Camera, Microphone, Accessibility, and Full Disk Access on your Mac."
            ))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                bulletRow(icon: "lock.shield", text: String(localized: "Reads TCC databases read-only"))
                bulletRow(icon: "hand.raised", text: String(localized: "Never modifies any file"))
                bulletRow(icon: "wifi.slash", text: String(localized: "No network requests, no telemetry"))
            }

            Spacer()

            Text(String(localized: "You'll need to relaunch Permission Pulse after granting access."))
                .font(.footnote)
                .foregroundStyle(.tertiary)

            HStack {
                Button(String(localized: "Skip for now")) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Grant Full Disk Access")) {
                    SystemSettingsLink.openFullDiskAccess()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 480, height: 420)
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
        }
    }
}
