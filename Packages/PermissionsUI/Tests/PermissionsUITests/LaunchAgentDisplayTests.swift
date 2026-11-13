import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite @MainActor struct LaunchAgentDisplayTests {
    private func agent(
        label: String = "com.example.helper",
        source: LaunchAgentItem.SourceDirectory = .userLaunchAgents,
        program: String? = "/Applications/Example.app/Contents/MacOS/helper",
        arguments: [String] = [],
        runAtLoad: Bool = true,
        keepAlive: Bool = false,
        isDisabled: Bool = false,
        readable: Bool = true,
        fileName: String? = nil
    ) -> LaunchAgentItem {
        LaunchAgentItem(
            label: label,
            sourceDirectory: source,
            programPath: readable ? program : nil,
            programArguments: readable ? arguments : [],
            runAtLoad: readable && runAtLoad,
            keepAlive: readable && keepAlive,
            isDisabled: isDisabled,
            detailsReadable: readable,
            fileName: fileName
        )
    }

    // MARK: - Rows, search, reveal

    @Test func rowSubtitleNamesProgramAndScope() {
        #expect(LaunchAgentDisplay.secondaryLine(agent()) == "helper · User")
        #expect(LaunchAgentDisplay.secondaryLine(agent(
            source: .libraryLaunchAgents, program: nil, arguments: ["/usr/bin/tool", "-x"]
        )) == "tool · All users")
        #expect(LaunchAgentDisplay.secondaryLine(agent(
            source: .libraryLaunchDaemons, readable: false
        )) == "Details unreadable · System daemon")
    }

    @Test func searchMatchesArgumentsAndFileName() {
        let byArgument = agent(label: "com.example.a", arguments: ["/bin/sh", "--watch-folder"])
        let byFile = agent(label: "com.example.b", fileName: "Vendor Updater.plist")
        let items = [byArgument, byFile]

        #expect(LaunchAgentDisplay.filtered(items, searchText: "watch-folder") == [byArgument])
        #expect(LaunchAgentDisplay.filtered(items, searchText: "vendor updater") == [byFile])
        #expect(LaunchAgentDisplay.filtered(items, searchText: "  ") == items)
    }

    @Test func revealSelectsTheRecordedFileNameNotALabelGuess() {
        let item = agent(fileName: "Renamed Helper.plist")
        let target = LaunchAgentDisplay.revealTarget(for: item) { $0.hasSuffix("/Renamed Helper.plist") }
        #expect(target.lastPathComponent == "Renamed Helper.plist")

        let missing = LaunchAgentDisplay.revealTarget(for: item) { _ in false }
        #expect(missing.hasDirectoryPath)
        #expect(missing.lastPathComponent == "LaunchAgents")
    }

    @Test func inspectorShowsUnknownForUnreadableDetails() {
        let rows = LaunchAgentInspector.propertyRows(for: agent(isDisabled: true, readable: false))
        let values = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.value) })

        for key in ["Program", "Arguments", "Run at load", "Keep alive"] {
            #expect(values[key] == "Unknown (file not readable)")
        }
        #expect(values["Disabled"] == "Yes")
    }

    // MARK: - Missing program

    private func check(
        absent: Set<String>,
        unknown: Set<String> = [],
        unlistable: Set<String> = []
    ) -> MissingProgramCheck {
        MissingProgramCheck(
            entryState: { path in
                if unknown.contains(path) { return .unknown }
                return absent.contains(path) ? .absent : .present
            },
            isDirectoryListable: { !unlistable.contains($0) }
        )
    }

    @Test func missingProgramFlagsOnlyObservableAbsence() {
        let program = "/Applications/Example.app/Contents/MacOS/helper"
        let appGone: Set<String> = [
            program, "/Applications/Example.app/Contents/MacOS",
            "/Applications/Example.app/Contents", "/Applications/Example.app",
        ]
        let item = agent(program: program)

        #expect(check(absent: appGone).isProgramMissing(item))
        #expect(!check(absent: []).isProgramMissing(item))
        #expect(!check(absent: appGone, unlistable: ["/Applications"]).isProgramMissing(item))
        #expect(!check(absent: [program], unknown: ["/Applications/Example.app/Contents/MacOS"]).isProgramMissing(item))
    }

    @Test func missingProgramNeverFlagsWhenUnsure() {
        let gone = check(absent: ["helper", "/Volumes/Backup", "/Volumes/Backup/bin", "/Volumes/Backup/bin/tool"])

        #expect(!gone.isProgramMissing(agent(program: "helper")))
        #expect(!gone.isProgramMissing(agent(program: "/Volumes/Backup/bin/tool")))
        #expect(!gone.isProgramMissing(agent(readable: false)))
    }
}
