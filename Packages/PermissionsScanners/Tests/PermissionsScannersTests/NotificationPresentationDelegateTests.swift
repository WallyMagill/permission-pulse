import Testing
import UserNotifications
@testable import PermissionsScanners

@Suite("NotificationPresentationDelegate")
struct NotificationPresentationDelegateTests {
    @Test("foreground presentation policy shows banner, lists in Notification Center, and plays sound")
    func foregroundPolicyShowsBanner() {
        let options = NotificationPresentationDelegate.foregroundPresentationOptions

        #expect(options.contains(.banner))
        #expect(options.contains(.list))
        #expect(options.contains(.sound))
    }

    @Test("delegate is usable as a notification center delegate")
    func conformsToCenterDelegate() {
        let delegate: any UNUserNotificationCenterDelegate = NotificationPresentationDelegate()
        #expect(delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))))
    }
}
