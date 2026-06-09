import SwiftUI

public struct WelcomeWindowView: View {
    private let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: PPSpacing.xl) {
            Image(systemName: "shield.lefthalf.filled")
                // Decorative hero icon in a fixed visual tile — KEEP fixed size (Rule 1)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(String(localized: "Welcome to Permission Pulse"))
                .ppFont(.pageTitle)
                .fontWeight(.bold)

            Text(String(
                localized: "Permission Pulse helps you audit which apps have access to TCC permissions like Camera, Microphone, Accessibility, and Full Disk Access on your Mac."
            ))
                .ppFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                bulletRow(icon: "lock.shield", text: String(localized: "Reads TCC databases read-only"))
                bulletRow(icon: "hand.raised", text: String(localized: "Never modifies any file"))
                bulletRow(icon: "wifi.slash", text: String(localized: "No network requests, no telemetry"))
            }

            Spacer()

            Text(String(localized: "You'll need to relaunch Permission Pulse after granting access."))
                .ppFont(.metadata)
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
        .padding(PPSpacing.xxl)
        .frame(width: 480, height: 420)
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(spacing: PPSpacing.sm) {
            Image(systemName: icon)
                // Decorative icon in fixed 16-pt-wide frame — KEEP fixed sizing (Rule 1)
                .frame(width: 16)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .ppFont(.body)
        }
    }
}
