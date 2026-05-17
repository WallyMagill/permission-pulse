import Foundation
import PermissionsCore

// UI-layer grouping of PermissionGrants. Every distinct app collapses to ONE
// display row that lists all of its granted services in the sub-line. The
// underlying grants array stays granular so the detail sheet can render
// per-service grant dates and per-target automation rows.
enum PermissionsDisplayItem: Identifiable {
    case appGroup(app: AppIdentity, grants: [PermissionGrant])

    var id: String {
        switch self {
        case .appGroup(let app, let grants):
            // Empty bundleID would otherwise collapse every unknown app
            // together. Fall back to a per-grant id so each unknown row
            // stays its own item.
            if app.bundleID.isEmpty, let firstID = grants.first?.id {
                return "grant|\(firstID)"
            }
            return "app|\(app.bundleID)"
        }
    }

    var app: AppIdentity {
        switch self {
        case .appGroup(let app, _): return app
        }
    }

    var grants: [PermissionGrant] {
        switch self {
        case .appGroup(_, let grants): return grants
        }
    }

    // De-duplicated services sorted by display name. Automation grants with
    // multiple targets collapse to one "Automation" entry.
    var distinctServices: [PermissionService] {
        var seen = Set<PermissionService>()
        var ordered: [PermissionService] = []
        for grant in grants where seen.insert(grant.service).inserted {
            ordered.append(grant.service)
        }
        return ordered.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var automationGrants: [PermissionGrant] {
        grants.filter { $0.service == .automation }
    }

    // Pick the most recently granted instance of `service`. Used to date the
    // service-pill in the detail sheet — even if a (service, app, target)
    // tuple ends up duplicated for any reason, the user sees the latest.
    func mostRecentGrant(for service: PermissionService) -> PermissionGrant? {
        grants
            .filter { $0.service == service }
            .max { $0.lastModified < $1.lastModified }
    }

    static func make(from grants: [PermissionGrant]) -> [PermissionsDisplayItem] {
        var groups: [String: [PermissionGrant]] = [:]
        var standalone: [PermissionGrant] = []

        for grant in grants {
            if grant.app.bundleID.isEmpty {
                standalone.append(grant)
            } else {
                groups[grant.app.bundleID, default: []].append(grant)
            }
        }

        var items: [PermissionsDisplayItem] = groups.values.map { bucket in
            let app = bucket.first!.app
            return .appGroup(app: app, grants: bucket)
        }
        for grant in standalone {
            items.append(.appGroup(app: grant.app, grants: [grant]))
        }

        return items.sorted { a, b in
            a.app.displayName.localizedCaseInsensitiveCompare(b.app.displayName) == .orderedAscending
        }
    }
}
