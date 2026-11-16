import SwiftUI
import Testing
@testable import PermissionsUI

@Suite("Recent Changes badge suppression")
struct RecentChangesBadgeTests {
    @Test("Only Recent Changes in an active window hides the unreviewed badge")
    func suppressedOnlyInFront() {
        #expect(SidebarItem.recentChanges.suppressesUnreviewedBadge(windowIsInFront: true))
        #expect(!SidebarItem.recentChanges.suppressesUnreviewedBadge(windowIsInFront: false))
        #expect(!SidebarItem.permissions.suppressesUnreviewedBadge(windowIsInFront: true))
    }

    @Test("A key or active window is in front; an inactive one is not")
    func controlActiveStateInFront() {
        #expect(ControlActiveState.key.isInFront)
        #expect(ControlActiveState.active.isInFront)
        #expect(!ControlActiveState.inactive.isInFront)
    }
}
