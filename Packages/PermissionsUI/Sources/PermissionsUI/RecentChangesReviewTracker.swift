import PermissionsCore

/// The newest snapshot whose since-last-review changes were on screen while
/// the detail window was in front. Leaving Recent Changes marks that one
/// reviewed, never a newer snapshot the user did not see: one that arrived
/// while the window was behind other apps, while "Last 7 days" was showing,
/// or before its diff had rendered.
struct RecentChangesReviewTracker: Equatable, Sendable {
    private(set) var seenSnapshotID: SnapshotID?

    /// Call whenever the page, window focus, picker, or rendered diff changes.
    /// `displayedSnapshotID` is the snapshot the since-last-review diff on
    /// screen ends at.
    mutating func observe(
        showingRecentChanges: Bool,
        inFront: Bool,
        window: RecentChangesWindow,
        displayedSnapshotID: SnapshotID?
    ) {
        guard showingRecentChanges, inFront, window == .sinceLastReview,
              let displayedSnapshotID else { return }
        if let seenSnapshotID, seenSnapshotID.rawValue >= displayedSnapshotID.rawValue { return }
        seenSnapshotID = displayedSnapshotID
    }

    /// Snapshot IDs restart at 1 after Reset All Data, so a seen ID past the
    /// latest one belongs to deleted history and would block every newer one.
    mutating func latestSnapshotChanged(to latest: SnapshotID?) {
        guard let seenSnapshotID else { return }
        if latest.map({ $0.rawValue < seenSnapshotID.rawValue }) ?? true {
            self.seenSnapshotID = nil
        }
    }

    /// The snapshot to mark reviewed on leaving, if any; tracking starts over.
    mutating func leave() -> SnapshotID? {
        defer { seenSnapshotID = nil }
        return seenSnapshotID
    }
}
