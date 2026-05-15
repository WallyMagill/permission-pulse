import Foundation
import PermissionsCore

// UI-layer grouping of PermissionGrants. Most services produce one display
// row per grant, but Automation grants — which carry a per-target indirect
// object — get bundled by app so the user sees "Raycast (3 targets)" rather
// than three near-identical rows that all live in the same Settings pane.
//
// The underlying PermissionGrant array stays granular so the diff engine
// can still surface per-target add/remove events in the What Changed tab.
enum PermissionsDisplayItem: Identifiable {
    case single(PermissionGrant)
    case automationGroup(AutomationGroup)

    var id: String {
        switch self {
        case .single(let grant):       grant.id
        case .automationGroup(let g):  g.id
        }
    }

    static func make(from grants: [PermissionGrant]) -> [PermissionsDisplayItem] {
        var nonAutomation: [PermissionGrant] = []
        var automationByBundleID: [String: [PermissionGrant]] = [:]
        for grant in grants {
            if grant.service == .automation {
                automationByBundleID[grant.app.bundleID, default: []].append(grant)
            } else {
                nonAutomation.append(grant)
            }
        }

        var items: [PermissionsDisplayItem] = nonAutomation.map(PermissionsDisplayItem.single)
        for (_, group) in automationByBundleID {
            if group.count == 1 {
                items.append(.single(group[0]))
            } else {
                items.append(.automationGroup(AutomationGroup(grants: group)))
            }
        }
        return items.sorted(by: itemSort)
    }

    private static func itemSort(
        _ a: PermissionsDisplayItem,
        _ b: PermissionsDisplayItem
    ) -> Bool {
        let aService = a.serviceRawValue
        let bService = b.serviceRawValue
        if aService != bService { return aService < bService }
        return a.displayName < b.displayName
    }

    fileprivate var serviceRawValue: String {
        switch self {
        case .single(let grant):       grant.service.rawValue
        case .automationGroup(let g):  g.primaryGrant.service.rawValue
        }
    }

    fileprivate var displayName: String {
        switch self {
        case .single(let grant):       grant.app.displayName
        case .automationGroup(let g):  g.app.displayName
        }
    }
}

struct AutomationGroup: Identifiable, Hashable {
    let grants: [PermissionGrant]   // all .automation, same bundleID

    var primaryGrant: PermissionGrant { grants[0] }
    var app: AppIdentity             { primaryGrant.app }
    var targets: [PermissionGrant]   { grants.sorted { $0.lastModified > $1.lastModified } }
    var mostRecentModified: Date     { grants.map(\.lastModified).max() ?? primaryGrant.lastModified }

    var id: String { "automation-group|\(app.bundleID)" }
}
