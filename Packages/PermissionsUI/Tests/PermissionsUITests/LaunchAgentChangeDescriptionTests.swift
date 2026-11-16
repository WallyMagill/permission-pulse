import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite @MainActor struct LaunchAgentChangeDescriptionTests {
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

    private func flip(_ before: LaunchAgentItem, _ after: LaunchAgentItem) -> ChangeRow.Kind {
        .launchAgentFlipped(DomainChange(before: before, after: after))
    }

    @Test func everyComparedFieldHasAPlainSentence() {
        let base = agent()
        let cases: [(LaunchAgentItem, String)] = [
            (agent(program: "/usr/local/bin/new"), "com.example.helper now runs /usr/local/bin/new"),
            (agent(arguments: ["--quiet"]), "com.example.helper now runs with different arguments"),
            (agent(isDisabled: true), "com.example.helper was disabled"),
            (agent(runAtLoad: false), "com.example.helper starts at login: on → off"),
            (agent(keepAlive: true), "com.example.helper restarts if it quits: off → on"),
            (agent(readable: false), "com.example.helper: details became unreadable"),
        ]
        for (after, expected) in cases {
            #expect(ChangeRow.summary(for: flip(base, after)) == expected)
        }
        #expect(ChangeRow.summary(for: flip(agent(isDisabled: true), base)) == "com.example.helper was enabled")
        #expect(ChangeRow.summary(for: flip(agent(readable: false), base)) == "com.example.helper: details became readable")
    }

    @Test func addedUnreadableDaemonSaysSo() {
        let added = ChangeRow.Kind.launchAgentAdded(agent(
            label: "com.nordvpn.macos.helper", source: .libraryLaunchDaemons, readable: false
        ))
        #expect(ChangeRow.summary(for: added) == "New launch daemon (details unreadable): com.nordvpn.macos.helper")
    }

    @Test func dismissingOneKindOfChangeDoesNotHideAnother() {
        let base = agent()
        let disabled = flip(base, agent(isDisabled: true))
        let loginOff = flip(base, agent(runAtLoad: false))

        #expect(DiffEntryKey.key(for: disabled) != DiffEntryKey.key(for: loginOff))
        #expect(DiffEntryKey.key(for: disabled) == "la-flip|userLaunchAgents|com.example.helper|disabled")
        // A dismissal stored by an earlier version keeps working.
        #expect(DiffEntryKey.lookupKeys(for: loginOff).contains("la-flip|userLaunchAgents|com.example.helper"))
    }
}
