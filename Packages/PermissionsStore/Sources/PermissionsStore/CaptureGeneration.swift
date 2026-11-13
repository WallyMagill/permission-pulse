import PermissionsCore

/// Which capture rules wrote a snapshot, stored in `snapshots.capture_generation`.
///
/// Generation 1 is every snapshot written before v0.7.2. Generation 2 added
/// three facts the older rules never captured: Remote Desktop and Endpoint
/// Security grants, launchd's disabled-override database, and the string
/// elements of a `ProgramArguments` array that also holds other types (the
/// old decoder stored `[]`). A diff between snapshots of different
/// generations ignores those facts, so an upgrade does not show pre-existing
/// state as fresh changes.
public enum CaptureGeneration {
    public static let current = 2

    static let servicesAddedInGeneration2: Set<PermissionService> = [.remoteDesktop, .endpointSecurity]

    /// True when exactly one endpoint predates generation 2.
    static func spansGeneration2(_ lhs: Int, _ rhs: Int) -> Bool {
        min(lhs, rhs) < 2 && max(lhs, rhs) >= 2
    }
}
