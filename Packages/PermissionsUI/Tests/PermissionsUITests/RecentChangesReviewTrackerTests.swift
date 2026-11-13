import Testing
import PermissionsCore
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
}
