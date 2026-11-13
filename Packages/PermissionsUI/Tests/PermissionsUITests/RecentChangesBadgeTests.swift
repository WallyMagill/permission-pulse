import Testing
@testable import PermissionsUI

@Suite("Recent Changes badge suppression")
struct RecentChangesBadgeTests {
    @Test("Only Recent Changes in an active window hides the unreviewed badge")
    func suppressedOnlyInFront() {
        #expect(SidebarItem.recentChanges.suppressesUnreviewedBadge(windowAppearsActive: true))
        #expect(!SidebarItem.recentChanges.suppressesUnreviewedBadge(windowAppearsActive: false))
        #expect(!SidebarItem.permissions.suppressesUnreviewedBadge(windowAppearsActive: true))
    }
}
