import Foundation
import PermissionsCore

/// Why the Permissions scan was refused with permission denied.
public enum FullDiskAccessLoss: Sendable, Equatable {
    /// No earlier snapshot ever captured protected data: access was never on.
    case firstRun
    /// It worked before and this build differs from the last one launched.
    /// macOS ties the grant to the signature of an ad-hoc-signed build, so
    /// every update turns it off.
    case lostAfterUpdate
    /// It worked before in this same build, so someone turned it off.
    case revoked

    /// Only the Permissions scan decides: the Background Items scanner
    /// reports any unreadable file as permission denied, even with access on.
    public static func isDenied(tcc: ScanAvailability) -> Bool {
        isPermissionDenied(tcc.error)
    }

    /// `lastLaunchedVersion` is nil when no build has recorded itself yet.
    public static func classify(
        capturedBefore: Bool,
        lastLaunchedVersion: String?,
        runningVersion: String
    ) -> FullDiskAccessLoss {
        guard capturedBefore else { return .firstRun }
        return lastLaunchedVersion == runningVersion ? .revoked : .lostAfterUpdate
    }

    /// The first run has the Welcome window for this; the others open the
    /// recovery window.
    public var opensRecoveryWindow: Bool { self != .firstRun }

    private static func isPermissionDenied(_ error: ScannerError?) -> Bool {
        if case .permissionDenied = error { true } else { false }
    }
}
