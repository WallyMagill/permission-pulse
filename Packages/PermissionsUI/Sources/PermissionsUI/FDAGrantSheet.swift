import SwiftUI

public struct FDAGrantSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Grant Full Disk Access"))
                        .ppFont(.pageTitle)
                    Text(String(localized: "Permission Pulse needs read access to macOS's permission databases."))
                        .ppFont(.secondary)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(String(localized: "Without Full Disk Access, the Permissions and Background Items sections are empty. Permission Pulse opens these databases read-only and never modifies them."))
                .ppFont(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                stepRow(number: 1, text: String(localized: "Click Open System Settings below."))
                stepRow(number: 2, text: String(localized: "Toggle Permission Pulse on in the Full Disk Access list."))
                stepRow(number: 3, text: String(localized: "Quit Permission Pulse and reopen it."))
            }
            .padding(PPSpacing.md)
            .vibrancyCard(cornerRadius: PPRadius.small)

            Text(String(localized: "Permission Pulse never sends data over the network. Source is open on GitHub."))
                .ppFont(.metadata)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "Open System Settings")) {
                    SystemSettingsLink.openFullDiskAccess()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(Font.system(.body).monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Text(text)
                .ppFont(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    FDAGrantSheet()
}
