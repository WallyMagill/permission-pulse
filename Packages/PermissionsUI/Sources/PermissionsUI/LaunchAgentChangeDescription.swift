import Foundation
import PermissionsCore
import PermissionsStore

/// Plain-language sentences for every launch-agent field the diff compares,
/// plus a stable token per change so dismissing one kind of change does not
/// hide a different later one.
enum LaunchAgentChangeDescription {
    struct FieldChange: Equatable {
        let token: String
        let sentence: String
    }

    static func summary(_ change: DomainChange<LaunchAgentItem>) -> String {
        let sentences = fieldChanges(change).map(\.sentence)
        guard !sentences.isEmpty else {
            return String(localized: "Modified: \(change.after.label)")
        }
        return sentences.joined(separator: "; ")
    }

    static func dismissalToken(_ change: DomainChange<LaunchAgentItem>) -> String {
        fieldChanges(change).map(\.token).joined(separator: ",")
    }

    static func addedSummary(_ item: LaunchAgentItem) -> String {
        guard !item.detailsReadable else {
            return String(localized: "New launch agent: \(item.label)")
        }
        return item.sourceDirectory == .libraryLaunchDaemons
            ? String(localized: "New launch daemon (details unreadable): \(item.label)")
            : String(localized: "New launch agent (details unreadable): \(item.label)")
    }

    static func fieldChanges(_ change: DomainChange<LaunchAgentItem>) -> [FieldChange] {
        let before = change.before
        let after = change.after
        var changes: [FieldChange] = []
        if before.detailsReadable != after.detailsReadable {
            changes.append(readabilityChange(after))
        } else if after.detailsReadable {
            changes += programChanges(before, after)
            changes += flagChanges(before, after)
        }
        if before.isDisabled != after.isDisabled {
            changes.append(after.isDisabled
                ? FieldChange(token: "disabled", sentence: String(localized: "\(after.label) was disabled"))
                : FieldChange(token: "enabled", sentence: String(localized: "\(after.label) was enabled")))
        }
        return changes
    }

    private static func readabilityChange(_ after: LaunchAgentItem) -> FieldChange {
        after.detailsReadable
            ? FieldChange(token: "readable", sentence: String(localized: "\(after.label): details became readable"))
            : FieldChange(token: "unreadable", sentence: String(localized: "\(after.label): details became unreadable"))
    }

    private static func programChanges(_ before: LaunchAgentItem, _ after: LaunchAgentItem) -> [FieldChange] {
        if before.effectiveProgram != after.effectiveProgram {
            let sentence = after.effectiveProgram.map {
                String(localized: "\(after.label) now runs \($0)")
            } ?? String(localized: "\(after.label) no longer names a program")
            return [FieldChange(token: "program", sentence: sentence)]
        }
        if before.programPath != after.programPath || before.programArguments != after.programArguments {
            return [FieldChange(
                token: "arguments",
                sentence: String(localized: "\(after.label) now runs with different arguments")
            )]
        }
        return []
    }

    private static func flagChanges(_ before: LaunchAgentItem, _ after: LaunchAgentItem) -> [FieldChange] {
        var changes: [FieldChange] = []
        if before.runAtLoad != after.runAtLoad {
            let transition = onOff(before.runAtLoad, after.runAtLoad)
            changes.append(FieldChange(
                token: after.runAtLoad ? "runAtLoad-on" : "runAtLoad-off",
                sentence: String(localized: "\(after.label) starts at login: \(transition)")
            ))
        }
        if before.keepAlive != after.keepAlive {
            let transition = onOff(before.keepAlive, after.keepAlive)
            changes.append(FieldChange(
                token: after.keepAlive ? "keepAlive-on" : "keepAlive-off",
                sentence: String(localized: "\(after.label) restarts if it quits: \(transition)")
            ))
        }
        return changes
    }

    private static func onOff(_ from: Bool, _ to: Bool) -> String {
        let fromLabel = from ? String(localized: "on") : String(localized: "off")
        let toLabel = to ? String(localized: "on") : String(localized: "off")
        return "\(fromLabel) → \(toLabel)"
    }
}
