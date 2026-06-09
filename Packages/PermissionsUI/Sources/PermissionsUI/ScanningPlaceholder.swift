import SwiftUI

/// Shown in an inventory page while the initial scan is still running and there
/// is nothing to display yet. (U1)
struct ScanningPlaceholder: View {
    var body: some View {
        VStack(spacing: PPSpacing.md) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "Scanning…"))
                .ppFont(.cardHeader)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PPSpacing.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Scanning"))
    }
}
