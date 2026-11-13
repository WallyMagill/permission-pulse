import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite struct RecentChangesReviewTrackerTests {
    private let first = SnapshotID(rawValue: 7)
    private let second = SnapshotID(rawValue: 8)

    @Test func aScanThatArrivesWhileInTheBackgroundIsNotReviewedOnClose() {
        var tracker = RecentChangesReviewTracker()
        tracker.observe(showingRecentChanges: true, inFront: true, window: .sinceLastReview, displayedSnapshotID: first)
        tracker.observe(showingRecentChanges: true, inFront: false, window: .sinceLastReview, displayedSnapshotID: first)
        tracker.observe(showingRecentChanges: true, inFront: false, window: .sinceLastReview, displayedSnapshotID: second)

        #expect(tracker.leave() == first)
    }

    @Test func aWindowNeverInFrontReviewsNothing() {
        var tracker = RecentChangesReviewTracker()
        tracker.observe(showingRecentChanges: true, inFront: false, window: .sinceLastReview, displayedSnapshotID: second)

        #expect(tracker.leave() == nil)
    }

    @Test func viewingOnlyLastSevenDaysReviewsNothing() {
        var tracker = RecentChangesReviewTracker()
        tracker.observe(showingRecentChanges: true, inFront: true, window: .lastSevenDays, displayedSnapshotID: second)

        #expect(tracker.leave() == nil)
    }

    @Test func sinceLastReviewSeenInFrontIsReviewedOnLeavingAndOnlyOnce() {
        var tracker = RecentChangesReviewTracker()
        tracker.observe(showingRecentChanges: true, inFront: true, window: .sinceLastReview, displayedSnapshotID: first)
        tracker.observe(showingRecentChanges: true, inFront: true, window: .sinceLastReview, displayedSnapshotID: second)

        #expect(tracker.leave() == second)
        #expect(tracker.leave() == nil)
    }

    @Test func aDiffNotYetRenderedIsNotSeen() {
        var tracker = RecentChangesReviewTracker()
        tracker.observe(showingRecentChanges: true, inFront: true, window: .sinceLastReview, displayedSnapshotID: nil)
        tracker.observe(showingRecentChanges: false, inFront: true, window: .sinceLastReview, displayedSnapshotID: second)

        #expect(tracker.leave() == nil)
    }

    // After Reset All Data, snapshot IDs restart at 1: a seen ID from the
    // deleted history must not block marking the new one.
    @Test func aResetHistoryClearsTheSeenSnapshot() {
        var tracker = RecentChangesReviewTracker()
        tracker.observe(showingRecentChanges: true, inFront: true, window: .sinceLastReview, displayedSnapshotID: second)
        tracker.latestSnapshotChanged(to: nil)
        tracker.latestSnapshotChanged(to: SnapshotID(rawValue: 1))
        tracker.observe(
            showingRecentChanges: true, inFront: true, window: .sinceLastReview,
            displayedSnapshotID: SnapshotID(rawValue: 1)
        )

        #expect(tracker.leave() == SnapshotID(rawValue: 1))
    }

    @Test func aDecreasingLatestSnapshotClearsTheSeenSnapshot() {
        var tracker = RecentChangesReviewTracker()
        tracker.observe(showingRecentChanges: true, inFront: true, window: .sinceLastReview, displayedSnapshotID: second)
        tracker.latestSnapshotChanged(to: second)
        #expect(tracker.seenSnapshotID == second)

        tracker.latestSnapshotChanged(to: first)

        #expect(tracker.leave() == nil)
    }

    @MainActor @Test func resettingTheViewModelHistoryClearsWhatWasSeen() {
        let viewModel = AppViewModel()
        Self.show(second, in: viewModel)
        viewModel.latestSnapshotID = nil
        Self.show(SnapshotID(rawValue: 1), in: viewModel)

        #expect(viewModel.takeSeenRecentChanges() == SnapshotID(rawValue: 1))
    }

    @MainActor private static func show(_ id: SnapshotID, in viewModel: AppViewModel) {
        viewModel.latestSnapshotID = id
        viewModel.latestDiffSinceReview = SnapshotDiffs(
            toID: id,
            tcc: TCCGrantsDiff(added: [], removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [])
        )
        viewModel.observeRecentChanges(showing: true, inFront: true)
    }
}
