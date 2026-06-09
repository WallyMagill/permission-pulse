// AppKit: NSSavePanel is the only way to let the user choose an export
// location; writing there is explicitly allowed by the read-only hard rules.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PermissionsCore

struct ExportToolbarMenu: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Menu {
            Button(String(localized: "Export as JSON…")) { export(.json) }
            Button(String(localized: "Export as Markdown…")) { export(.markdown) }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .help(String(localized: "Export current state"))
        .accessibilityLabel(String(localized: "Export"))
    }

    private enum Format { case json, markdown }

    private func export(_ format: Format) {
        let report = PermissionsExport.report(
            grants: viewModel.grants,
            launchAgents: viewModel.launchAgents,
            btmItems: viewModel.btmItems,
            staleApps: viewModel.staleApps,
            generatedAt: Date()
        )
        do {
            let data: Data
            let ext: String
            let contentType: UTType
            switch format {
            case .json:
                data = try PermissionsExport.makeJSON(report: report)
                ext = "json"; contentType = .json
            case .markdown:
                data = Data(PermissionsExport.makeMarkdown(report: report).utf8)
                ext = "md"; contentType = UTType(filenameExtension: "md") ?? .plainText
            }
            try ExportSaver.run(data: data, suggestedName: "PermissionPulse-Export.\(ext)", contentType: contentType)
        } catch {
            // AppKit: NSAlert is the idiomatic one-shot modal for surfacing a
            // failed encode/write so the export never fails silently.
            NSAlert(error: error).runModal()
        }
    }
}

private enum ExportSaver {
    // AppKit: NSSavePanel + Data.write to the user-chosen URL. A cancel is not
    // an error (returns without writing); a real write failure propagates.
    static func run(data: Data, suggestedName: String, contentType: UTType) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
    }
}
