import Foundation
import PermissionsCore

public struct MockTCCScanner: TCCScanner {
    public init() {}

    public func scan() async throws -> [PermissionGrant] {
        let now = Date()
        return [
            PermissionGrant(
                service: .screenRecording,
                app: AppIdentity(bundleID: "us.zoom.xos", displayName: "Zoom"),
                lastModified: now.addingTimeInterval(-86_400 * 3)
            ),
            PermissionGrant(
                service: .accessibility,
                app: AppIdentity(bundleID: "com.raycast.macos", displayName: "Raycast"),
                lastModified: now.addingTimeInterval(-86_400 * 14)
            ),
            PermissionGrant(
                service: .fullDiskAccess,
                app: AppIdentity(bundleID: "com.apple.Terminal", displayName: "Terminal"),
                lastModified: now.addingTimeInterval(-86_400 * 30)
            ),
        ]
    }
}
