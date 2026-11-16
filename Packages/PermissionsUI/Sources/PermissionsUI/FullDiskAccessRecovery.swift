import Foundation
import Observation

/// The "turn Full Disk Access back on" loop shared by the recovery window
/// and the Welcome window: wait while the user is in System Settings, check
/// again when they come back, then confirm or offer a reopen.
@Observable
@MainActor
public final class FullDiskAccessRecovery {
    public enum Phase: Sendable, Equatable {
        /// No window is waiting on the user.
        case idle
        /// A window is open and the user may be in System Settings.
        case waiting
        case checking
        case restored
        /// Still refused after the user came back; macOS may need a restart.
        case stillDenied
    }

    public var phase: Phase = .idle
    @ObservationIgnored private var leftAppWhileWaiting = false

    public init() {}

    public func beginWaiting() {
        phase = .waiting
        leftAppWhileWaiting = false
    }

    public func end() {
        phase = .idle
        leftAppWhileWaiting = false
    }

    /// Opening the window activates the app too, so only a return after
    /// leaving it counts as the user coming back from System Settings.
    public func appResignedActive() {
        if phase == .waiting || phase == .stillDenied { leftAppWhileWaiting = true }
    }

    /// True once per return to the app while a window waits.
    public func shouldRecheckOnActivation() -> Bool {
        defer { leftAppWhileWaiting = false }
        return leftAppWhileWaiting && (phase == .waiting || phase == .stillDenied)
    }

    public nonisolated static func outcome(tcc: ScanAvailability) -> Phase {
        FullDiskAccessLoss.isDenied(tcc: tcc) ? .stillDenied : .restored
    }
}
