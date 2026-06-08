import SwiftUI

/// Shown in an inventory page while the initial scan is still running and there
/// is nothing to display yet. (U1)
struct ScanningPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "Scanning…"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Scanning"))
    }
}
