import SwiftUI
import PermissionsCore

struct SchemaMismatchBanner: View {
    let error: ScannerError

    private static let reportURL = URL(
        string: "https://github.com/WallyMagill/permission-pulse/issues/new?labels=schema-mismatch"
    )!

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Unrecognized TCC schema"))
                    .font(.headline)
                Text(bodyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Link(String(localized: "Report"), destination: Self.reportURL)
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var bodyText: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "macOS \(version.majorVersion).\(version.minorVersion)"
        switch error {
        case .schemaMismatch(let detail):
            return String(
                localized: "\(osString) reports a TCC schema this version of Permission Pulse doesn't recognize. \(detail)"
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
