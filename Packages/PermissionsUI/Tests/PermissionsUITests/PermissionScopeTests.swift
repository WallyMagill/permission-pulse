import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite("PermissionScope") @MainActor
struct PermissionScopeTests {
    @Test("Only a hidden per-user database reduces the scope")
    func reducedFromUnavailableSources() {
        #expect(PermissionScope(unavailableSources: [.userTCCDatabase]).isReduced)
        #expect(!PermissionScope(unavailableSources: []).isReduced)
        #expect(!PermissionScope(unavailableSources: [.systemTCCDatabase]).isReduced)
    }

    @Test("A reduced scope hides per-user services and keeps system-level ones")
    func hiddenServices() {
        let reduced = PermissionScope.systemLevelOnly
        #expect(reduced.isHidden(.camera))
        #expect(reduced.isHidden(.filesAndFolders))
        #expect(!reduced.isHidden(.accessibility))
        #expect(!reduced.isHidden(.endpointSecurity))
        #expect(!PermissionScope.full.isHidden(.camera))
    }

    @Test("A search naming a hidden service finds it only under a reduced scope")
    func searchMatchesHiddenService() {
        let reduced = PermissionScope.systemLevelOnly
        #expect(reduced.hiddenService(matching: "Camera") == .camera)
        #expect(reduced.hiddenService(matching: " mic ") == .microphone)
        #expect(reduced.hiddenService(matching: "camera access") == .camera)
        #expect(reduced.hiddenService(matching: "Full Disk") == nil)
        #expect(reduced.hiddenService(matching: "ca") == nil)
        #expect(reduced.hiddenService(matching: "Slack") == nil)
        #expect(PermissionScope.full.hiddenService(matching: "Camera") == nil)
    }

    @Test("Hidden-service copy names the service")
    func hiddenServiceCopy() {
        #expect(PermissionScope.hiddenServiceMessage(.camera)
            == "macOS 27 doesn't let apps see which apps have Camera access")
        #expect(PermissionScope.openServiceSettingsTitle(.camera) == "Open Camera in System Settings")
    }

    @Test("A reduced empty Permissions list names the visible services, not 'no permissions'")
    func reducedEmptyStateCopy() {
        let reduced = PermissionsEmptyStateView.emptyCopy(domain: .tcc, scope: .systemLevelOnly)
        #expect(reduced.headline == "No apps hold system-level permissions")
        #expect(reduced.description.contains("Accessibility"))
        #expect(reduced.description.contains("Endpoint Security"))
        #expect(!reduced.description.contains("No app permissions have been recorded"))
        let full = PermissionsEmptyStateView.emptyCopy(domain: .tcc, scope: .full)
        #expect(full.description == "No app permissions have been recorded on this Mac.")
    }
}
