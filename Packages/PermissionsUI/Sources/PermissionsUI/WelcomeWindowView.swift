import SwiftUI

public struct WelcomeWindowView: View {
    private let onDismiss: () -> Void
    @State private var step: Step = .features

    private enum Step { case features, fullDiskAccess }

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .features: featuresStep
            case .fullDiskAccess: fdaStep
            }
        }
        .padding(PPSpacing.xl)
        .frame(width: 480, height: 440)
    }

    private var featuresStep: some View {
        VStack(spacing: PPSpacing.lg) {
            Image(systemName: "shield.lefthalf.filled")
                // Decorative hero icon — keep fixed size (rule 1)
                .font(.system(size: 52))
                .foregroundStyle(PPColor.brandGradient)
                .accessibilityHidden(true)
            Text(String(localized: "Welcome to Permission Pulse"))
                .ppFont(.pageTitle)
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                FeatureRow(
                    symbol: "lock.shield",
                    title: String(localized: "Read-only by design"),
                    detail: String(localized: "Inspects permissions, launch agents, and background items. Never changes anything.")
                )
                FeatureRow(
                    symbol: "clock.arrow.circlepath",
                    title: String(localized: "Daily change tracking"),
                    detail: String(localized: "A snapshot a day — see exactly what appeared, changed, or disappeared.")
                )
                FeatureRow(
                    symbol: "hourglass",
                    title: String(localized: "Stale permission alerts"),
                    detail: String(localized: "Flags apps holding permissions you haven't used in months.")
                )
                FeatureRow(
                    symbol: "wifi.slash",
                    title: String(localized: "No network, no analytics"),
                    detail: String(localized: "Everything stays on this Mac. Open source, MIT licensed.")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(String(localized: "Continue")) { step = .fullDiskAccess }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var fdaStep: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            Label(String(localized: "One permission to ask for"), systemImage: "lock.shield")
                .ppFont(.pageTitle)
            Text(String(localized: "Reading the system's permission records (TCC) requires Full Disk Access. Permission Pulse only ever reads — it cannot change permissions, and it never writes outside its own data folder."))
                .ppFont(.body)
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                NumberedStep(number: 1, text: String(localized: "Click Open System Settings below."))
                NumberedStep(number: 2, text: String(localized: "Turn on Permission Pulse under Full Disk Access."))
                NumberedStep(number: 3, text: String(localized: "Quit and reopen Permission Pulse."))
            }
            .vibrancyCard()
            Text(String(localized: "You can skip this — everything except permission scanning still works."))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(String(localized: "Skip for Now")) { onDismiss() }
                Button(String(localized: "Open System Settings")) {
                    SystemSettingsLink.openFullDiskAccess()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            Image(systemName: symbol)
                // Decorative feature glyph — keep fixed size (rule 1)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(title).ppFont(.cardHeader)
                Text(detail)
                    .ppFont(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NumberedStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PPSpacing.sm) {
            Text("\(number)")
                .ppFont(.badge)
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            Text(text).ppFont(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Step \(number): \(text)"))
    }
}
