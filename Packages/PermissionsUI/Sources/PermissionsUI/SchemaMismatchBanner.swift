import SwiftUI
import PermissionsCore

struct SchemaMismatchBanner: View {
    let error: ScannerError
    let domain: ScannerDomain

    init(error: ScannerError, domain: ScannerDomain = .tcc) {
        self.error = error
        self.domain = domain
    }

    private static let reportURL = URL(
        string: "https://github.com/WallyMagill/permission-pulse/issues/new?labels=schema-mismatch"
    )!

    var body: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(PPColor.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                Text(headline)
                    .ppFont(.cardHeader)
                Text(bodyText)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Link(String(localized: "Report"), destination: Self.reportURL)
                .buttonStyle(.borderless)
        }
        .padding(PPSpacing.md)
        .vibrancyCard()
    }

    private var headline: String {
        switch domain {
        case .tcc: String(localized: "Unrecognized TCC schema")
        case .btm: String(localized: "Unrecognized BTM schema")
        }
    }

    private var bodyText: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "macOS \(version.majorVersion).\(version.minorVersion)"
        let label = domain == .tcc ? "TCC" : "BTM"
        switch error {
        case .schemaMismatch(let detail):
            return String(
                localized: "\(osString) reports a \(label) schema this version of Permission Pulse doesn't recognize. \(detail)"
            )
        case .unsupportedOnThisOS(let detail):
            return String(
                localized: "\(osString) — \(detail)"
            )
        default:
            return ""
        }
    }
}
