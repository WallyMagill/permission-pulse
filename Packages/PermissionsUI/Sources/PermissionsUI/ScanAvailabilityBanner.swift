import SwiftUI
import PermissionsCore

public struct ScanAvailabilityBanner: View {
    public let availability: ScanAvailability
    public let domainName: String

    public init(availability: ScanAvailability, domainName: String) {
        self.availability = availability
        self.domainName = domainName
    }

    public var body: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                Text(headline)
                    .ppFont(.cardHeader)
                Text(detailText)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                if case .degraded(_, let warnings) = availability {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                        Text(Self.warningText(for: warning))
                            .ppFont(.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(PPSpacing.md)
        .vibrancyCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    var accessibilityText: String {
        switch availability {
        case .never:
            return String(localized: "\(domainName) not yet scanned. No scan results are available yet.")
        case .complete:
            return String(localized: "\(domainName) scan complete. \(detailText)")
        case .degraded(_, let warnings):
            let warningText = warnings.map(Self.warningText).joined(separator: " ")
            return String(localized: "\(domainName) scan degraded. \(detailText) \(warningText)")
        case .failed(let lastSuccessful, _):
            if lastSuccessful != nil {
                return String(localized: "\(domainName) scan failed. Stale data from the last known successful scan. \(detailText)")
            }
            return String(localized: "\(domainName) scan failed. No successful scan is available. \(detailText)")
        }
    }

    static func warningText(for warning: ScannerWarning) -> String {
        switch warning.source {
        case .userTCCDatabase:
            String(localized: "User permission records were unavailable.")
        case .systemTCCDatabase:
            String(localized: "System permission records were unavailable.")
        case .userLaunchAgents:
            String(localized: "User Launch Agents were unavailable.")
        case .libraryLaunchAgents:
            String(localized: "System Launch Agents were unavailable.")
        case .libraryLaunchDaemons:
            String(localized: "System Launch Daemons were unavailable.")
        case .entries:
            if let count = warning.omittedCount {
                count == 1
                    ? String(localized: "1 malformed or unreadable entry was omitted.")
                    : String(localized: "\(count) malformed or unreadable entries were omitted.")
            } else {
                String(localized: "Some malformed or unreadable entries were omitted.")
            }
        }
    }

    var headline: String {
        switch availability {
        case .never: String(localized: "Not yet scanned")
        case .complete: String(localized: "Complete data")
        case .degraded: String(localized: "Degraded data")
        case .failed(let lastSuccessful, _):
            lastSuccessful == nil
                ? String(localized: "Scan failed")
                : String(localized: "Stale data")
        }
    }

    private var detailText: String {
        switch availability {
        case .never:
            return String(localized: "No scan results are available yet.")
        case .complete(let lastUpdated):
            return String(localized: "Updated \(formatted(lastUpdated)).")
        case .degraded(let lastUpdated, _):
            return String(localized: "Some sources could not be read. Updated \(formatted(lastUpdated)).")
        case .failed(let lastSuccessful, let error):
            if let lastSuccessful {
                return String(localized: "Showing last-known data from \(formatted(lastSuccessful)). \(error.localizedDescription)")
            }
            return String(localized: "No successful scan is available. \(error.localizedDescription)")
        }
    }

    private var symbolName: String {
        switch availability {
        case .never: "clock"
        case .complete: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .failed: "clock.badge.exclamationmark.fill"
        }
    }

    private var symbolColor: Color {
        switch availability {
        case .never: .secondary
        case .complete: PPColor.success
        case .degraded, .failed: PPColor.warning
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
