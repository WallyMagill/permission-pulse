import SwiftUI

/// Opened automatically, once per version, when Full Disk Access is off after
/// it worked before.
public struct FullDiskAccessPromptView: View {
    private let loss: FullDiskAccessLoss
    private let bundlePath: String
    private let recovery: FullDiskAccessRecovery
    private let onClose: () -> Void

    /// `bundlePath` is this copy's path as shown to the user (home as `~`).
    public init(
        loss: FullDiskAccessLoss,
        bundlePath: String,
        recovery: FullDiskAccessRecovery,
        onClose: @escaping () -> Void
    ) {
        self.loss = loss
        self.bundlePath = bundlePath
        self.recovery = recovery
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            Label(title, systemImage: "lock.shield")
                .ppFont(.pageTitle)
            Text(message)
                .ppFont(.body)
                .fixedSize(horizontal: false, vertical: true)
            FullDiskAccessSteps()
            Text(String(localized: "This copy: \(bundlePath)"))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            FullDiskAccessRecoveryStatus(
                recovery: recovery,
                successText: String(localized: "Full Disk Access is back on")
            )
            Spacer(minLength: 0)
            FullDiskAccessRecoveryButtons(recovery: recovery, dismissTitle: String(localized: "Close"), onDismiss: onClose)
        }
        .padding(PPSpacing.xl)
        .frame(width: 480, height: 460)
    }

    private var title: String {
        switch loss {
        case .lostAfterUpdate: String(localized: "Full Disk Access was turned off")
        case .revoked, .firstRun: String(localized: "Full Disk Access is off")
        }
    }

    private var message: String {
        switch loss {
        case .lostAfterUpdate:
            String(localized: "macOS turned off Full Disk Access when Permission Pulse was updated. This happens with every update because the app isn't signed with a paid Apple Developer ID. Your history is safe.")
        case .revoked, .firstRun:
            String(localized: "Full Disk Access is off for Permission Pulse.")
        }
    }
}

private struct FullDiskAccessSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            NumberedStep(number: 1, text: String(localized: "Open System Settings to Privacy & Security → Full Disk Access."))
            NumberedStep(number: 2, text: String(localized: "Turn Permission Pulse on. If it already looks on, switch it off and on again."))
            NumberedStep(number: 3, text: String(localized: "Come back here. Permission Pulse checks again and offers to reopen if macOS needs a restart."))
        }
        .vibrancyCard()
    }
}

/// The loop's status line: waiting, checking, the result.
struct FullDiskAccessRecoveryStatus: View {
    let recovery: FullDiskAccessRecovery
    let successText: String

    var body: some View {
        switch recovery.phase {
        case .idle:
            EmptyView()
        case .waiting:
            statusLabel(String(localized: "Waiting for Full Disk Access to be turned on…"), icon: "hourglass", tint: .secondary)
        case .checking:
            HStack(spacing: PPSpacing.sm) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Checking…")).ppFont(.body)
            }
        case .restored:
            statusLabel(successText, icon: "checkmark.circle.fill", tint: PPColor.success)
        case .stillDenied:
            statusLabel(
                String(localized: "Full Disk Access still looks off. macOS sometimes applies it only after Permission Pulse reopens."),
                icon: "exclamationmark.triangle.fill",
                tint: PPColor.warning
            )
        }
    }

    private func statusLabel(_ text: String, icon: String, tint: Color) -> some View {
        Label {
            Text(text).ppFont(.body).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
        }
    }
}

/// Dismiss, Open System Settings and, when still refused, Reopen.
struct FullDiskAccessRecoveryButtons: View {
    let recovery: FullDiskAccessRecovery
    let dismissTitle: String
    let onDismiss: () -> Void
    var onOpenSettings: () -> Void = {}

    var body: some View {
        HStack {
            Spacer()
            if recovery.phase == .restored {
                Button(dismissTitle) { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(dismissTitle) { onDismiss() }
                openSettingsButton
                if recovery.phase == .stillDenied {
                    Button(String(localized: "Reopen Permission Pulse")) { AppRelauncher.relaunch() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private var openSettingsButton: some View {
        let button = Button(String(localized: "Open System Settings")) {
            SystemSettingsLink.openFullDiskAccess()
            if recovery.phase != .stillDenied { recovery.beginWaiting() }
            onOpenSettings()
        }
        if recovery.phase == .stillDenied {
            button
        } else {
            button
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(recovery.phase == .checking)
        }
    }
}
