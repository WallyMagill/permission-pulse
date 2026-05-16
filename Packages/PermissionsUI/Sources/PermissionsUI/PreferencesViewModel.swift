import Foundation
import Observation

/// Bridges `PreferencesStore` to the Preferences SwiftUI surface.
///
/// View-bound bindings always use the `Double` mirrors for sliders (SwiftUI
/// `Slider` wants `Double`); the underlying store stores `Int`. Calls into
/// the digest authorization flow go through `onDigestToggle`, which the app
/// target wires to `WeeklyDigestCoordinator.handleAuthorizationToggle`.
@Observable
@MainActor
public final class PreferencesViewModel {
    public enum AuthorizationHint: Sendable, Equatable {
        case notYetRequested
        case scheduled(nextFireDescription: String)
        case denied
        case disabled
    }

    public let store: PreferencesStore
    public var authorizationHint: AuthorizationHint = .notYetRequested

    private let onDigestToggle: @MainActor (Bool) async -> AuthorizationHint

    public init(
        store: PreferencesStore,
        onDigestToggle: @escaping @MainActor (Bool) async -> AuthorizationHint = { _ in .disabled }
    ) {
        self.store = store
        self.onDigestToggle = onDigestToggle
    }

    // MARK: - Slider bindings (Double mirrors)

    public var snapshotRetentionDaysDouble: Double {
        get { Double(store.snapshotRetentionDays) }
        set { store.snapshotRetentionDays = Int(newValue) }
    }

    public var staleThresholdDaysDouble: Double {
        get { Double(store.staleThresholdDays) }
        set { store.staleThresholdDays = Int(newValue) }
    }

    // MARK: - Digest toggle

    public var digestEnabled: Bool {
        get { store.digestEnabled }
        set { store.digestEnabled = newValue }
    }

    public func handleDigestToggle(to newValue: Bool) async {
        store.digestEnabled = newValue
        authorizationHint = await onDigestToggle(newValue)
    }

    public func refreshAuthorizationHint() async {
        // Called on appear so the hint reflects the latest OS state even if
        // the user toggled notifications in System Settings while the app
        // was alive.
        authorizationHint = await onDigestToggle(store.digestEnabled)
    }
}
