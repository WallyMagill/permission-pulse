import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite struct SystemSettingsLinkTests {
    @Test func everyServiceProducesANonNilURL() {
        for service in PermissionService.allCases {
            let url = SystemSettingsLink.url(for: service)
            #expect(url.absoluteString.hasPrefix("x-apple.systempreferences:com.apple.preference.security?Privacy_"))
        }
    }

    @Test func everyServiceProducesADistinctAnchor() {
        // Two services pointing at the same anchor is almost always a paste
        // error. Each TCC service has its own Settings pane.
        let urls = PermissionService.allCases.map { SystemSettingsLink.urlString(for: $0) }
        #expect(Set(urls).count == urls.count, "duplicate anchor detected")
    }

    @Test func fullDiskAccessAnchorIsStable() {
        // FDA is the one anchor we know works on every macOS we support — keep
        // an explicit assertion so a future refactor doesn't silently break it.
        #expect(
            SystemSettingsLink.urlString(for: .fullDiskAccess)
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
    }

    @Test func privacyPaneFallbackURLIsConstructable() {
        #expect(
            SystemSettingsLink.privacyPaneURL.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security"
        )
    }
}
