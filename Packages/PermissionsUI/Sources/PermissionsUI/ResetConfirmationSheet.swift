import SwiftUI

/// Destructive confirmation before wiping snapshots, dismissals, and
/// preferences. Sized to match the v0.4.1 FDA grant sheet visual language.
public struct ResetConfirmationSheet: View {
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    public init(
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Reset Permission Pulse?"))
                        .ppFont(.cardHeader)
                    Text(String(localized: "This deletes all saved snapshots, dismissed items, snoozes, and preferences. Permission Pulse will rescan immediately."))
                        .ppFont(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "This cannot be undone."))
                        .ppFont(.body)
                        .foregroundStyle(.primary)
                }
            }

            HStack {
                Spacer()
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Text(String(localized: "Cancel"))
                }
                .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    Text(String(localized: "Reset"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
